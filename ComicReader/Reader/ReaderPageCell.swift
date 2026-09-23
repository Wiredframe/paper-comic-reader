//
//  ReaderPageCell.swift
//  Comic Reader
//
//  One "slot" of the landscape reader: a single page (double-page off) or a two-page
//  spread. Portrait is the strip (ReaderStripController), which doesn't use this cell.
//
//  There is no free magnification. Both gestures move between named fits instead, which
//  is what keeps the layout frame-based (see below) and keeps every move animatable:
//
//    • Pinch  steps along the fit ladder, one rung per pinch:
//        Single page:  fit-height  ⇄  fit-width
//        Spread:       whole spread  ⇄  fit-width spread  ⇄  one page zoomed
//    • Double tap toggles the ends of that ladder directly:
//        Single page:  fit-width  ⇄  fit-height
//        Spread:       both pages (each half width) ⇄ the tapped page zoomed to full
//                      width. Both pages stay laid out, so the zoom animates in place,
//                      with no black flash.
//
//  Every reading layout makes the scroll content exactly as wide as the slot, so there is
//  no horizontal travel to be had and a drag can only ever move up and down. Which page of
//  a spread is being read is carried by the FRAMES (`placeFocus` shifts the row), not by a
//  scroll position, so the facing page is reached by an edge tap or a double tap.
//
//  Everything is done by sizing the image views inside a plain, non-zooming scroll
//  view. Pages are centred by their FRAME (not contentInset, which stays zero) inside
//  a content area of at least the bounds: it stays put when it fits and pans when it
//  doesn't. Keeping the inset at zero is what makes a size change smooth: only frames
//  change, and those animate inside the turn, so nothing snaps.
//
//  One shadow tracks the union of those frames, so the page — or the whole spread —
//  rests on the letterbox mat without a seam down the gutter (see `layoutShadow`).
//

import UIKit
import VisionKit

protocol ReaderPageCellDelegate: AnyObject {
    /// A single tap that wasn't consumed by tap-scroll — the controller decides
    /// prev / next / toggle-chrome from the tap's horizontal position.
    func pageCell(_ cell: ReaderPageCell, didSingleTapAtX x: CGFloat, width: CGFloat)

    /// The spread's focus moved to a specific half (a double-tap zoom, or a tap-scroll that
    /// crossed to the other page). The controller makes that global page the current one, so
    /// rotation and bookmarking act on the page actually being read, not always the left half.
    func pageCell(_ cell: ReaderPageCell, didFocusPageAt globalIndex: Int)

    /// A double tap zoomed the spread into one page (`true`) or put it back down to the whole
    /// spread (`false`). Cells are recycled, so the controller keeps this: it's what Keep Zoom
    /// Across Pages carries to the next slot (see `FocusEntry`).
    func pageCell(_ cell: ReaderPageCell, didChangeFitWidthFocus focused: Bool)

    /// A sideways swipe that the slot itself can't answer: it is zoomed into the last half in
    /// that direction, so the reader should turn to the next / previous slot. Only sent while the
    /// slot owns sideways navigation (see `ownsSidewaysNavigation`); every other view lets the
    /// collection view page the swipe itself.
    func pageCell(_ cell: ReaderPageCell, didRequestTurn forward: Bool)

    /// `ownsSidewaysNavigation` flipped because the slot's layout changed on its own (a fit change,
    /// a page image arriving and making the page wider than the screen), so the controller should
    /// hand the paging over or take it back.
    func pageCellDidChangeSidewaysOwnership(_ cell: ReaderPageCell)
}

final class ReaderPageCell: UICollectionViewCell {

    static let reuseID = "ReaderPageCell"

    /// How much background shows between the two halves of a double page when Page Gap is on.
    /// Deliberately a fixed, small metric rather than a second slider: it's there to tell the two
    /// halves apart, and anything wide enough to notice as a space stops reading as one spread.
    /// A hairline is the whole point: enough to feel where one page ends, not enough to read as
    /// a margin. Tried at 6 and 3 first; both looked like the spread had been pulled apart.
    static let spreadGap: CGFloat = 1

    /// How far two facing scans may differ in aspect and still be laid out as one shape (see
    /// `aspect(_:)`). Trim variance between two scans of the same comic is a fraction of a percent,
    /// so this sits well clear of it while staying far below a page whose proportions differ for a
    /// REASON: a true landscape spread stored as one wide image, a differently scanned inside
    /// cover, an ad page. `ReaderPaging` pairs purely by index and never looks at a page's shape,
    /// so those really do land in a pair, and harmonising them would crop away artwork rather than
    /// a scanner edge. At this limit the taller scan gives up about 1% of its height at each edge;
    /// on the scans it's meant for it gives up a handful of pixels.
    static let pairAspectTolerance: CGFloat = 0.02

    /// How far a pinch has to travel before it steps to the next fit. Deliberately asymmetric:
    /// fingers spread further than they close, so the same felt effort needs a larger number
    /// going out than coming in. One step per pinch, whatever happens after the threshold, so a
    /// long pinch can't run up the whole ladder at once (see `handlePinch`).
    static let pinchOutThreshold: CGFloat = 1.25
    static let pinchInThreshold: CGFloat = 0.8

    /// What counts as a sideways swipe on a zoomed spread half: either a drag past a quarter of
    /// the screen or a flick, whichever comes first. Both, because the page does not follow the
    /// finger here — with nothing moving under the hand there is no rubber band to tell you how
    /// far is far enough, so a slow drag has to succeed on distance and a quick one on speed.
    static let swipeDistanceFraction: CGFloat = 0.25
    static let swipeVelocity: CGFloat = 500

    /// How a slot looks the moment it goes on screen. The controller decides this, because it is
    /// the only place that knows how the reader arrived; the cell just does as it's told.
    enum Opening: Equatable {
        /// The slot's own default: the whole spread, or a plain fit-width single page.
        case standard
        /// One half at fit-width (Keep Zoom Across Pages), resting at that page's top or, entered
        /// from behind while reading backward, at its bottom.
        case page(column: Int, atEnd: Bool)
    }

