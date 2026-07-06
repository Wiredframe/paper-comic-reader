//
//  ReaderPageCell.swift
//  Comic Reader
//
//  One "slot" of the reader: a single page (portrait / double-page off) or a
//  two-page spread (landscape double-page). There is deliberately NO pinch zoom —
//  a double-tap toggles the fit instead, which keeps the layout 100% predictable
//  and drift-free:
//
//    • Single page:  fit-width  ⇄  fit-height
//    • Spread:       both pages ⇄  the tapped page at fit-width (the other beside it)
//
//  Everything is done by sizing the image views inside a plain, non-zooming scroll
//  view (contentSize > bounds ⇒ pan; contentSize ≤ bounds ⇒ centred, no scroll).
//

import UIKit
import VisionKit

protocol ReaderPageCellDelegate: AnyObject {
    /// A single tap that wasn't consumed by thirds-scroll — the controller decides
    /// prev / next / toggle-chrome from the tap's horizontal position.
    func pageCell(_ cell: ReaderPageCell, didSingleTapAtX x: CGFloat, width: CGFloat)
}

final class ReaderPageCell: UICollectionViewCell {

    static let reuseID = "ReaderPageCell"
    static let displayMaxPixel: CGFloat = 2200

    /// How the slot's page(s) fill the screen.
    private enum Fit {
        case fitWidth          // single page fills the width (may scroll vertically)
        case fitHeight         // single page fills the height (whole page, letterboxed)
        case fitSpread         // two pages contained side by side (both fully visible)
        case focus(Int)        // spread zoomed so the tapped page (0/1) is fit-width
    }

    private let scrollView = UIScrollView()
    private let pageViews = [UIImageView(), UIImageView()]       // [left, right]
    private let liveText = [ImageAnalysisInteraction(), ImageAnalysisInteraction()]
    private let analyzer = ImageAnalyzer()

    private(set) var slotIndex = -1
    private var pageIndices: [Int] = []          // 1 or 2 global page indices
    private var images: [UIImage?] = []
    private var loadToken = 0
    private var fit: Fit = .fitWidth
    private var isDouble = false
    private var lastLaidOutBounds: CGSize = .zero
    private var settings: ReaderSettings?
    private weak var delegate: ReaderPageCellDelegate?

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = true
        contentView.backgroundColor = .clear

        scrollView.frame = contentView.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bounces = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.backgroundColor = .clear
        contentView.addSubview(scrollView)

        for view in pageViews {
            view.backgroundColor = .clear
            view.contentMode = .scaleAspectFit
            scrollView.addSubview(view)
        }

