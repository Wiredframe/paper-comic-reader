//
//  ReaderStripController.swift
//  Comic Reader
//
//  The portrait strip (Settings > Reader > Portrait Strip): every page at the screen's full
//  height, side by side in one horizontal band with a one-pixel seam, scrolled freely. No paging
//  and no edge taps: the whole comic is one surface, and a tap only toggles the chrome. A double
//  tap or a pinch switches the whole band, for the moment, between two fits: full height, and a
//  typical page at exactly the screen's width. The page covering the
//  middle of the screen is the current one, so the counter, the bookmark button and the saved
//  progress all follow what is being read.
//
//  A deliberately separate controller rather than a mode of ReaderCollectionController: the
//  paging reader's slots, fit ladder, spread morph and edge taps all assume one slot per screen,
//  and none of that applies here. Keeping them apart leaves the paging reader untouched.
//
//  Widths are the one subtle part. A page at full height is as wide as its shape makes it, and
//  the shape is only known once the page has been read. The band starts from an estimate and is
//  corrected as the real shapes arrive (a header scan, see `PageImageStore.scanAspects`, and each
//  decoded page as a fallback). Every correction puts the spot in the middle of the screen back
//  exactly where it was, so the page being read never moves under the reader.
//

import UIKit
import VisionKit

/// Lays the pages out left to right at the collection view's full height, `gap` apart. Frames
/// are computed in one pass (a comic is at most a few hundred pages), so lookups are a binary
/// search. The widths come from the controller, which is the one that knows the page shapes.
final class StripLayout: UICollectionViewLayout {
    var widths: [CGFloat] = []
    var gap: CGFloat = 1
    /// How tall the pages are. Below the collection view's height the band sits centred on it.
    var bandHeight: CGFloat = 0

    private var frames: [CGRect] = []
    private var contentWidth: CGFloat = 0

    override func prepare() {
        super.prepare()
        let y = (((collectionView?.bounds.height ?? 0) - bandHeight) / 2).rounded()
        var x: CGFloat = 0
        frames = widths.map { width in
            defer { x += width + gap }
            return CGRect(x: x, y: y, width: width, height: bandHeight)
        }
        contentWidth = frames.last?.maxX ?? 0
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: contentWidth, height: collectionView?.bounds.height ?? 0)
    }

    func frame(ofPage page: Int) -> CGRect? { frames.indices.contains(page) ? frames[page] : nil }

    /// The page under `x`, a seam counting as the page to its right. Clamped to the ends.
    func page(atX x: CGFloat) -> Int? {
        guard !frames.isEmpty else { return nil }
        var low = 0, high = frames.count - 1
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].maxX + gap <= x { low = mid + 1 } else { high = mid }
        }
        return low
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard var page = page(atX: rect.minX) else { return [] }
        var result: [UICollectionViewLayoutAttributes] = []
        while page < frames.count, frames[page].minX < rect.maxX {
            result.append(attributes(page))
            page += 1
        }
        return result
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        frames.indices.contains(indexPath.item) ? attributes(indexPath.item) : nil
    }

    /// The height is what every frame hangs off, so only a height change needs a new pass; a
    /// plain scroll never does. (The controller re-derives the widths for a new height itself.)
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.height != collectionView?.bounds.height
    }

    private func attributes(_ page: Int) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: page, section: 0))
        attributes.frame = frames[page]
        return attributes
    }
}