    /// How the slot's page(s) fill the screen. This is the whole layout state: every case says
    /// everything `performLayout` needs, so nothing about the fit can drift into a second flag.
    private enum Fit {
        case fitWidth          // single page fills the width (may scroll vertically)
        case fitHeight         // single page fills the height (whole page, letterboxed)
        case spread            // both pages fit-width-combined (each half), vertical only
        /// Both pages sized to the slot's HEIGHT, so the whole spread is on screen at once and
        /// nothing scrolls. The pair's counterpart to `.fitHeight`, and the rung below `.spread`.
        case spreadHeight
        /// Both pages at the configurable fit-width zoom each, the row shifted to `column`
        /// (0 = left, 1 = right).
        case focus(column: Int)
    }

    private let scrollView = UIScrollView()
    /// Drawn behind the page(s) — see `layoutShadow(around:)`.
    private let pageShadow = UIView()
    private let pageViews = [UIImageView(), UIImageView()]       // [left, right]
    private let liveText = [ImageAnalysisInteraction(), ImageAnalysisInteraction()]
    private let analyzer = ImageAnalyzer()
    private var tapScrollAnimator: UIViewPropertyAnimator?       // render-server tap-scroll step

    private var singleTap: UITapGestureRecognizer?
    private var doubleTap: UITapGestureRecognizer?
    /// Touch-down x captured in `shouldReceive`, read back in `shouldRequireFailureOf`
    /// (whose own `location(in:)` isn't reliable there). Cell (`self`) coordinate space.
    private var pendingTapDownX: CGFloat?

    /// Pinch-to-fit. The pinch changes which named fit the slot is in and nothing else: there is
    /// no transform, no magnification state, and so nothing that could fight the frame-based
    /// layout or the zero `contentInset` the size changes rely on. See the `// MARK: Pinch` section.
    private var zoomPinch: UIPinchGestureRecognizer?
    /// One step per pinch: set the moment a pinch crosses a threshold, cleared when it begins.
    private var pinchDidStep = false
    /// Sideways navigation on a zoomed spread half, where a swipe means "the other half" rather
    /// than "the next spread" — see `ownsSidewaysNavigation`.
    private var sidewaysPan: UIPanGestureRecognizer?
    /// The current sideways swipe has already been answered (it went far enough mid-drag), so its
    /// end must not answer it a second time.
    private var sidewaysPanHandled = false

    private(set) var slotIndex = -1
    private var pageIndices: [Int] = []          // 1 or 2 global page indices
    private var images: [UIImage?] = []
    private var loadToken = 0
    private var fit: Fit = .fitWidth
    /// The slot was opened at the bottom of its focused page (`Opening.page(atEnd: true)`, a
    /// backward page change), so `placeFocus` rests it there instead of at the top. Deliberately
    /// NOT part of `fit`: it describes the arrival, not the layout, and stops being true of the
    /// slot the moment the reader moves it (see `readerTookOver`). It does survive the extra
    /// layouts a slot gets while its images arrive, which is the whole reason it's stored.
    private var openAtBottom = false
    /// The slot still rests at its default fit, nobody has double-tapped or pinched it. For a
    /// single page that is fit-width, re-applied at every layout so a size change keeps it.
    private var fitIsStandard = true
    /// The last `ownsSidewaysNavigation` the controller was told about, so a layout only reports a
    /// real flip. Nil after reuse: the first layout of a new slot always reports.
    private var reportedSidewaysOwnership: Bool?
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
        // Reading layouts have no horizontal travel at all: `place` and `placeFocus` both make the
        // content exactly as wide as the slot, so a drag has nowhere sideways to go and the page
        // simply holds still. The one exception is a fit-height page WIDER than the screen (a
        // spread scanned as one image), which does need panning — the axis lock is here for that
        // page and only that page, so reading down it doesn't slosh.
        scrollView.isDirectionalLockEnabled = true
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        contentView.addSubview(scrollView)

        // Added before the pages, so it stays behind them however they're laid out.
        pageShadow.isUserInteractionEnabled = false
        pageShadow.isHidden = true
        ReaderMetrics.applyPageShadow(to: pageShadow.layer)
        scrollView.addSubview(pageShadow)

        for view in pageViews {
            view.backgroundColor = .clear
            // Aspect-FILL with clipping, not aspect-fit. Every frame this cell builds already
            // carries its own page's aspect, so for anything but a harmonised pair the two modes
            // draw identical pixels. Where they differ is exactly the case `aspect(_:)` creates:
            // two facing scans handed one shape, where fill is what crops the taller scan's
            // surplus away instead of letterboxing it inside its half. A letterbox there would
            // leave a hairline of mat down the gutter, the one place it would be noticed.
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            scrollView.addSubview(view)
        }

        let double = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        double.numberOfTapsRequired = 2
        double.delegate = self
        scrollView.addGestureRecognizer(double)
        doubleTap = double

        // No static `single.require(toFail: double)`: the failure requirement is set per
        // tap by location in the UIGestureRecognizerDelegate below, so edge taps (page
        // turn / tap-scroll) fire instantly while the centre keeps the clean double-tap
        // zoom. A static requirement couldn't be lifted per tap by the delegate.
        let single = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        single.numberOfTapsRequired = 1
        single.delegate = self
        scrollView.addGestureRecognizer(single)
        singleTap = single

        // Pinch to step the fit. On contentView (above the scroll view) so it still reads while
        // the scroll view is handling a drag. Two-finger, so it never competes with the
        // single / double taps. Section: Pinch.
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        contentView.addGestureRecognizer(pinch)
        zoomPinch = pinch