        let double = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        double.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        single.numberOfTapsRequired = 1
        single.require(toFail: double)
        scrollView.addGestureRecognizer(single)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken += 1
        images = []
        pageIndices = []
        lastLaidOutBounds = .zero
        for (i, view) in pageViews.enumerated() {
            view.image = nil
            view.isHidden = true
            view.removeInteraction(liveText[i])
        }
        scrollView.contentInset = .zero
        scrollView.contentOffset = .zero
    }

    // MARK: Configure

    func configure(slotIndex: Int, pageIndices: [Int], isDouble: Bool,
                   store: PageImageStore, settings: ReaderSettings,
                   delegate: ReaderPageCellDelegate) {
        self.slotIndex = slotIndex
        self.pageIndices = pageIndices
        self.isDouble = isDouble
        self.settings = settings
        self.delegate = delegate
        self.fit = isDouble ? .fitSpread : .fitWidth
        self.images = Array(repeating: nil, count: pageIndices.count)
        self.lastLaidOutBounds = .zero
        pageViews[1].isHidden = pageIndices.count < 2

        loadToken += 1
        let token = loadToken
        for pos in pageIndices.indices {
            let page = pageIndices[pos]
            store.requestImage(at: page, maxPixel: Self.displayMaxPixel) { [weak self] index, image in
                guard let self, self.loadToken == token, index == page,
                      pos < self.images.count, let image else { return }
                self.images[pos] = image
                self.pageViews[pos].image = image
                self.pageViews[pos].isHidden = false
                self.setupLiveText(pos, image)
                self.lastLaidOutBounds = .zero          // re-fit now that a page arrived
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
        }
    }

    /// Back to the slot's default fit (called when it scrolls off screen), so a
    /// stuck fit-height / focus state never greets you on the way back.
    func resetToDefault() {
        guard !images.isEmpty else { return }
        fit = isDouble ? .fitSpread : .fitWidth
        lastLaidOutBounds = .zero
        setNeedsLayout()
        layoutIfNeeded()
    }

    // MARK: Layout

    // Re-fits on any bounds change. During a device rotation UIKit calls this inside
    // the rotation's animation transaction, so the image-view frame changes here
    // animate along with the rotation for free — no manual coordinator work needed,
    // and it behaves the same whether the chrome (and status bar) is shown or hidden.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !images.isEmpty else { return }
        let bounds = scrollView.bounds.size
        guard bounds.width > 0, bounds != lastLaidOutBounds else { return }
        lastLaidOutBounds = bounds
        performLayout(in: bounds)
    }

    private func applyLayout(animated: Bool) {
        let bounds = scrollView.bounds.size
        guard !images.isEmpty, bounds.width > 0 else { return }
        lastLaidOutBounds = bounds
        if animated {
            let duration = settings?.fastAnimations == true ? 0.2 : 0.32
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.curveEaseInOut, .beginFromCurrentState]) {
                self.performLayout(in: bounds)
            }
        } else {
            performLayout(in: bounds)
        }
    }

    private func performLayout(in bounds: CGSize) {
        switch fit {
        case .fitWidth:     layoutSingle(fillWidth: true, in: bounds)
        case .fitHeight:    layoutSingle(fillWidth: false, in: bounds)
        case .fitSpread:    layoutSpread(in: bounds)
        case .focus(let i): layoutFocus(page: i, in: bounds)
        }
    }

    /// Aspect (w/h) of page `i`, falling back to a sibling / typical page while it loads.
    private func aspect(_ i: Int) -> CGFloat {
        if i < images.count, let image = images[i], image.size.height > 0 {
            return image.size.width / image.size.height
        }
        if let loaded = images.compactMap({ $0 }).first, loaded.size.height > 0 {
            return loaded.size.width / loaded.size.height
        }
        return 2.0 / 3.0
    }

    private func layoutSingle(fillWidth: Bool, in bounds: CGSize) {
        let r = aspect(0)
        let width: CGFloat, height: CGFloat
        if fillWidth {
            width = bounds.width
            height = r > 0 ? width / r : bounds.height
        } else {
            height = bounds.height
            width = height * r
        }
        pageViews[0].frame = CGRect(x: 0, y: 0, width: width, height: height)
        pageViews[1].isHidden = true
        scrollView.contentSize = CGSize(width: width, height: height)
        center(in: bounds)
        scrollView.contentOffset = topLeftOffset()
    }

    private func layoutSpread(in bounds: CGSize) {
        let two = pageIndices.count > 1
        let rL = aspect(0)
        let rR = two ? aspect(1) : 0
        let totalAspect = rL + rR                       // combined width / common height
        let height = min(bounds.height, totalAspect > 0 ? bounds.width / totalAspect : bounds.height)
        let wL = height * rL
        let wR = height * rR
        pageViews[0].frame = CGRect(x: 0, y: 0, width: wL, height: height)
        pageViews[1].isHidden = !two
        if two { pageViews[1].frame = CGRect(x: wL, y: 0, width: wR, height: height) }
        scrollView.contentSize = CGSize(width: wL + wR, height: height)
        center(in: bounds)
        scrollView.contentOffset = topLeftOffset()
    }

    private func layoutFocus(page i: Int, in bounds: CGSize) {
        let two = pageIndices.count > 1
        let height = aspect(i) > 0 ? bounds.width / aspect(i) : bounds.height   // focused page fills width
        let wL = height * aspect(0)
        let wR = two ? height * aspect(1) : 0
        pageViews[0].frame = CGRect(x: 0, y: 0, width: wL, height: height)
        pageViews[1].isHidden = !two
        if two { pageViews[1].frame = CGRect(x: wL, y: 0, width: wR, height: height) }
        scrollView.contentSize = CGSize(width: wL + wR, height: height)
        center(in: bounds)
        // Horizontally reveal the focused page; vertically start at the top.
        let pageX = (i == 0) ? 0 : wL
        let pageW = (i == 0) ? wL : wR
        let maxX = max(0, scrollView.contentSize.width - bounds.width)
        let targetX = min(max(pageX + pageW / 2 - bounds.width / 2, 0), maxX)
        let x = scrollView.contentInset.left > 0 ? -scrollView.contentInset.left : targetX
        scrollView.contentOffset = CGPoint(x: x, y: -scrollView.contentInset.top)
    }

    private func center(in bounds: CGSize) {
        let content = scrollView.contentSize
        let insetX = max(0, (bounds.width - content.width) / 2)
        let insetY = max(0, (bounds.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    private func topLeftOffset() -> CGPoint {
        CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
    }

    // MARK: Gestures

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard !images.isEmpty else { return }
        if isDouble {
            switch fit {
            case .focus: fit = .fitSpread
            default:     fit = .focus(tappedPage(atX: gesture.location(in: self).x))
            }
        } else {
            fit = isFitWidth ? .fitHeight : .fitWidth
        }
        applyLayout(animated: true)
    }

    private var isFitWidth: Bool {
        if case .fitWidth = fit { return true }
        return false
    }

    private func tappedPage(atX x: CGFloat) -> Int {
        guard pageIndices.count > 1 else { return 0 }
        return x < bounds.width / 2 ? 0 : 1
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: self).x
        // Page-by-page thirds scroll only makes sense on a single, vertically
        // scrollable page — never in a spread.
        if !isDouble, settings?.thirdsScroll == true {
            if x < bounds.width * 0.25, scrollByThird(forward: false) { return }
            if x > bounds.width * 0.75, scrollByThird(forward: true) { return }
        }
        delegate?.pageCell(self, didSingleTapAtX: x, width: bounds.width)
    }

    private func scrollByThird(forward: Bool) -> Bool {
        let visible = scrollView.bounds.height
        let content = scrollView.contentSize.height
        guard content > visible + 1 else { return false }
        let maxY = content - visible
        let step = content / 3
        let y = scrollView.contentOffset.y
        if forward {
            guard y < maxY - 1 else { return false }
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: min(maxY, y + step)), animated: true)
        } else {
            guard y > 1 else { return false }
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: max(0, y - step)), animated: true)
        }
        return true
    }

    // MARK: Live Text

    private func setupLiveText(_ pos: Int, _ image: UIImage) {
        guard settings?.liveText == true, ImageAnalyzer.isSupported, pos < liveText.count else { return }
        let interaction = liveText[pos]
        if pageViews[pos].interactions.contains(where: { $0 === interaction }) == false {
            pageViews[pos].addInteraction(interaction)
        }
        interaction.preferredInteractionTypes = .textSelection
        interaction.setSupplementaryInterfaceHidden(true, animated: false)
        Task { [weak self] in
            guard let self else { return }
            let config = ImageAnalyzer.Configuration([.text])
            if let analysis = try? await self.analyzer.analyze(image, configuration: config) {
                interaction.analysis = analysis
            }
        }
    }
}