final class ReaderStripController: UIViewController,
                                   UICollectionViewDataSource,
                                   UICollectionViewDataSourcePrefetching,
                                   UICollectionViewDelegate,
                                   ReaderControlling {

    private let store: PageImageStore
    private let settings: ReaderSettings
    let pageCount: Int
    private(set) var currentPage: Int

    var onPageChanged: ((Int) -> Void)?
    var onReachedEnd: (() -> Void)?
    var onToggleChrome: (() -> Void)?

    private let layout = StripLayout()
    private var collectionView: UICollectionView!
    private var backgroundUIColor: UIColor

    /// Each page's shape (width / height) once known, nil until then.
    private var aspects: [CGFloat?]
    /// The height the current widths were worked out for. Zero until the first layout.
    private var laidOutHeight: CGFloat = 0
    /// Open on `currentPage` at the first real layout, left edge at the screen's left edge.
    private var pendingInitialScroll = true
    /// The band is at fit-width rather than full height. Per presentation on purpose, so every
    /// comic opens at full height again.
    private var fitWidth = false
    /// A fit switch is animating. The collection view is widened for its duration (see
    /// `toggleFit`), so nothing else may lay it out or read its width meanwhile.
    private var isRefitting = false
    /// Page shapes arrived during a fit switch and are applied once it lands.
    private var needsRelayout = false
    /// A pinch switches the fit once per gesture, however far it goes on.
    private var pinchStepped = false

    /// A US comic page (6.625 × 10.25 in), for the shape of a page nothing is known about yet
    /// while no other page is known either.
    private static let fallbackAspect: CGFloat = 0.65
    /// How far the middle of the screen has to be into the next page before it becomes the
    /// current one, so the counter can't flicker while a seam rests on the middle.
    private static let hysteresis: CGFloat = 12
    /// Release speed (points per millisecond) from which a snap rides the fling's own momentum;
    /// anything slower settles with a fixed-length animated scroll (see `scrollViewWillEndDragging`).
    private static let flingVelocity: CGFloat = 0.5
    /// How far a pinch has to go before it switches the fit.
    private static let pinchThreshold: CGFloat = 0.15

    init(store: PageImageStore, settings: ReaderSettings, startIndex: Int, backgroundColor: UIColor) {
        self.store = store
        self.settings = settings
        self.pageCount = max(store.pageCount, 0)
        self.currentPage = min(max(startIndex, 0), max(pageCount - 1, 0))
        self.backgroundUIColor = backgroundColor
        self.aspects = Array(repeating: nil, count: max(store.pageCount, 0))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Orientation is deliberately left alone: the app's mask is portrait while the reader is up
    // unless the paging reader frees it, and the strip never does, so the reader simply stays
    // portrait. ReaderView still locks portrait on close, as for the paging reader.

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = backgroundUIColor

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.delegate = self
        collectionView.isPagingEnabled = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.alwaysBounceVertical = false
        collectionView.backgroundColor = backgroundUIColor
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(StripPageCell.self, forCellWithReuseIdentifier: StripPageCell.reuseID)
        view.addSubview(collectionView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        collectionView.addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.require(toFail: doubleTap)
        collectionView.addGestureRecognizer(tap)
        collectionView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch)))

        store.setActivePage(currentPage)
        store.prefetch(around: currentPage, maxPixel: ReaderPageCell.displayMaxPixel)
        store.scanAspects(from: currentPage) { [weak self] found in self?.learn(found) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isRefitting else { return }   // the switch restores the frame when it lands
        collectionView.frame = view.bounds
        let height = collectionView.bounds.height
        guard height > 0, pageCount > 0 else { return }
        if pendingInitialScroll {
            pendingInitialScroll = false
            applyWidths()
            show(page: currentPage)
            notifyPageChange()
        } else if height != laidOutHeight {
            relayoutKeepingPosition()   // iPad multitasking, a size change the strip must follow
        }
    }

    // MARK: ReaderControlling

    /// Single versus double page is a landscape matter, and the strip is portrait only.
    func syncLayoutMode() {}

    func setBackground(_ color: UIColor) {
        guard color != backgroundUIColor else { return }
        backgroundUIColor = color
        viewIfLoaded?.backgroundColor = color
        collectionView?.backgroundColor = color
    }

    /// Rebuilds the visible pages (the paper effect changed). The widths don't depend on it, so
    /// the band stays exactly where it is.
    func reloadCurrent() {
        collectionView.reloadData()
    }

    /// Page grid / bookmark jump: the page's left edge to the screen's left edge.
    func jump(to page: Int) {
        let target = min(max(page, 0), max(pageCount - 1, 0))
        // Current first, so the scroll below finds the middle already on it and leaves it be
        // (unless the end of the band holds the page short of the left edge, which it then says).
        let previous = currentPage
        currentPage = target
        show(page: target)
        if currentPage == target, target != previous { notifyPageChange() }
    }

    // MARK: Widths

    /// Takes in newly known page shapes, and re-lays the band if any of them changes a width.
    private func learn(_ found: [Int: CGFloat]) {
        var changed = false
        for (page, aspect) in found where aspects.indices.contains(page) && aspects[page] == nil {
            aspects[page] = aspect
            changed = true
        }
        guard changed, laidOutHeight > 0 else { return }
        if isRefitting { needsRelayout = true } else { relayoutKeepingPosition() }
    }

    /// A page with no known shape yet borrows the typical one of the pages that are known (the
    /// median, so one wide spread doesn't stretch every unknown page).
    private var estimatedAspect: CGFloat {
        let known = aspects.compactMap { $0 }.sorted()
        return known.isEmpty ? Self.fallbackAspect : known[known.count / 2]
    }

    /// Works out every page's width for the current fit and lays the band out with them. False,
    /// touching nothing, when nothing would change: most shapes the header scan brings in match
    /// the estimate to the pixel, and those must not disturb a scroll or a snap under way.
    @discardableResult
    private func applyWidths() -> Bool {
        let height = collectionView.bounds.height
        let scale = max(traitCollection.displayScale, 1)
        let estimate = estimatedAspect
        let band = bandHeight(screen: view.bounds.size, estimate: estimate, scale: scale)
        // Whole device pixels, so every seam is exactly one pixel and never smears across two.
        let widths = aspects.map { (band * ($0 ?? estimate) * scale).rounded() / scale }
        guard widths != layout.widths || band != layout.bandHeight || height != laidOutHeight else {
            return false
        }
        layout.widths = widths
        layout.gap = 1 / scale
        layout.bandHeight = band
        layout.invalidateLayout()
        laidOutHeight = height
        collectionView.layoutIfNeeded()
        return true
    }

    /// Full height, or at fit-width as tall as a typical page is at exactly the screen's width.
    /// The reader's Zoom setting is deliberately not applied: it sizes a lone page in the paging
    /// reader, and here the band's neighbours already frame the page. Never taller than the
    /// screen: where a full-height page is already no wider than that (an iPad in portrait), the
    /// two fits are simply the same.
    private func bandHeight(screen: CGSize, estimate: CGFloat, scale: CGFloat) -> CGFloat {
        guard fitWidth, estimate > 0 else { return screen.height }
        let height = screen.width / estimate
        return min((height * scale).rounded() / scale, screen.height)
    }

    /// New widths, with the spot in the middle of the screen put back where it was: measured as a
    /// fraction of the page under it, so a page that changes width keeps the same part of itself
    /// in the middle. Pages further left may still grow or shrink, but the one being read holds.
    private func relayoutKeepingPosition() {
        let width = collectionView.bounds.width
        let middle = collectionView.contentOffset.x + width / 2
        let anchor = layout.page(atX: middle) ?? currentPage
        var fraction: CGFloat = 0
        if let frame = layout.frame(ofPage: anchor), frame.width > 0 {
            fraction = (middle - frame.minX) / frame.width
        }
        guard applyWidths(), let frame = layout.frame(ofPage: anchor) else { return }
        setOffset(frame.minX + fraction * frame.width - collectionView.bounds.width / 2)
    }

    /// Puts `page`'s left edge at the screen's left edge (or as near as the ends of the band allow).
    private func show(page: Int) {
        guard let frame = layout.frame(ofPage: page) else { return }
        setOffset(frame.minX)
    }

    private func setOffset(_ x: CGFloat) {
        let maxX = max(layout.collectionViewContentSize.width - collectionView.bounds.width, 0)
        collectionView.contentOffset = CGPoint(x: min(max(x, 0), maxX), y: 0)
    }

    // MARK: Fit switch (double tap, pinch)

    /// Switches the whole band between full height and fit-width, keeping the spot under
    /// `point` (in the controller's view) where it is.
    ///
    /// A real zoom: the animation only SCALES what is on screen, as one transform on the render
    /// server, so nothing is re-laid out mid-flight and the spot under the finger can't drift.
    /// The new layout is swapped in underneath once it lands, matching the last frame. Going
    /// smaller, the collection view is first widened past both screen edges so the neighbouring
    /// pages that come into view already have cells to be scaled in with.
    private func toggleFit(at point: CGPoint) {
        guard !isRefitting, laidOutHeight > 0 else { return }
        let bounds = view.bounds
        let contentX = collectionView.contentOffset.x + point.x
        let anchor = layout.page(atX: contentX) ?? currentPage
        guard let before = layout.frame(ofPage: anchor), before.width > 0 else { return }
        let fraction = (contentX - before.minX) / before.width
        let oldBand = layout.bandHeight

        fitWidth.toggle()
        let scale = max(traitCollection.displayScale, 1)
        let newBand = bandHeight(screen: bounds.size, estimate: estimatedAspect, scale: scale)
        guard newBand != oldBand, oldBand > 0 else { return }   // both fits the same size here
        let ratio = newBand / oldBand

        // Stop any fling first, so it can't keep moving the band under the animation.
        collectionView.setContentOffset(collectionView.contentOffset, animated: false)
        isRefitting = true
        let extra = ratio < 1 ? (bounds.width * (1 / ratio - 1)).rounded(.up) : 0
        let screenOffset = collectionView.contentOffset.x
        collectionView.frame = bounds.insetBy(dx: -extra, dy: 0)
        collectionView.contentOffset.x = screenOffset - extra   // same picture, wider window
        collectionView.layoutIfNeeded()

        // The final layout decides where the spot lands; the transform is solved to put it there.
        let landing = finalLanding(anchor: anchor, fraction: fraction, point: point, newBand: newBand)
        // Scale about the screen's centre (the band stays vertically centred in both fits), then
        // shift so the spot at `point.x` arrives at `landing.spotX`.
        let centreX = bounds.midX
        let shiftX = landing.spotX - centreX - ratio * (point.x - centreX)
        let zoom = CGAffineTransform(translationX: shiftX, y: 0).scaledBy(x: ratio, y: ratio)

        UIView.animate(withDuration: settings.fitToggleDuration, delay: 0, options: [.curveEaseInOut]) {
            self.collectionView.transform = zoom
        } completion: { _ in
            UIView.performWithoutAnimation {
                self.collectionView.transform = .identity
                self.collectionView.frame = self.view.bounds
                self.applyWidths()
                self.collectionView.contentOffset.x = landing.offset
                self.collectionView.layoutIfNeeded()
            }
            self.isRefitting = false
            if self.needsRelayout {
                self.needsRelayout = false
                self.relayoutKeepingPosition()
            }
            self.trackCurrentPage()
        }
    }

    /// Where the band will rest after a fit switch to `newBand`: its scroll offset, and the screen
    /// x the spot (`fraction` into page `anchor`) will then be at. Pure arithmetic over the page
    /// shapes, so it can be known before the layout is actually swapped.
    private func finalLanding(anchor: Int, fraction: CGFloat, point: CGPoint,
                              newBand: CGFloat) -> (offset: CGFloat, spotX: CGFloat) {
        let scale = max(traitCollection.displayScale, 1)
        let estimate = estimatedAspect
        let gap = 1 / scale
        var minX: CGFloat = 0, pageWidth: CGFloat = 0, contentWidth: CGFloat = 0
        for (page, aspect) in aspects.enumerated() {
            let width = (newBand * (aspect ?? estimate) * scale).rounded() / scale
            if page == anchor { minX = contentWidth; pageWidth = width }
            contentWidth += width + (page < aspects.count - 1 ? gap : 0)
        }
        let spot = minX + fraction * pageWidth
        let maxX = max(contentWidth - view.bounds.width, 0)
        let offset = min(max(spot - point.x, 0), maxX)
        return (offset, spot - offset)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        toggleFit(at: gesture.location(in: view))
    }

    /// One step per pinch, in the direction it goes: in towards full height, out towards
    /// fit-width. Never a free scale; the band only ever rests at one of the two fits.
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStepped = false
        case .changed:
            guard !pinchStepped else { return }
            let smaller = gesture.scale < 1 - Self.pinchThreshold
            let bigger = gesture.scale > 1 + Self.pinchThreshold
            guard (smaller && !fitWidth) || (bigger && fitWidth) else { return }
            pinchStepped = true
            toggleFit(at: gesture.location(in: view))
        default:
            break
        }
    }

    // MARK: Current page

    /// The page being read: the one under the middle of the screen, held until the middle is
    /// clearly into a neighbour. At either end of the band the end page counts, even when it is
    /// too narrow to ever reach the middle, so the first and last pages can always be current.
    private func trackCurrentPage() {
        let width = collectionView.bounds.width
        guard !isRefitting, width > 0, laidOutHeight > 0, pageCount > 0 else { return }
        let x = collectionView.contentOffset.x
        let maxX = layout.collectionViewContentSize.width - width
        let page: Int
        if x <= 0.5 {
            page = 0
        } else if x >= maxX - 0.5 {
            page = pageCount - 1
        } else {
            let middle = x + width / 2
            if let frame = layout.frame(ofPage: currentPage),
               middle >= frame.minX - Self.hysteresis, middle <= frame.maxX + Self.hysteresis {
                return
            }
            guard let under = layout.page(atX: middle) else { return }
            page = under
        }
        guard page != currentPage else { return }
        currentPage = page
        notifyPageChange()
    }

    private func notifyPageChange() {
        store.setActivePage(currentPage)
        store.prefetch(around: currentPage, maxPixel: ReaderPageCell.displayMaxPixel)
        onPageChanged?(currentPage)
        if pageCount > 0, currentPage == pageCount - 1 { onReachedEnd?() }
    }

    @objc private func handleTap() {
        // A tap that dismisses a Live Text selection is spent on that, not on the chrome.
        for case let cell as StripPageCell in collectionView.visibleCells where cell.hasTextSelection {
            return
        }
        onToggleChrome?()
    }

    // MARK: Data source

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { pageCount }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: StripPageCell.reuseID, for: indexPath) as! StripPageCell
        cell.configure(page: indexPath.item, store: store, settings: settings) { [weak self] page, aspect in
            // The header scan missed this one; the image knows. Never re-lays out right here:
            // a cached image arrives synchronously, inside the collection view's own cell request.
            DispatchQueue.main.async { self?.learn([page: aspect]) }
        }
        return cell
    }

    func collectionView(_ cv: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            store.prefetchImage(at: indexPath.item, maxPixel: ReaderPageCell.displayMaxPixel)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { trackCurrentPage() }

    /// Soft snapping. A real fling runs out on its own momentum and only its resting point is
    /// moved, so the band eases into place as it slows. A slow release is different: handed a
    /// target, UIKit stretches its deceleration over the whole distance to it, and a page that
    /// was let go almost at rest would creep the last stretch into place. That case stops where
    /// it is and settles with the scroll view's own fixed-length animated scroll instead, so every
    /// snap takes as long.
    ///
    /// Deliberately NOT `UIView.animate` on `contentOffset`: that moves the model offset to the
    /// end at once, the collection view drops every cell not visible THERE, and the neighbouring
    /// page vanished while the band was still sliding it out. An animated scroll lays out as it
    /// goes, like any other scroll, and a finger landing on it simply takes over.
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard !isRefitting else { return }
        let natural = targetContentOffset.pointee.x
        let rest = restingOffset(near: natural)
        guard rest != natural else { return }
        if abs(velocity.x) >= Self.flingVelocity {
            targetContentOffset.pointee.x = rest
            return
        }
        targetContentOffset.pointee = scrollView.contentOffset
        DispatchQueue.main.async {   // after UIKit has taken the stop, or it would cancel this
            scrollView.setContentOffset(CGPoint(x: rest, y: scrollView.contentOffset.y), animated: true)
        }
    }

    /// Where the band may come to rest near `x`: anywhere inside one page, but never with a seam
    /// on screen. At full height a page is wider than the screen and has to be free to stop
    /// part-way across, so only a resting point that would straddle two pages is moved, to
    /// whichever is nearer: the left page's right edge at the screen's right edge, or the right
    /// page's left edge at the screen's left edge. At fit-width a page is about the screen's
    /// width, so nearly every stop straddles one and this settles on whole pages.
    private func restingOffset(near x: CGFloat) -> CGFloat {
        let width = collectionView.bounds.width
        let maxX = max(layout.collectionViewContentSize.width - width, 0)
        guard width > 0, x > 0, x < maxX,
              let page = layout.page(atX: x), let frame = layout.frame(ofPage: page),
              x + width > frame.maxX + 0.5 else { return x }   // one page fills the screen
        let leftPageEnd = frame.width >= width ? frame.maxX - width : frame.minX
        let rightPageStart = layout.frame(ofPage: page + 1)?.minX ?? maxX
        let rest = abs(x - leftPageEnd) <= abs(rightPageStart - x) ? leftPageEnd : rightPageStart
        return min(max(rest, 0), maxX)
    }
}

