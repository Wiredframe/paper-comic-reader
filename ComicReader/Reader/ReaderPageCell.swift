//
//  ReaderPageCell.swift
//  Comic Reader
//
//  One "slot" of the reader: a single page (portrait / double-page off) or a
//  two-page spread (landscape double-page).
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
//  doesn't. Keeping the inset at zero is what makes a rotation smooth — only frames
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
}

final class ReaderPageCell: UICollectionViewCell {

    static let reuseID = "ReaderPageCell"
    static let displayMaxPixel: CGFloat = 2200
    /// Width fraction of each outer navigation zone (page turn / tap-scroll), where a
    /// single tap fires instantly and the double-tap zoom is suppressed. The centre keeps
    /// the double-tap zoom. Single source for the cell (`isNavEdge`) and the controller's
    /// `didSingleTapAtX` split, so change the feel value here only.
    static let navEdgeFraction: CGFloat = 0.10

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
        /// Both pages at fit-width each, panned to `column` (0 = left, 1 = right). `zoomed` says
        /// whether the configurable fit-width zoom applies: it does for a deliberate double-tap
        /// and for the look carried across page changes, but never for the rotation morph, whose
        /// focus is a full-width endpoint.
        case focus(column: Int, zoomed: Bool)
    }

    /// The page shadow: soft, sitting a little below the page, as if lit from above. Sized
    /// generously rather than tightly — a hard, tight shadow reads as a drop-shadowed graphic,
    /// a wide diffuse one reads as paper resting on the mat.
    private enum Shadow {
        static let opacity: Float = 0.5
        static let radius: CGFloat = 16
        static let offset = CGSize(width: 0, height: 6)
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
    /// layout or the zero `contentInset` the rotation relies on. See the `// MARK: Pinch` section.
    private var zoomPinch: UIPinchGestureRecognizer?
    /// One step per pinch: set the moment a pinch crosses a threshold, cleared when it begins.
    private var pinchDidStep = false
    /// Sideways navigation on a zoomed spread half, where a swipe means "the other half" rather
    /// than "the next spread" — see `ownsSidewaysNavigation`.
    private var sidewaysPan: UIPanGestureRecognizer?

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
        pageShadow.layer.shadowColor = UIColor.black.cgColor
        pageShadow.layer.shadowOpacity = Shadow.opacity
        pageShadow.layer.shadowRadius = Shadow.radius
        pageShadow.layer.shadowOffset = Shadow.offset
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
    /// `.page` keeps `zoomed` on because it continues a deliberate double-tap zoom, and without it
    /// the page would snap back to full width at every page change. A slot holding a single page
    /// (the cover, an unpaired last page) takes it too: `.focus` is fit-width there just like
    /// `.spread`, but unlike `.spread` it honours the chosen zoom level.
    private func apply(_ opening: Opening) {
        switch opening {
        case .page(let column, let atEnd) where isDouble && !pageIndices.isEmpty:
            fit = .focus(column: min(max(column, 0), pageIndices.count - 1), zoomed: true)
            openAtBottom = atEnd
        default:
            fit = isDouble ? .spread : .fitWidth
            openAtBottom = false
        }
        lastLaidOutBounds = .zero
    }

    /// The reader has taken the page over (a tap-scroll, a drag, a double tap), so where it was
    /// ENTERED no longer describes where it rests. Only the layouts that still belong to the
    /// arrival, including the re-fits while the images arrive, put the page at its bottom.
    private func readerTookOver() { openAtBottom = false }

    /// Drive one endpoint of the portrait⇄landscape rotation morph on a spread cell.
    /// `.focus` is the PORTRAIT look — the reader's page fills the width with its partner
    /// waiting exactly one screen-width off the adjoining edge — and `.spread` is the
    /// settled LANDSCAPE spread. The controller flips between the two *inside* the rotation
    /// animation, so the page slides into (or grows out of) its half while the partner
    /// glides in / out, instead of the single page and the spread cross-dissolving.
    /// `focusPos` is the page's side in the pair (0 = left, 1 = right); a lone page (cover
    /// or an unpaired last page) has no partner, so both endpoints simply fit the width.
    func setRotationSpread(_ spread: Bool, focusPos: Int) {
        // The morph's focus is a full-width endpoint, never zoomed, and always from the top
        // whatever the slot arrived at.
        fit = spread ? .spread : .focus(column: focusPos, zoomed: false)
        openAtBottom = false
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
        case .fitWidth:  place([fitWidth(0, in: bounds, zoom: zoom)], in: bounds)
        case .fitHeight: place([fitHeight(0, in: bounds)], in: bounds)
        case .spread:    place(spreadSizes(in: bounds), in: bounds)
        case .spreadHeight: place(spreadHeightSizes(in: bounds), in: bounds)
        case .focus(let column, let zoomed):
            placeFocus(focusSizes(in: bounds, zoom: zoomed ? zoom : 1.0),
                       focused: pageIndices.count > 1 ? column : 0, in: bounds)
        }
        updateLiveTextEnabled(landscape: landscape)
        tapTargetY = nil          // the scroll position was just reset by the layout
    }

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
    /// whichever axis it's smaller. The scroll content is at least the bounds — so it
    /// stays put when it fits and pans when it doesn't — and `contentInset` stays ZERO.
    /// That's the point: on a rotation only the frames change, which animate inside the
    /// turn, so there's no inset/offset snap (smooth regardless of the chrome).
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
    /// Edges on), the other poking in from the side. At zoom 1 this exactly reproduces the
    /// full-width, edge-aligned focus (and the rotation morph's portrait endpoint) whichever way
    /// the setting is.
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
    /// since the scroll view clips there: above and below a portrait page, around a fit-height or
    /// a sub-full-width fit-width page, and now in the gutter. Where the page runs to the screen
    /// edge there's no mat to catch a shadow anyway.
    ///
    /// `shadowPath` is set explicitly for two reasons: Core Animation then never derives the
    /// shadow from the layer's alpha channel (an offscreen pass every frame, which the rotation
    /// can't afford), and — being an animatable layer property, set here alongside the frames —
    /// it tweens inside the rotation morph and the double-tap fit instead of snapping.
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
        let landscape = size.width > size.height
        let zoom = (landscape && focusIsZoomed) ? CGFloat(settings?.doubleTapZoom ?? 1.0) : 1.0
        let pageW = size.width * zoom
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
                fit = .focus(column: column, zoomed: true)   // deliberate zoom → honour the setting
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

    /// The focused half and whether it is zoomed, for the code that has to act on the focus it is
    /// already in (tap-scroll, a hand pan across the gutter) rather than set a new one.
    private var focusState: (column: Int, zoomed: Bool)? {
        if case .focus(let column, let zoomed) = fit { return (column, zoomed) }
        return nil
    }

    private var focusIsZoomed: Bool { focusState?.zoomed ?? false }

    private func tappedPage(atX x: CGFloat) -> Int {
        guard pageIndices.count > 1 else { return 0 }
        return x < bounds.width / 2 ? 0 : 1
    }

    /// The outer navigation zones (page turn / tap-scroll), where the single tap must
    /// fire instantly and the double-tap zoom is suppressed. Cell (`self`) coordinate
    /// space, the same basis as `tappedPage(atX:)`. Each zone is `navEdgeFraction` wide.
    private func isNavEdge(_ x: CGFloat) -> Bool {
        x < bounds.width * Self.navEdgeFraction || x > bounds.width * (1 - Self.navEdgeFraction)
    }

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
        if let focus = focusState, pageIndices.count > 1 {
            return focusTapScroll(forward: forward, focus: focus)
        }
        return scrollColumn(forward: forward)
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
        stopTapScroll()
        readerTookOver()
        let animator = UIViewPropertyAnimator(duration: settings?.tapScrollDuration ?? 0.25,
                                              curve: .easeInOut) { [weak self] in
            self?.scrollView.contentOffset.y = y
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
    /// it return false, so the controller turns to the next / previous spread. Crossing
    /// the gutter enters the other page the way a page turn enters a slot: forward at its
    /// top, backward at its bottom.
    private func focusTapScroll(forward: Bool, focus: (column: Int, zoomed: Bool)) -> Bool {
        if scrollColumn(forward: forward) { return true }
        return crossGutter(forward: forward, focus: focus)
    }

    /// Move the reader to the facing half of this spread. Returns false when there is no half
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
    private func crossGutter(forward: Bool, focus: (column: Int, zoomed: Bool)) -> Bool {
        let crossTo = forward ? 1 : 0
        guard focus.column != crossTo, pageIndices.count > 1 else { return false }
        stopTapScroll()
        fit = .focus(column: crossTo, zoomed: focus.zoomed)
        openAtBottom = !forward
        applyLayout(animated: true)
        readerTookOver()
        tapTargetY = forward ? 0 : max(0, scrollView.contentSize.height - scrollView.bounds.height)
        reportFocus(column: crossTo)
        updateLiveTextEnabled(landscape: bounds.width > bounds.height)
        return true
    }

    /// True while a sideways swipe on this slot means "the facing page" rather than "the next
    /// spread": it holds two pages and is zoomed into one of them.
    ///
    /// The reader reads this to hand the collection view's paging over and take it back (see
    /// `ReaderCollectionController.syncSidewaysNavigation`). Without it a swipe from the LEFT half
    /// turns the whole spread and the right half is never seen — which, with Keep Zoom Across
    /// Pages on, is every right page in the comic.
    var ownsSidewaysNavigation: Bool {
        guard pageIndices.count > 1, case .focus = fit else { return false }
        return true
    }

    /// A sideways swipe while this slot owns the direction: cross to the facing page, or, if the
    /// reader is already on the last half this way, ask for the next / previous slot.
    ///
    /// Deliberately not interactive. The page does not follow the finger and then settle; the
    /// gesture is read at its end and answered with the same animation the edge taps use, so
    /// tapping and swiping produce the same movement rather than two dialects of it.
    @objc private func handleSidewaysPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended, let focus = focusState else { return }
        let dx = gesture.translation(in: self).x
        let vx = gesture.velocity(in: self).x
        let far = abs(dx) > bounds.width * Self.swipeDistanceFraction
        let fast = abs(vx) > Self.swipeVelocity
        guard far || fast else { return }               // a nudge is not a page turn
        // Dragging LEFT (negative) reads forward, the way the collection view pages.
        let forward = (far ? dx : vx) < 0
        if !crossGutter(forward: forward, focus: focus) {
            delegate?.pageCell(self, didRequestTurn: forward)
        }
    }

    // MARK: Pinch

    /// One pinch = one rung on the fit ladder.
    ///
    /// There is no continuous magnification behind this. The whole reader is laid out by FRAMES
    /// (see `place`), which is what lets a rotation and a fit change animate instead of snap, and
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
    ///   single page  fit-height  →  fit-width
    ///   spread       whole spread  →  fit-width spread  →  one page at the chosen zoom
    ///
    /// Going into a spread's focused page is the same event as the double-tap zoom, so it reports
    /// the same things: the half being read becomes current, and Keep Zoom Across Pages picks the
    /// look up. At either end of a ladder the pinch does nothing at all, which is the honest
    /// answer — there is no rung to move to.
    private func stepFit(closer: Bool, atX x: CGFloat) {
        switch fit {
        case .fitHeight where closer:
            fit = .fitWidth
        case .fitWidth where !closer:
            fit = .fitHeight
        case .spreadHeight where closer:
            fit = .spread
        case .spread where !closer:
            fit = .spreadHeight
        case .spread where closer:
            let column = tappedPage(atX: x)
            fit = .focus(column: column, zoomed: true)
            reportFocus(column: column)
            delegate?.pageCell(self, didChangeFitWidthFocus: true)
        case .focus where !closer:
            fit = .spread
            delegate?.pageCell(self, didChangeFitWidthFocus: false)
        default:
            return                      // already at the end of this ladder
        }
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
        case .spreadHeight: enabled = false   // both pages at once, far too small to select in
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
        return abs(v.x) > abs(v.y)
    }

    /// The pinch reads alongside the scroll view's own pan, so two fingers laid on a page that is
    /// already being dragged still register as a pinch. That pair only; nothing else composes.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer === zoomPinch && other === scrollView.panGestureRecognizer
    }
}