        // Sideways navigation, but only while this slot is zoomed into one half of a spread; the
        // gesture delegate below refuses to begin otherwise, so in every other view the swipe
        // reaches the collection view and pages exactly as it always has.
        let sideways = UIPanGestureRecognizer(target: self, action: #selector(handleSidewaysPan(_:)))
        sideways.delegate = self
        contentView.addGestureRecognizer(sideways)
        sidewaysPan = sideways
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
        pendingTapDownX = nil           // the next touch re-captures it in shouldReceive
        reportedSidewaysOwnership = nil
        pageShadow.isHidden = true      // no stale shadow before the new slot lays out
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

    /// Fill the cell with a slot's pages. How the slot will LOOK isn't decided here: a cell is
    /// often built long before it is shown, so that is settled in `prepareForDisplay(_:)`.
    func configure(slotIndex: Int, pageIndices: [Int], isDouble: Bool,
                   store: PageImageStore, settings: ReaderSettings,
                   delegate: ReaderPageCellDelegate) {
        self.slotIndex = slotIndex
        self.pageIndices = pageIndices
        self.isDouble = isDouble
        self.settings = settings
        self.delegate = delegate
        apply(.standard)
        self.images = Array(repeating: nil, count: pageIndices.count)
        self.lastLaidOutBounds = .zero
        pageViews[1].isHidden = pageIndices.count < 2

        loadToken += 1
        let token = loadToken
        for pos in pageIndices.indices {
            let page = pageIndices[pos]
            store.requestImage(at: page) { [weak self] index, image in
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

    /// Back to the slot's default fit, called when it scrolls off screen, so a stuck fit-height
    /// never greets you on the way back. What it will actually open at is settled when it is shown
    /// again, in `prepareForDisplay(_:)`.
    func resetToDefault() {
        guard !images.isEmpty else { return }
        apply(.standard)
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Settle how the slot looks, right before it goes on screen. THE one place a slot's look is
    /// decided, deliberately not `configure`: the collection view builds cells ahead of time and
    /// shows them again without rebuilding them, so anything decided at build time would be shown
    /// as it was whenever that happened to be. It re-fits the pages and puts the scroll back at the
    /// slot's resting position, which is what an arriving slot wants; nothing is animated, and a
    /// slot whose images haven't arrived is skipped by `layoutSubviews` and re-fitted when they do.
    func prepareForDisplay(_ opening: Opening) {
        apply(opening)
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// The single writer of the opening state: one `Opening` in, `fit` and the arrival flag out,
    /// so they can't be set apart from each other.
    ///
    /// `.page` continues a deliberate double-tap zoom, so it honours the chosen zoom level. A slot
    /// holding a single page (the cover, an unpaired last page) takes it too: `.focus` is fit-width
    /// there just like `.spread`, but unlike `.spread` it honours the chosen zoom level.
    private func apply(_ opening: Opening) {
        switch opening {
        case .page(let column, let atEnd) where isDouble && !pageIndices.isEmpty:
            fit = .focus(column: min(max(column, 0), pageIndices.count - 1))
            openAtBottom = atEnd
        default:
            fit = isDouble ? .spread : .fitWidth
            openAtBottom = false
        }
        fitIsStandard = true
        lastLaidOutBounds = .zero
    }

    /// The reader has taken the page over (a tap-scroll, a drag, a double tap), so where it was
    /// ENTERED no longer describes where it rests. Only the layouts that still belong to the
    /// arrival, including the re-fits while the images arrive, put the page at its bottom.
    private func readerTookOver() { openAtBottom = false }

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
        let zoom = fitWidthZoom
        if fitIsStandard, !isDouble { fit = .fitWidth }
        switch fit {
        case .fitWidth:  place([fitWidth(0, in: bounds, zoom: zoom)], in: bounds)
        case .fitHeight: place([fitHeight(0, in: bounds)], in: bounds)
        case .spread:    place(spreadSizes(in: bounds), in: bounds)
        case .spreadHeight: place(spreadHeightSizes(in: bounds), in: bounds)
        case .focus(let column):
            placeFocus(focusSizes(in: bounds, zoom: zoom),
                       focused: pageIndices.count > 1 ? column : 0, in: bounds)
        }
        updateLiveTextEnabled()
        tapTargetY = nil          // the scroll position was just reset by the layout
        let owns = ownsSidewaysNavigation
        if owns != reportedSidewaysOwnership {
            reportedSidewaysOwnership = owns
            delegate?.pageCellDidChangeSidewaysOwnership(self)
        }
    }

    /// How wide a page fills the screen at fit-width (Settings > Zoom), 1 = the full width.
    private var fitWidthZoom: CGFloat { CGFloat(settings?.doubleTapZoom ?? 1.0) }

    /// Aspect (w/h) of page `i` as the LAYOUT should use it.
    ///
    /// Where two facing scans differ only by trim variance (the same comic, a few pixels of
    /// difference in the JPEGs), both halves report the shorter page's aspect, so everything
    /// downstream measures the pair as one shape: equal widths, the gutter exactly on the screen's
    /// centre line, the same scale on both halves, and a shadow outline that matches the pages
    /// instead of overhanging the shorter one.
    ///
    /// Without it the mismatch still has to go somewhere, and it goes somewhere different in every
    /// layout: `spreadSizes` shares one height, so it surfaces as unequal widths and an off-centre
    /// gutter; `focusSizes` shares one width, so it surfaces as unequal heights, and since each
    /// page is centred vertically on its own, the artwork steps a few points as you pan across the
    /// gutter. One harmonised aspect settles all three at once, because all three read from here.
    ///
    /// The taller scan's surplus is then cropped by the page views' `.scaleAspectFill`, in equal
    /// parts top and bottom. Taking the SHORTER page (the LARGER w/h) as the target is what keeps
    /// the crop on that axis: with both aspects at or below the frame's, a page can only ever
    /// overflow vertically, so neither can be cut at the gutter or the outer trim, which is where
    /// a comic's artwork actually runs to the edge and where the eye follows the panel borders.
    /// Harmonising to the average would halve the crop, but it would move part of it onto exactly
    /// those two edges.
    ///
    /// Pairs only, and only within `pairAspectTolerance`. A lone page (the cover, an unpaired last
    /// page, every slot outside double mode) has no facing page to agree with and keeps its own
    /// aspect, which is also why `.fitHeight` is never touched: it is reachable only when the slot
    /// holds a single page.
    private func aspect(_ i: Int) -> CGFloat {
        guard pageIndices.count > 1 else { return rawAspect(i) }
        let left = rawAspect(0), right = rawAspect(1)
        let target = max(left, right)          // the larger w/h is the SHORTER page
        guard target > 0,
              abs(left - right) / target <= Self.pairAspectTolerance else { return rawAspect(i) }
        return target
    }

    /// The page's own aspect (w/h), falling back to a sibling / typical page while it loads.
    private func rawAspect(_ i: Int) -> CGFloat {
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

    /// Is `.fitHeight` the tighter of the two single-page fits for this slot?
    ///
    /// Normally not: in landscape a page is the narrower shape, so fit-width is the close-up. Only
    /// a page proportionally wider than the screen (a panorama) turns it round, since filling the
    /// height then pushes it out past both sides. The pinch reads this so that spreading the
    /// fingers always moves toward the closer fit.
    private var fitHeightIsCloser: Bool {
        let bounds = scrollView.bounds.size
        guard bounds.width > 0, bounds.height > 0 else { return false }
        return aspect(0) > bounds.width / bounds.height
    }

    /// A page filling the height (fit-height): as wide as its aspect makes it.
    private func fitHeight(_ i: Int, in bounds: CGSize) -> CGSize {
        let r = aspect(i)
        return CGSize(width: r > 0 ? bounds.height * r : bounds.width, height: bounds.height)
    }

    /// The gutter between this slot's two halves: `spreadGap` when Page Gap is on, else nothing.
    /// Zero for a slot holding a single page, which has no facing page to be separated from.
    /// Every layout that puts two pages in a row reads it from here, so they can't disagree about
    /// how wide the row is, and a row measured wrong is dead scroll travel past the page.
    private var pageGap: CGFloat {
        (settings?.pageGap == true && pageIndices.count > 1) ? Self.spreadGap : 0
    }

    /// Both pages sharing one height so together they fill the width exactly (→ no
    /// horizontal scroll; only vertical if the spread is taller than the screen).
    private func spreadSizes(in bounds: CGSize) -> [CGSize] {
        let two = pageIndices.count > 1
        let rL = aspect(0)
        let rR = two ? aspect(1) : 0
        let total = rL + rR
        // The gutter comes out of the width the two pages share, so the pair PLUS the gap still
        // fills the slot exactly and the spread stays free of horizontal scroll.
        let available = max(1, bounds.width - pageGap)
        let h = total > 0 ? available / total : bounds.height
        var sizes = [CGSize(width: h * rL, height: h)]
        if two { sizes.append(CGSize(width: h * rR, height: h)) }
        return sizes
    }

    /// Both pages sharing the slot's full HEIGHT, so the whole spread is on screen at once. The
    /// pair's `.fitHeight`: nothing scrolls, and the mat shows either side of it. In landscape a
    /// spread is far taller than the screen at fit-width, so this is the only way to see both
    /// facing pages whole — the reason the pinch has a rung below `.spread` at all.
    ///
    /// The gutter is NOT taken out of the width here the way `spreadSizes` has to take it: this
    /// row is measured from the height and then centred, so the gap simply widens the row rather
    /// than pushing it off the screen.
    private func spreadHeightSizes(in bounds: CGSize) -> [CGSize] {
        let h = bounds.height
        var sizes = [CGSize(width: h * aspect(0), height: h)]
        if pageIndices.count > 1 { sizes.append(CGSize(width: h * aspect(1), height: h)) }
        return sizes
    }

    /// Both pages at fit-width(*zoom) each, side by side — you pan between them.
    private func focusSizes(in bounds: CGSize, zoom: CGFloat = 1.0) -> [CGSize] {
        var sizes = [fitWidth(0, in: bounds, zoom: zoom)]
        if pageIndices.count > 1 { sizes.append(fitWidth(1, in: bounds, zoom: zoom)) }
        return sizes
    }

    /// Lay the page view(s) out in a horizontal row and centre the row in `bounds` on
    /// whichever axis it's smaller. The scroll content is at least the bounds, so it stays put
    /// when it fits and pans when it doesn't, and `contentInset` stays ZERO: a size change or a
    /// fit change then only moves frames, which animate, so nothing snaps.
    ///
    /// Always centres, including a fit-width page narrowed by the fit-width zoom: Align to Screen
    /// Edges is about a spread's two halves, and a lone page has no facing page to hand the spare
    /// width to. Spread focus goes through `placeFocus` instead.
    private func place(_ sizes: [CGSize], in bounds: CGSize) {
        let gap = sizes.count > 1 ? pageGap : 0
        let rowWidth = sizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(sizes.count - 1, 0))
        let rowHeight = sizes.map(\.height).max() ?? bounds.height
        let contentW = max(rowWidth, bounds.width)
        let contentH = max(rowHeight, bounds.height)
        let startX = (contentW - rowWidth) / 2

        var x = startX
        for (i, size) in sizes.enumerated() {
            pageViews[i].frame = CGRect(x: x, y: (contentH - size.height) / 2,
                                        width: size.width, height: size.height)
            pageViews[i].isHidden = false
            x += size.width + gap
        }
        for i in sizes.count..<pageViews.count { pageViews[i].isHidden = true }
        layoutShadow(around: sizes.count)

        scrollView.contentInset = .zero
        scrollView.contentSize = CGSize(width: contentW, height: contentH)
        scrollView.contentOffset = CGPoint(x: (contentW - bounds.width) / 2, y: 0)
    }

    /// Focus placement for a spread: each page at fit-width(*zoom), the focused page brought to
    /// rest by `focusColumnOffsetX` (centred, or against its own screen edge with Align to Screen
    /// Edges on), the other poking in from the side. At zoom 1 both settings give the same
    /// full-width, edge-aligned focus.
    ///
    /// The only space between the two pages is `pageGap`, so with Page Gap off they still touch and
    /// the spread casts one unbroken shadow; what Align to Screen Edges changes is the empty margin
    /// AROUND the pair (see `focusSidePad`).
    private func placeFocus(_ sizes: [CGSize], focused: Int, in bounds: CGSize) {
        guard let pageW = sizes.first?.width else { return }
        let sidePad = focusSidePad(pageWidth: pageW, in: bounds, pageCount: sizes.count)
        let gap = sizes.count > 1 ? pageGap : 0
        let contentH = max(sizes.map(\.height).max() ?? bounds.height, bounds.height)

        // Which page is being read is expressed by SHIFTING THE ROW, not by scrolling to it. That
        // is what makes the focus vertical-only without a single rule about gestures: the content
        // is exactly as wide as the slot, so there is no horizontal travel for a drag to find. The
        // facing page hangs outside that width and is simply clipped until a tap brings it over,
        // and because the shift lives in the frames it animates with every other frame change.
        var x = sidePad - focusColumnOffsetX(focused, in: bounds)
        for (i, size) in sizes.enumerated() {
            pageViews[i].frame = CGRect(x: x, y: (contentH - size.height) / 2,
                                        width: size.width, height: size.height)
            pageViews[i].isHidden = false
            x += pageW + gap
        }
        for i in sizes.count..<pageViews.count { pageViews[i].isHidden = true }
        layoutShadow(around: sizes.count)

        scrollView.contentInset = .zero
        scrollView.contentSize = CGSize(width: bounds.width, height: contentH)
        // Normally the page rests at its top; a slot entered from a backward page change rests at
        // its bottom instead, so reading backward continues where reading forward would have left off.
        scrollView.contentOffset = CGPoint(x: 0, y: openAtBottom ? max(0, contentH - bounds.height) : 0)
    }

    /// Wrap the `count` pages just laid out in ONE shadow, sized to the union of their frames,
    /// so the page reads as a sheet resting on the letterbox mat rather than a picture pasted
    /// onto it.
    ///
    /// With Page Gap OFF the path is that single enclosing rectangle, and that is what keeps the
    /// spread's gutter clean: the two halves touch, so one shadow around the pair has nowhere to
    /// draw between them. The whole spread casts one shadow, like the real open comic it's
    /// imitating. (A shadow per page would seam straight down the middle of a solid spread.)
    ///
    /// With Page Gap ON there IS a gutter, and the halves should read as two sheets, so the path
    /// becomes one subpath per page and each casts into the gap. Still one shadow layer either
    /// way; only the path differs, and the setting can't change mid-spread, so the subpath count
    /// stays fixed across any animation.
    ///
    /// It follows that the shadow is only ever *seen* where a page doesn't reach the slot's edge,
    /// since the scroll view clips there: around a fit-height page or spread, beside a
    /// sub-full-width fit-width page, and in the gutter. Where the page runs to the screen edge
    /// there's no mat to catch a shadow anyway.
    ///
    /// `shadowPath` is set explicitly for two reasons: Core Animation then never derives the
    /// shadow from the layer's alpha channel (an offscreen pass every frame), and, being an
    /// animatable layer property set here alongside the frames, it tweens inside a fit change
    /// instead of snapping.
    private func layoutShadow(around count: Int) {
        guard settings?.pageShadow == true, count > 0 else {
            pageShadow.isHidden = true
            return
        }
        var union = pageViews[0].frame
        for view in pageViews.prefix(count).dropFirst() { union = union.union(view.frame) }
        pageShadow.isHidden = false
        pageShadow.frame = union

        let path = UIBezierPath()
        if pageGap > 0, count > 1 {
            // The frames are in the scroll view's space; the path wants the shadow view's own.
            for view in pageViews.prefix(count) {
                path.append(UIBezierPath(rect: view.frame.offsetBy(dx: -union.minX, dy: -union.minY)))
            }
        } else {
            path.append(UIBezierPath(rect: pageShadow.bounds))
        }
        pageShadow.layer.shadowPath = path.cgPath
    }

    /// The empty margin left either side of the focused row's pages, and with it the slack the
    /// scroll has beyond them.
    ///
    /// Normally symmetric, so a page at either end of the row still has the room to reach the
    /// centre. With Align to Screen Edges on and a real pair to align, it is ZERO, and it has to
    /// be. That padding is scrollable content: leaving it in place while only moving the resting
    /// offset let the page be dragged away from the edge it was supposed to rest against, baring
    /// the mat behind it. Dropping it makes the content exactly as wide as the two pages, so the
    /// travel ends precisely where the pages do.
    ///
    /// A lone page (the cover, an unpaired last page) keeps its padding and stays centred: it has
    /// no facing page, so there is no outer edge for it to belong to.
    private func focusSidePad(pageWidth: CGFloat, in bounds: CGSize, pageCount: Int) -> CGFloat {
        if settings?.alignToEdges == true, pageCount > 1 { return 0 }
        return max(0, (bounds.width - pageWidth) / 2)
    }

    /// How far LEFT the row has to be shifted to bring focus column `col` to rest. `placeFocus`
    /// is the only caller: this is where the focused column lives, in the frames, which is what
    /// leaves the scroll view with nothing to travel horizontally.
    ///
    /// Centres the column by default. With Align to Screen Edges on, a two-page slot instead rests
    /// the column's OUTER edge against the screen's matching edge: the left page flush left, the
    /// right page flush right, which spends the fit-width zoom's spare width on the facing page
    /// rather than on a margin. Paired with `focusSidePad` returning zero there.
    ///
    /// The clamp at the end is measured against the row's OWN width, not the slot's, so a page can
    /// never be shifted so far that the mat shows past the outer trim.
    ///
    /// At zoom 1 both branches evaluate to the same number (`sidePad` is 0 and `pageW` is the full
    /// width), so the setting is inert at 100% by arithmetic rather than by a special case.
    private func focusColumnOffsetX(_ col: Int, in bounds: CGSize? = nil) -> CGFloat {
        let size = bounds ?? scrollView.bounds.size
        let pageW = size.width * fitWidthZoom
        let sidePad = focusSidePad(pageWidth: pageW, in: size, pageCount: pageIndices.count)
        let count = max(pageIndices.count, 1)
        let gap = pageGap
        let contentW = pageW * CGFloat(count) + gap * CGFloat(count - 1) + 2 * sidePad
        // Where the column's own left edge sits in the content, the one place the gutter enters
        // this calculation, and it has to match the stride `placeFocus` lays the frames out on.
        let colX = sidePad + CGFloat(col) * (pageW + gap)
        let target: CGFloat
        if settings?.alignToEdges == true, pageIndices.count > 1 {
            // Column 0 is the left page (its left edge to the screen's left); anything beyond it
            // is a right page (its right edge to the screen's right).
            target = col == 0 ? colX : colX + pageW - size.width
        } else {
            target = colX + pageW / 2 - size.width / 2
        }
        return min(max(target, 0), max(0, contentW - size.width))
    }

    // MARK: Gestures

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard !images.isEmpty else { return }
        readerTookOver()
        fitIsStandard = false
        if isDouble {
            // Spread ⇄ zoom the tapped page (fit-width * zoom, centred), animated in place
            // (both pages stay laid out → smooth zoom, no black flash, pan to the other).
            // Either way the controller is told, since this is the gesture that picks the
            // carried fit-width look up and puts it back down (Keep Zoom Across Pages).
            switch fit {
            case .focus:
                fit = .spread
                delegate?.pageCell(self, didChangeFitWidthFocus: false)
            case .spreadHeight:
                // Pinched all the way out to the whole spread: a double tap comes back to the
                // reading fit rather than jumping straight into one page.
                fit = .spread
            default:
                let column = tappedPage(atX: gesture.location(in: self).x)
                fit = .focus(column: column)
                reportFocus(column: column)                  // and it makes that half current
                delegate?.pageCell(self, didChangeFitWidthFocus: true)
            }
        } else {
            fit = isFitWidth ? .fitHeight : .fitWidth
        }
        applyLayout(animated: true)
    }

    /// Tell the controller which global page this slot is now focused on, so `currentPage`
    /// follows the half actually being read. Bounds-guarded to the pages this slot holds.
    private func reportFocus(column: Int) {
        guard column >= 0, column < pageIndices.count else { return }
        delegate?.pageCell(self, didFocusPageAt: pageIndices[column])
    }

    private var isFitWidth: Bool {
        if case .fitWidth = fit { return true }
        return false
    }

    /// The focused half, for the code that has to act on the focus it is already in (tap-scroll,
    /// a sideways swipe across the gutter) rather than set a new one.
    private var focusColumn: Int? {
        if case .focus(let column) = fit { return column }
        return nil
    }

    private func tappedPage(atX x: CGFloat) -> Int {
        guard pageIndices.count > 1 else { return 0 }
        return x < bounds.width / 2 ? 0 : 1
    }

    /// The outer navigation zones (page turn / tap-scroll), where the single tap must
    /// fire instantly and the double-tap zoom is suppressed. Cell (`self`) coordinate
    /// space, the same basis as `tappedPage(atX:)`.
    private func isNavEdge(_ x: CGFloat) -> Bool { ReaderMetrics.isNavEdge(x, width: bounds.width) }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        let x = gesture.location(in: self).x
        // Tap-to-navigate (opt-in): step down / up the page a half at a time. In a
        // zoomed spread it also steps left→right across the two pages before turning.
        // At the very edge it falls through to the controller (prev / next / chrome).
        // When disabled, every tap falls through (→ the controller toggles the chrome).
        if settings?.tapToNavigate == true, isNavEdge(x) {
            // Left edge scrolls up, right edge down; at the page edge tapScroll returns
            // false and we fall through to the controller (prev / next).
            if tapScroll(forward: x > bounds.width / 2) { return }
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
        if case .spreadHeight = fit { return false }   // the whole spread is already on screen
        if let column = focusColumn, pageIndices.count > 1 {
            return scrollColumn(forward: forward) || crossGutter(forward: forward, from: column)
        }
        if case .fitHeight = fit, scrollRow(forward: forward) { return true }
        return scrollColumn(forward: forward)
    }

    /// Steps across a fit-height page that is WIDER than the slot (a panorama): forward to its
    /// right end, back to its left end, then false so the page turns. One step each way, because
    /// the overflow is a fraction of a screen, not several.
    private func scrollRow(forward: Bool) -> Bool {
        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        guard maxX > 1 else { return false }
        let x = scrollView.contentOffset.x
        let target: CGFloat = forward ? maxX : 0
        guard abs(x - target) > 1 else { return false }
        animateTapScroll(to: CGPoint(x: target, y: scrollView.contentOffset.y))
        return true
    }

    /// How many taps carry the reader from a page's top to its bottom.
    ///
    /// A tablet holds nearly the whole page already, so the leftover is a strip rather than a
    /// screenful and one tap should clear it; splitting that strip in two would ask for a tap to
    /// travel almost nothing. A phone at fit-width runs well past the screen, where a half-screen
    /// step is the readable unit and one tap would skip past text.
    private var tapScrollSteps: CGFloat {
        traitCollection.userInterfaceIdiom == .pad ? 1 : 2
    }

    /// Scrolls the current column up / down by exactly one `tapScrollSteps` share of its
    /// *scrollable* range, so the true top / bottom is always reached in exactly that many taps —
    /// even when tapping fast, because it advances from the last committed target rather than the
    /// (possibly mid-animation) live offset. One share short of a full traverse, never one more,
    /// because the top portion is already on screen at rest. Returns false at the edge, so the
    /// controller turns the page.
    private func scrollColumn(forward: Bool) -> Bool {
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        guard maxY > 1 else { return false }              // page fits → no vertical scroll
        let steps = tapScrollSteps
        let step = maxY / steps
        let base = tapTargetY ?? scrollView.contentOffset.y
        let index = (base / step).rounded()               // which stop we're on (0…steps)
        let target: CGFloat
        if forward {
            guard index < steps - 0.5 else { return false }   // at the bottom → turn the page
            target = index + 1 >= steps ? maxY : (index + 1) * step
        } else {
            guard index > 0.5 else { return false }           // at the top → turn the page
            target = (index - 1) * step
        }
        tapTargetY = target
        animateTapScroll(toY: target)
        return true
    }

    /// Animate a tap-scroll step with a Core Animation property animator, so — like the
    /// double-tap zoom — it runs on the render server at the full ProMotion rate instead of a
    /// main-thread per-frame loop. Standard iOS ease-in-out, on a quicker duration than a page
    /// turn. Restarting from the live offset (`.beginFromCurrentState` semantics of stopping
    /// the previous animator) means two fast taps chain straight through to the page end.
    private func animateTapScroll(toY y: CGFloat) {
        animateTapScroll(to: CGPoint(x: scrollView.contentOffset.x, y: y))
    }

    private func animateTapScroll(to offset: CGPoint) {
        stopTapScroll()
        readerTookOver()
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

    /// Move the reader to the facing half of this spread, entering it the way a page turn enters
    /// a slot: forward at its top, backward at its bottom. Returns false when there is no half
    /// left in that direction, which is the caller's cue to turn the slot instead.
    ///
    /// The one implementation of the crossing, shared by the edge tap and the sideways swipe, so
    /// the two gestures can't drift into meaning different things.
    ///
    /// It is a RE-LAYOUT, because that is where the focused column lives now (see `placeFocus`):
    /// the row slides over by one page and the new page's resting height comes with it, both
    /// inside the same animation. `openAtBottom` carries "enter this page at its bottom" into
    /// that layout, and is handed back afterwards since the slot is being read now, not arriving.
    @discardableResult
    private func crossGutter(forward: Bool, from column: Int) -> Bool {
        let crossTo = forward ? 1 : 0
        guard column != crossTo, pageIndices.count > 1 else { return false }
        stopTapScroll()
        fit = .focus(column: crossTo)
        openAtBottom = !forward
        applyLayout(animated: true)
        readerTookOver()
        tapTargetY = forward ? 0 : max(0, scrollView.contentSize.height - scrollView.bounds.height)
        reportFocus(column: crossTo)
        return true
    }

    /// The slot is at the top of its page (or doesn't scroll at all), so a pull down is meant for
    /// the reader, not the page. The scroll view never bounces and its inset stays zero.
    var isScrolledToTop: Bool { scrollView.contentOffset.y <= 0.5 }

    /// True while a sideways swipe on this slot means something inside the slot rather than "the
    /// next slot": it holds two pages and is zoomed into one of them, or it is a single page at
    /// fit-height wider than the screen (see `pansAcrossPage`).
    ///
    /// The reader reads this to hand the collection view's paging over and take it back (see
    /// `ReaderCollectionController.syncSidewaysNavigation`). Without it a swipe from the LEFT half
    /// turns the whole spread and the right half is never seen, which, with Keep Zoom Across
    /// Pages on, is every right page in the comic.
    var ownsSidewaysNavigation: Bool {
        if pageIndices.count > 1, case .focus = fit { return true }
        return pansAcrossPage
    }

    /// A fit-height page wider than the slot (a panorama): the scroll view
    /// pans across it natively, and the page turns only on a swipe that STARTS at the edge it
    /// points past. Without owning the direction, the collection view's paging and the page's own
    /// pan both claimed the same swipe, so a drag across the page could turn it halfway.
    private var pansAcrossPage: Bool {
        guard case .fitHeight = fit else { return false }
        return scrollView.contentSize.width > scrollView.bounds.width + 1
    }

    /// Whether the page is already at the edge a sideways swipe in this direction points past, so
    /// the swipe is a page turn rather than a pan. Dragging LEFT reads forward.
    private func pageAtEdge(forward: Bool) -> Bool {
        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        return forward ? scrollView.contentOffset.x >= maxX - 1 : scrollView.contentOffset.x <= 1
    }

    /// A sideways swipe while this slot owns the direction: cross to the facing page, or, if the
    /// reader is already on the last half this way, ask for the next / previous slot.
    ///
    /// Deliberately not interactive. The page does not follow the finger and then settle; the
    /// gesture is read at its end and answered with the same animation the edge taps use, so
    /// tapping and swiping produce the same movement rather than two dialects of it.
    ///
    /// Answered the moment the drag has gone far enough rather than when the finger lifts, so the
    /// turn doesn't wait out the rest of the gesture; a short flick is still read at its end, from
    /// its velocity.
    @objc private func handleSidewaysPan(_ gesture: UIPanGestureRecognizer) {
        let dx = gesture.translation(in: self).x
        let far = abs(dx) > bounds.width * Self.swipeDistanceFraction
        switch gesture.state {
        case .began:
            sidewaysPanHandled = false
        case .changed where far && !sidewaysPanHandled:
            sidewaysPanHandled = true
            answerSwipe(forward: dx < 0)            // dragging LEFT reads forward
        case .ended where !sidewaysPanHandled:
            let vx = gesture.velocity(in: self).x
            guard abs(vx) > Self.swipeVelocity else { return }   // a nudge is not a page turn
            answerSwipe(forward: vx < 0)
        default:
            break
        }
    }

    private func answerSwipe(forward: Bool) {
        if let column = focusColumn, crossGutter(forward: forward, from: column) { return }
        delegate?.pageCell(self, didRequestTurn: forward)
    }

    // MARK: Pinch

    /// One pinch = one rung on the fit ladder.
    ///
    /// There is no continuous magnification behind this. The whole reader is laid out by FRAMES
    /// (see `place`), which is what lets a size change and a fit change animate instead of snap, and
    /// a live pinch scale would have to be a transform laid over that — a second, competing idea
    /// of where the page is. Stepping between named fits keeps one source of truth and gives the
    /// pinch the same two destinations the double tap has.
    ///
    /// The step fires on the way through the threshold and then the rest of the pinch is ignored,
    /// so the ladder is climbed one deliberate gesture at a time rather than run up in one long
    /// spread of the fingers.
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard !images.isEmpty else { return }
        switch gesture.state {
        case .began:
            pinchDidStep = false
            stopTapScroll()
        case .changed:
            guard !pinchDidStep else { return }
            if gesture.scale >= Self.pinchOutThreshold {
                pinchDidStep = true
                stepFit(closer: true, atX: gesture.location(in: self).x)
            } else if gesture.scale <= Self.pinchInThreshold {
                pinchDidStep = true
                stepFit(closer: false, atX: gesture.location(in: self).x)
            }
        default:
            break
        }
    }

    /// Move one rung: `closer` = pinched out (more page, less of it on screen), else pinched in.
    ///
    /// The ladders, tightest first:
    ///   single page  whole page  →  the other fit (see `fitHeightIsCloser`)
    ///   spread       whole spread  →  fit-width spread  →  one page at the chosen zoom
    ///
    /// Which of the two single-page fits is the CLOSER one depends on the page, not on the name:
    /// normally fit-width blows the page up, but for a panorama fit-height is the one that
    /// overflows. `fitHeightIsCloser` asks the geometry instead of assuming, so spreading the
    /// fingers always means more page.
    ///
    /// Going into a spread's focused page is the same event as the double-tap zoom, so it reports
    /// the same things: the half being read becomes current, and Keep Zoom Across Pages picks the
    /// look up. At either end of a ladder the pinch does nothing at all, which is the honest
    /// answer — there is no rung to move to.
    private func stepFit(closer: Bool, atX x: CGFloat) {
        switch fit {
        case .fitHeight where closer != fitHeightIsCloser:
            fit = .fitWidth
        case .fitWidth where closer == fitHeightIsCloser:
            fit = .fitHeight
        case .spreadHeight where closer:
            fit = .spread
        case .spread where !closer:
            fit = .spreadHeight
        case .spread where closer:
            let column = tappedPage(atX: x)
            fit = .focus(column: column)
            reportFocus(column: column)
            delegate?.pageCell(self, didChangeFitWidthFocus: true)
        case .focus where !closer:
            fit = .spread
            delegate?.pageCell(self, didChangeFitWidthFocus: false)
        default:
            return                      // already at the end of this ladder
        }
        fitIsStandard = false
        readerTookOver()
        applyLayout(animated: true)
    }

    // MARK: Live Text

    private func setupLiveText(_ pos: Int, _ image: UIImage) {
        guard settings?.liveText == true, ImageAnalyzer.isSupported, pos < liveText.count else { return }
        let interaction = liveText[pos]
        if pageViews[pos].interactions.contains(where: { $0 === interaction }) == false {
            pageViews[pos].addInteraction(interaction)
        }
        interaction.setSupplementaryInterfaceHidden(true, animated: false)
        updateLiveTextEnabled()
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

    /// Live Text press-and-hold selection is only offered where a page is shown at a
    /// comfortable reading size (fit-width, a spread's zoomed page), so it never competes with
    /// the whole-page and spread overviews, where the text is too small to select anyway.
    private func updateLiveTextEnabled() {
        let enabled: Bool
        switch fit {
        case .fitWidth, .focus:                   enabled = true
        case .fitHeight, .spread, .spreadHeight:  enabled = false
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
        readerTookOver()
        tapTargetY = nil
    }
}

extension ReaderPageCell: UIGestureRecognizerDelegate {

    /// Capture the reliable touch-down x for `shouldRequireFailureOf` (whose own
    /// `location(in:)` isn't dependable when the failure graph is built). Also keep the
    /// double-tap recognizer out of the nav edges while tap-to-navigate is on, so an edge
    /// double-tap can't zoom — there it simply becomes two single taps (two nav steps).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        let x = touch.location(in: self).x
        pendingTapDownX = x
        if gestureRecognizer === doubleTap, settings?.tapToNavigate == true, isNavEdge(x) {
            return false
        }
        return true
    }

    /// Make the single tap wait for the double only where the double should win: the
    /// centre (everything but the nav edges), or whenever tap-to-navigate is off. In the nav edges (tap-to-navigate
    /// on) there is no requirement, so the single tap fires on touch-up — instantly.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === singleTap, other === doubleTap else { return false }
        guard settings?.tapToNavigate == true else { return true }   // off → today's behaviour
        guard let x = pendingTapDownX else { return true }           // uncertain → safe fallback
        return !isNavEdge(x)
    }

    /// The sideways pan begins only where it has something to say: a slot zoomed into one half of
    /// a spread, and a drag that is going sideways rather than down the page. Everywhere else it
    /// fails at once, which is what leaves the swipe to the collection view. `override` because
    /// UIView already declares this @objc hook; ours also serves the recognizers' delegate.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === sidewaysPan else { return true }
        guard ownsSidewaysNavigation, let pan = sidewaysPan else { return false }
        let v = pan.velocity(in: self)
        guard abs(v.x) > abs(v.y) else { return false }
        // Across a wide fit-height page the swipe is the scroll view's pan, until the page is at
        // the edge it points past: only a swipe that begins there turns the page.
        if pansAcrossPage { return pageAtEdge(forward: v.x < 0) }
        return true
    }

    /// The pinch reads alongside the scroll view's own pan, so two fingers laid on a page that is
    /// already being dragged still register as a pinch. That pair only; nothing else composes.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === zoomPinch && other === scrollView.panGestureRecognizer { return true }
        // At the edge of a wide fit-height page the scroll view's pan also begins (the page is
        // scrollable, just not that way), and it must not swallow the turning swipe.
        return gestureRecognizer === sidewaysPan && other === scrollView.panGestureRecognizer
            && pansAcrossPage
    }
}