/// One page of the strip: the image filling the cell, which the layout has already shaped to the
/// page. Nothing to fit, zoom or pan.
final class StripPageCell: UICollectionViewCell {
    static let reuseID = "StripPageCell"

    private let imageView = UIImageView()
    private let liveText = ImageAnalysisInteraction()
    private static let analyzer = ImageAnalyzer()
    /// How long a page has to stay before its text is analysed for Live Text.
    private static let liveTextDelay: Duration = .milliseconds(500)
    private var loadToken = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Fill, not fit: the cell already has the page's shape, and while it is still an estimate
        // a slight crop reads better than a sliver of mat down one side.
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true   // Live Text needs a live view to hang off
        contentView.addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken += 1
        imageView.image = nil
        imageView.removeInteraction(liveText)
        liveText.analysis = nil   // don't carry the old page's text into the reused cell
    }

    func configure(page: Int, store: PageImageStore, settings: ReaderSettings,
                   onShape: @escaping (Int, CGFloat) -> Void) {
        loadToken += 1
        let token = loadToken
        store.requestImage(at: page, maxPixel: ReaderPageCell.displayMaxPixel) { [weak self] index, image in
            guard let self, self.loadToken == token, index == page, let image else { return }
            self.imageView.image = image
            if image.size.height > 0 { onShape(page, image.size.width / image.size.height) }
            if settings.liveText { self.setupLiveText(image) }
        }
    }

    /// A Live Text selection is up, which the tap landing now dismisses on its own.
    var hasTextSelection: Bool { liveText.hasActiveTextSelection }

    private func setupLiveText(_ image: UIImage) {
        guard ImageAnalyzer.isSupported else { return }
        if !imageView.interactions.contains(where: { $0 === liveText }) {
            imageView.addInteraction(liveText)
        }
        liveText.preferredInteractionTypes = .textSelection
        liveText.setSupplementaryInterfaceHidden(true, animated: false)
        let token = loadToken
        Task { [weak self] in
            // Only for a page that stays: flinging along the band passes page after page, and
            // analysing each of them would keep the CPU busy with text nobody stops to select.
            try? await Task.sleep(for: Self.liveTextDelay)
            guard self?.loadToken == token else { return }
            let config = ImageAnalyzer.Configuration([.text])
            let analysis = try? await Self.analyzer.analyze(image, configuration: config)
            // The cell may have moved on to another page while this ran.
            guard let self, self.loadToken == token, let analysis else { return }
            self.liveText.analysis = analysis
        }
    }
}
