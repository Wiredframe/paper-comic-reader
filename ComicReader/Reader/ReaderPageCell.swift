//
//  ReaderPageCell.swift
//  Comic Reader
//
//  One "slot" of the reader: a single page (portrait / double-page off) or a
//  two-page spread (landscape double-page). There is deliberately NO pinch zoom —
//  a double-tap toggles the fit instead:
//
//    • Single page:  fit-width  ⇄  fit-height
//    • Spread:       both pages (each half width) ⇄ the tapped page zoomed to full
//                    width. Both pages stay laid out, so the zoom animates in place
//                    (no black flash) and you can pan to the other page. The scroll
//                    view's directional lock keeps vertical reading clean while a
//                    deliberate horizontal drag pans across.
//
//  Everything is done by sizing the image views inside a plain, non-zooming scroll
//  view. Pages are centred by their FRAME (not contentInset, which stays zero) inside
//  a content area of at least the bounds: it stays put when it fits and pans when it
//  doesn't. Keeping the inset at zero is what makes a rotation smooth — only frames
//  change, and those animate inside the turn, so nothing snaps.
//

import UIKit
import VisionKit

protocol ReaderPageCellDelegate: AnyObject {
    /// A single tap that wasn't consumed by tap-scroll — the controller decides
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
        case spread            // both pages fit-width-combined (each half), vertical only
        case focus(Int)        // both pages at fit-width each, scrolled to page 0 / 1
    }

    private let scrollView = UIScrollView()
    private let pageViews = [UIImageView(), UIImageView()]       // [left, right]
    private let liveText = [ImageAnalysisInteraction(), ImageAnalysisInteraction()]
    private let analyzer = ImageAnalyzer()
    private var tapScrollAnimator: UIViewPropertyAnimator?       // render-server tap-scroll step

    private(set) var slotIndex = -1
    private var pageIndices: [Int] = []          // 1 or 2 global page indices
    private var images: [UIImage?] = []
    private var loadToken = 0
    private var fit: Fit = .fitWidth
    /// True only when `.focus` was entered by a deliberate double-tap zoom, so the
    /// configurable fit-width zoom applies to it. The rotation morph also uses `.focus`,
    /// but as a full-width endpoint that must NOT be zoomed — it leaves this false.
    private var focusZoomEnabled = false
    private var isDouble = false
    private var lastLaidOutBounds: CGSize = .zero
    /// The vertical offset the last tap-scroll aimed at (nil = derive from the live
    /// offset). Advancing from this — not the mid-animation offset — is what makes
    /// two fast taps still reach the bottom. Reset on drag / re-layout.
    private var tapTargetY: CGFloat?
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
        // Reading a zoomed spread: a drag locks to the axis it starts in, so vertical
        // reading never sloshes sideways, but a deliberate horizontal drag still pans
        // to the other page.
        scrollView.isDirectionalLockEnabled = true
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
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
        stopTapScroll()
        images = []
        pageIndices = []
        lastLaidOutBounds = .zero
        tapTargetY = nil
        for (i, view) in pageViews.enumerated() {
            view.image = nil
            view.isHidden = true
            view.removeInteraction(liveText[i])
            liveText[i].analysis = nil   // don't carry the old page's text into the reused cell
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
        self.fit = isDouble ? .spread : .fitWidth
        self.focusZoomEnabled = false
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
    /// stuck fit-height never greets you on the way back.
    func resetToDefault() {
        guard !images.isEmpty else { return }
        fit = isDouble ? .spread : .fitWidth
        lastLaidOutBounds = .zero
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Drive one endpoint of the portrait⇄landscape rotation morph on a spread cell.
    /// `.focus` is the PORTRAIT look — the reader's page fills the width with its partner
    /// waiting exactly one screen-width off the adjoining edge — and `.spread` is the
    /// settled LANDSCAPE spread. The controller flips between the two *inside* the rotation
    /// animation, so the page slides into (or grows out of) its half while the partner
    /// glides in / out, instead of the single page and the spread cross-dissolving.
    /// `focusPos` is the page's side in the pair (0 = left, 1 = right); a lone page (cover
    /// or an unpaired last page) has no partner, so both endpoints simply fit the width.
    func setRotationSpread(_ spread: Bool, focusPos: Int) {
        fit = spread ? .spread : .focus(focusPos)
        focusZoomEnabled = false     // the morph's focus is a full-width endpoint, never zoomed
        lastLaidOutBounds = .zero
        setNeedsLayout()
        layoutIfNeeded()
    }

    // MARK: Layout

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
            let duration = settings?.fitToggleDuration ?? 0.25
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.curveEaseInOut, .beginFromCurrentState]) {
                self.performLayout(in: bounds)
            }
        } else {
            performLayout(in: bounds)
        }
    }

    private func performLayout(in bounds: CGSize) {
        // The fit-width zoom applies only in landscape (in portrait a page already fits
        // its width comfortably). For a focused spread page it applies only to a
        // deliberate double-tap zoom — never the rotation morph.
        let landscape = bounds.width > bounds.height
        let zoom = landscape ? CGFloat(settings?.doubleTapZoom ?? 1.0) : 1.0
        switch fit {
        case .fitWidth:     place([fitWidth(0, in: bounds, zoom: zoom)], in: bounds, focusColumn: nil)
        case .fitHeight:    place([fitHeight(0, in: bounds)], in: bounds, focusColumn: nil)
        case .spread:       place(spreadSizes(in: bounds), in: bounds, focusColumn: nil)
        case .focus(let i): placeFocus(focusSizes(in: bounds, zoom: focusZoomEnabled ? zoom : 1.0),
                                       focused: pageIndices.count > 1 ? i : 0, in: bounds)
        }
        updateLiveTextEnabled(landscape: landscape)
        tapTargetY = nil          // the scroll position was just reset by the layout
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

    /// A page filling the width (fit-width): as tall as its aspect makes it. `zoom` < 1
    /// narrows it (centred, more height on screen) for the configurable fit-width level.
    private func fitWidth(_ i: Int, in bounds: CGSize, zoom: CGFloat = 1.0) -> CGSize {
        let r = aspect(i)
        let w = bounds.width * zoom
        return CGSize(width: w, height: r > 0 ? w / r : bounds.height)
    }

    /// A page filling the height (fit-height): as wide as its aspect makes it.
    private func fitHeight(_ i: Int, in bounds: CGSize) -> CGSize {
        let r = aspect(i)
        return CGSize(width: r > 0 ? bounds.height * r : bounds.width, height: bounds.height)
    }

    /// Both pages sharing one height so together they fill the width exactly (→ no
    /// horizontal scroll; only vertical if the spread is taller than the screen).
    private func spreadSizes(in bounds: CGSize) -> [CGSize] {
        let two = pageIndices.count > 1
        let rL = aspect(0)
        let rR = two ? aspect(1) : 0
        let total = rL + rR
        let h = total > 0 ? bounds.width / total : bounds.height
        var sizes = [CGSize(width: h * rL, height: h)]
        if two { sizes.append(CGSize(width: h * rR, height: h)) }
        return sizes
    }

    /// Both pages at fit-width(*zoom) each, side by side — you pan between them.
    private func focusSizes(in bounds: CGSize, zoom: CGFloat = 1.0) -> [CGSize] {
        var sizes = [fitWidth(0, in: bounds, zoom: zoom)]
        if pageIndices.count > 1 { sizes.append(fitWidth(1, in: bounds, zoom: zoom)) }
        return sizes
    }

    /// Lay the page view(s) out in a horizontal row and centre the row in `bounds` on
    /// whichever axis it's smaller. The scroll content is at least the bounds — so it
    /// stays put when it fits and pans when it doesn't — and `contentInset` stays ZERO.
    /// That's the point: on a rotation only the frames change, which animate inside the
    /// turn, so there's no inset/offset snap (smooth regardless of the chrome). A
    /// `focusColumn` scrolls that page to the left edge (spread focus); else it centres.
    private func place(_ sizes: [CGSize], in bounds: CGSize, focusColumn: Int?) {
        let rowWidth = sizes.reduce(0) { $0 + $1.width }
        let rowHeight = sizes.map(\.height).max() ?? bounds.height
        let contentW = max(rowWidth, bounds.width)
        let contentH = max(rowHeight, bounds.height)
        let startX = (contentW - rowWidth) / 2

        var x = startX
        for (i, size) in sizes.enumerated() {
            pageViews[i].frame = CGRect(x: x, y: (contentH - size.height) / 2,
                                        width: size.width, height: size.height)
            pageViews[i].isHidden = false
            x += size.width
        }
        for i in sizes.count..<pageViews.count { pageViews[i].isHidden = true }

        scrollView.contentInset = .zero
        scrollView.contentSize = CGSize(width: contentW, height: contentH)
        if let focusColumn, focusColumn < sizes.count {
            let colX = startX + sizes.prefix(focusColumn).reduce(0) { $0 + $1.width }
            scrollView.contentOffset = CGPoint(x: min(colX, contentW - bounds.width), y: 0)
        } else {
            scrollView.contentOffset = CGPoint(x: (contentW - bounds.width) / 2, y: 0)
        }
    }

    /// Focus placement for a spread: each page at fit-width(*zoom), the focused page
    /// centred horizontally like single-page fit-width, the other poking in from the
    /// side. Symmetric side padding lets an edge page centre too. At zoom 1 this exactly
    /// reproduces the old full-width, edge-aligned focus (and the rotation morph's
    /// portrait endpoint).
    private func placeFocus(_ sizes: [CGSize], focused: Int, in bounds: CGSize) {
        guard let pageW = sizes.first?.width else { return }
        let sidePad = max(0, (bounds.width - pageW) / 2)
        let rowWidth = pageW * CGFloat(sizes.count)
        let contentW = rowWidth + 2 * sidePad
        let contentH = max(sizes.map(\.height).max() ?? bounds.height, bounds.height)

        var x = sidePad
        for (i, size) in sizes.enumerated() {
            pageViews[i].frame = CGRect(x: x, y: (contentH - size.height) / 2,
                                        width: size.width, height: size.height)
            pageViews[i].isHidden = false
            x += pageW
        }
        for i in sizes.count..<pageViews.count { pageViews[i].isHidden = true }

        scrollView.contentInset = .zero
        scrollView.contentSize = CGSize(width: contentW, height: contentH)
        scrollView.contentOffset = CGPoint(x: focusColumnOffsetX(focused, in: bounds), y: 0)
    }

    /// Content-offset x that centres focus column `col` — the source of truth for both
    /// `placeFocus` and the tap-scroll cross-over, so they always agree.
    private func focusColumnOffsetX(_ col: Int, in bounds: CGSize? = nil) -> CGFloat {
        let size = bounds ?? scrollView.bounds.size
        let landscape = size.width > size.height
        let zoom = (landscape && focusZoomEnabled) ? CGFloat(settings?.doubleTapZoom ?? 1.0) : 1.0
        let pageW = size.width * zoom
        let sidePad = max(0, (size.width - pageW) / 2)
        let contentW = pageW * CGFloat(max(pageIndices.count, 1)) + 2 * sidePad
        let center = sidePad + (CGFloat(col) + 0.5) * pageW
        return min(max(center - size.width / 2, 0), max(0, contentW - size.width))
    }

    // MARK: Gestures

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard !images.isEmpty else { return }
        if isDouble {
            // Spread ⇄ zoom the tapped page (fit-width * zoom, centred), animated in place
            // (both pages stay laid out → smooth zoom, no black flash, pan to the other).
            switch fit {
            case .focus: fit = .spread
            default:
                fit = .focus(tappedPage(atX: gesture.location(in: self).x))
                focusZoomEnabled = true      // deliberate zoom → honour the fit-width zoom setting
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
        // Tap-to-navigate (opt-in): step down / up the page a half at a time. In a
        // zoomed spread it also steps left→right across the two pages before turning.
        // At the very edge it falls through to the controller (prev / next / chrome).
        // When disabled, every tap falls through (→ the controller toggles the chrome).
        if settings?.tapToNavigate == true {
            if x < bounds.width * 0.25, tapScroll(forward: false) { return }
            if x > bounds.width * 0.75, tapScroll(forward: true) { return }
        }
        delegate?.pageCell(self, didSingleTapAtX: x, width: bounds.width)
    }

    /// One tap-navigation step. Returns false at the very end so the controller turns
    /// the page. A zoomed spread steps across both pages (fit-width) before that.
    private func tapScroll(forward: Bool) -> Bool {
        // Landscape double-page OVERVIEW (both pages visible): no in-page step-scroll — a
        // tap turns the page like every other view. Returning false lets handleSingleTap
        // fall through to the controller (prev / next / chrome).
        if case .spread = fit { return false }
        if case .focus(let column) = fit, pageIndices.count > 1 {
            return focusTapScroll(forward: forward, column: column)
        }
        return scrollColumn(forward: forward, columnX: scrollView.contentOffset.x)
    }

    /// Scrolls the current column up / down by exactly one half of its *scrollable*
    /// range, so the true top / bottom is always reached in exactly two taps — even
    /// when tapping fast, because it advances from the last committed target rather
    /// than the (possibly mid-animation) live offset. Two, not three, because the top
    /// portion is already on screen at rest. Returns false at the edge, so the
    /// controller turns the page.
    private func scrollColumn(forward: Bool, columnX: CGFloat) -> Bool {
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        guard maxY > 1 else { return false }              // page fits → no vertical scroll
        let step = maxY / 2
        let base = tapTargetY ?? scrollView.contentOffset.y
        let index = (base / step).rounded()               // which half we're on (0…2)
        let target: CGFloat
        if forward {
            guard index < 1.5 else { return false }        // at the bottom → turn the page
            target = index + 1 >= 2 ? maxY : (index + 1) * step
        } else {
            guard index > 0.5 else { return false }        // at the top → turn the page
            target = (index - 1) * step
        }
        tapTargetY = target
        animateTapScroll(to: CGPoint(x: columnX, y: target))
        return true
    }

    /// Animate a tap-scroll step with a Core Animation property animator, so — like the
    /// double-tap zoom — it runs on the render server at the full ProMotion rate instead of a
    /// main-thread per-frame loop. Standard iOS ease-in-out, on a quicker duration than a page
    /// turn. Restarting from the live offset (`.beginFromCurrentState` semantics of stopping
    /// the previous animator) means two fast taps chain straight through to the page end.
    private func animateTapScroll(to offset: CGPoint) {
        stopTapScroll()
        let animator = UIViewPropertyAnimator(duration: settings?.tapScrollDuration ?? 0.25,
                                              curve: .easeInOut) { [weak self] in
            self?.scrollView.contentOffset = offset
        }
        animator.startAnimation()
        tapScrollAnimator = animator
    }

    /// Stop an in-flight tap-scroll, leaving the page at its current on-screen position so a
    /// drag — or the next tap — continues from there.
    private func stopTapScroll() {
        if tapScrollAnimator?.state == .active { tapScrollAnimator?.stopAnimation(true) }
        tapScrollAnimator = nil
    }

    /// Tap-scroll inside a zoomed spread: scroll the focused page; at its bottom cross
    /// to the OTHER page at fit-width (keeping the zoom); only past the last page does
    /// it return false, so the controller turns to the next / previous spread — which
    /// resets the zoom. `column` is the focused page (0 = left, 1 = right).
    private func focusTapScroll(forward: Bool, column: Int) -> Bool {
        if scrollColumn(forward: forward, columnX: focusColumnOffsetX(column)) { return true }
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        if forward {
            guard column == 0 else { return false }        // right page finished → next spread
            fit = .focus(1)
            tapTargetY = 0
            animateTapScroll(to: CGPoint(x: focusColumnOffsetX(1), y: 0))
        } else {
            guard column == 1 else { return false }        // left page top → previous spread
            fit = .focus(0)
            tapTargetY = maxY
            animateTapScroll(to: CGPoint(x: focusColumnOffsetX(0), y: maxY))
        }
        updateLiveTextEnabled(landscape: bounds.width > bounds.height)
        return true
    }

    // MARK: Live Text

    private func setupLiveText(_ pos: Int, _ image: UIImage) {
        guard settings?.liveText == true, ImageAnalyzer.isSupported, pos < liveText.count else { return }
        let interaction = liveText[pos]
        if pageViews[pos].interactions.contains(where: { $0 === interaction }) == false {
            pageViews[pos].addInteraction(interaction)
        }
        interaction.setSupplementaryInterfaceHidden(true, animated: false)
        updateLiveTextEnabled(landscape: scrollView.bounds.width > scrollView.bounds.height)
        let token = loadToken
        Task { [weak self] in
            guard let self else { return }
            let config = ImageAnalyzer.Configuration([.text])
            let analysis = try? await self.analyzer.analyze(image, configuration: config)
            // The cell may have been reused for another page while analysis ran — only
            // apply it if this is still that page's load (mirrors the image-load guard).
            guard self.loadToken == token, let analysis else { return }
            interaction.analysis = analysis
        }
    }

    /// Live Text press-and-hold selection is only offered where a whole page is
    /// shown at a comfortable size — fit-height in portrait, fit-width in landscape —
    /// so it never competes with the reading scroll or the spread overview.
    private func updateLiveTextEnabled(landscape: Bool) {
        let enabled: Bool
        switch fit {
        case .fitHeight: enabled = !landscape
        case .fitWidth:  enabled = landscape
        case .focus:     enabled = landscape   // pages are at fit-width here
        case .spread:    enabled = false
        }
        for interaction in liveText {
            interaction.preferredInteractionTypes = enabled ? .textSelection : []
        }
    }
}

extension ReaderPageCell: UIScrollViewDelegate {
    /// A manual drag takes over from any in-flight tap-scroll and invalidates the
    /// tap-scroll target, so the next tap picks up from wherever the user left the page.
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        stopTapScroll()
        tapTargetY = nil
    }
}
