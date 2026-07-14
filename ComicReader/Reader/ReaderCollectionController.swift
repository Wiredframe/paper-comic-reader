//
//  ReaderCollectionController.swift
//  Comic Reader
//
//  The reader's paging core: a horizontal, paging UICollectionView of page slots.
//  In portrait (or with double-page off) a slot is one page; in landscape with
//  double-page on a slot is a spread. The page↔slot pairing is FIXED — the cover
//  (page 1) is always alone, then pages pair up (2·3, 4·5, …) — so a page that is
//  the right half of a spread can never become the left half of another. That makes
//  flipping between portrait and landscape any number of times fully consistent.
//

import UIKit

/// The fixed mapping between collection-view slots and page indices.
///
/// Edge cases (double mode), all verified: a 1-page comic → 1 slot `[0]`; a 2-page
/// comic → `[0]`, `[1]` (the cover, then page 2 alone); an even page count leaves a
/// lone final page in its own slot (`pages(inSlot:)` returns just `[left]`). Every
/// slot therefore holds 1 or 2 pages and is always in range.
struct ReaderPaging {
    let pageCount: Int
    let double: Bool          // true = spreads (cover alone, then pairs)

    var slotCount: Int {
        guard pageCount > 0 else { return 0 }
        return double ? 1 + pageCount / 2 : pageCount
    }

    /// The 1 or 2 page indices shown in a slot (right half may be absent at the end).
    func pages(inSlot slot: Int) -> [Int] {
        guard double else { return [slot] }
        if slot == 0 { return [0] }                      // cover, always alone
        let left = 2 * slot - 1
        let right = 2 * slot
        return right < pageCount ? [left, right] : [left]
    }

    /// The slot that contains a given page (its left OR right half).
    func slot(forPage page: Int) -> Int {
        guard double else { return page }
        return page == 0 ? 0 : (page + 1) / 2
    }
}

/// A paging flow layout that keeps the *current page* aligned across bounds changes
/// (rotation, status-bar show/hide). A plain flow layout keeps its raw pixel offset
/// when the item width changes, so a rotation lands on a different page (and then
/// snaps back) — this override hands back the page-aligned offset for the new bounds,
/// so the collection view can never show the wrong page mid-rotation.
final class PagingFlowLayout: UICollectionViewFlowLayout {
    /// Supplied by the controller: the slot to keep on screen.
    var currentSlot: () -> Int = { 0 }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        guard let cv = collectionView, cv.bounds.width > 0 else { return proposedContentOffset }
        return CGPoint(x: CGFloat(currentSlot()) * cv.bounds.width, y: proposedContentOffset.y)
    }
}

/// Animates a scroll view's `contentOffset` along a snappy easeOutBack curve — a fast
/// ease-out with a small terminal overshoot that reads as a light bounce. The curve is
/// closed-form, evaluated at each frame's presentation time, so the motion (and the
/// bounce) is identical at 60 or 120 Hz, and the display link is invalidated the instant
/// it ends so it never holds ProMotion at a high refresh rate afterwards.
///
/// Shared by the two reader movements: the tap PAGE TURN (on the collection view) and a
/// tap-SCROLL step (on a page's own scroll view). Driving the *model* `contentOffset`
/// each frame — rather than a `UIView.animate` that jumps the model offset to the
/// destination at once — is also what keeps BOTH pages laid out through a turn (the
/// collection view would otherwise recycle the outgoing page and slide the new one in
/// over black). The overshoot lands on neighbouring content mid-way and on the black
/// background at the ends, so it always looks like natural momentum.
final class EasedScrollAnimator {
    private var link: CADisplayLink?
    private weak var scrollView: UIScrollView?
    private var from: CGPoint = .zero
    private var to: CGPoint = .zero
    private var startTime: CFTimeInterval = -1     // set on the first frame
    private var duration: CFTimeInterval = 0
    private var overshoot: CGFloat = 0             // easeOutBack strength (0 = plain ease-out)
    private var completion: (() -> Void)?

    var isRunning: Bool { link != nil }

    /// Starts (or restarts, from the live offset) a turn to `target` over `duration`,
    /// with `overshoot` controlling the size of the terminal bounce.
    func animate(_ scrollView: UIScrollView, to target: CGPoint,
                 duration: CFTimeInterval, overshoot: Double, completion: @escaping () -> Void) {
        cancel()
        self.scrollView = scrollView
        self.from = scrollView.contentOffset
        self.to = target
        self.duration = duration
        self.overshoot = CGFloat(overshoot)
        self.startTime = -1
        self.completion = completion
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        // Run at the display's rate (up to 120 Hz on ProMotion) so the turn is as smooth
        // as a drag. The floor is kept high so these short movements bias to 120 rather
        // than being power-throttled toward 60 (60 Hz displays clamp this to 60 anyway).
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 90, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Stops the turn where it is, dropping the completion (used when a drag takes over).
    func cancel() {
        link?.invalidate()
        link = nil
        completion = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let scrollView else { cancel(); return }
        if startTime < 0 { startTime = link.timestamp }
        // Evaluate at the frame's own presentation time (targetTimestamp), not "now", so
        // the motion stays jitter-free on a variable-rate display.
        let t = duration > 0 ? min(1, (link.targetTimestamp - startTime) / duration) : 1
        let e = Self.easeOutBack(CGFloat(t), overshoot: overshoot)
        scrollView.contentOffset = CGPoint(x: from.x + (to.x - from.x) * e,
                                           y: from.y + (to.y - from.y) * e)
        if t >= 1 {
            scrollView.contentOffset = to
            let done = completion
            cancel()
            done?()
        }
    }

    /// Ease-out with a small overshoot past 1 near the end, settling back to exactly 1 at
    /// t = 1 — a snappy start and one light bounce. `c1` scales the overshoot (~0.8 ≈ 2%).
    private static func easeOutBack(_ t: CGFloat, overshoot c1: CGFloat) -> CGFloat {
        let c3 = c1 + 1
        let p = t - 1
        return 1 + c3 * p * p * p + c1 * p * p
    }
}

final class ReaderCollectionController: UIViewController,
                                        UICollectionViewDataSource,
                                        UICollectionViewDataSourcePrefetching,
                                        UICollectionViewDelegateFlowLayout,
                                        ReaderPageCellDelegate {

    private let store: PageImageStore
    private let settings: ReaderSettings
    let pageCount: Int
    /// The page the reader considers current. Source of truth across rotations.
    private(set) var currentPage: Int

    private var isDouble = false
    private var isRotating = false
    private var isProgrammaticScroll = false
    private var pendingInitialScroll = true

    var onPageChanged: ((Int) -> Void)?
    var onToggleChrome: (() -> Void)?

    private let layout = PagingFlowLayout()
    private var collectionView: UICollectionView!
    private let pageTurn = EasedScrollAnimator()

    private var paging: ReaderPaging { ReaderPaging(pageCount: pageCount, double: isDouble) }

    /// Letterbox behind the pages. The page cells are clear, so this is what shows
    /// around a page that doesn't fill the screen. Adaptive to the app's theme.
    private var backgroundUIColor: UIColor

    init(store: PageImageStore, settings: ReaderSettings, startIndex: Int, backgroundColor: UIColor) {
        self.store = store
        self.settings = settings
        self.pageCount = max(store.pageCount, 0)
        self.currentPage = min(max(startIndex, 0), max(pageCount - 1, 0))
        self.backgroundUIColor = backgroundColor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Update the letterbox colour live (e.g. the theme changed while reading).
    func setBackground(_ color: UIColor) {
        guard color != backgroundUIColor else { return }
        backgroundUIColor = color
        viewIfLoaded?.backgroundColor = color
        collectionView?.backgroundColor = color
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Free rotation while reading; the manual landscape/portrait toggle in the reader
        // nudges from here. (The rest of the app stays portrait — see OrientationGate.)
        OrientationGate.free()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Roll back to portrait as part of the dismiss transition. The page-grid is a
        // page sheet, which doesn't fire the presenter's viewWillDisappear, so this only
        // runs when the reader itself is going away.
        OrientationGate.lockPortrait()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = backgroundUIColor

        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        layout.currentSlot = { [weak self] in
            guard let self else { return 0 }
            return self.paging.slot(forPage: self.currentPage)
        }

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.delegate = self
        collectionView.isPagingEnabled = true
        collectionView.bounces = false
        collectionView.alwaysBounceHorizontal = false
        collectionView.alwaysBounceVertical = false
        collectionView.backgroundColor = backgroundUIColor
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        // Deliberately NO autoresizingMask: the controller owns the collection view's
        // frame (see viewDidLayoutSubviews / viewWillTransition). With autoresizing on,
        // SwiftUI resizes it in its own layout pass, which only lines up with the
        // rotation animation while the chrome (and status bar) is also animating — that
        // stray, un-animated resize was the "rebuild / snap" rotation jank.
        collectionView.register(ReaderPageCell.self, forCellWithReuseIdentifier: ReaderPageCell.reuseID)
        view.addSubview(collectionView)

        prefetchNeighbours(of: currentPage)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Own the frame for every NON-rotation layout (initial size, safe-area / split
        // changes). During a rotation the coordinator block below drives it instead, so
        // we leave it alone and let the turn animate the resize in one piece.
        if !isRotating { collectionView.frame = view.bounds }
        guard collectionView.bounds.width > 0, pageCount > 0 else { return }
        if pendingInitialScroll {
            isDouble = wantsDouble(for: collectionView.bounds.size)
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            if let offset = offset(forSlot: paging.slot(forPage: currentPage)) {
                collectionView.contentOffset = offset
            }
            pendingInitialScroll = false
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        isRotating = true
        let newDouble = wantsDouble(for: size)
        let modeFlip = newDouble != isDouble

        // The reader's page and where it sits in its spread pair (0 = left half, 1 = right
        // half). The morph PIVOTS on this page: it's the one that fills the width on the
        // portrait side and settles into — or grows out of — its half, so it always lands
        // on the correct side of the spread. A lone page (the cover, or a last unpaired
        // page) has no partner, so `.focus` and `.spread` both just fit the width — the
        // morph then degrades to the plain single-page re-fit, exactly as before.
        let doublePaging = ReaderPaging(pageCount: pageCount, double: true)
        let doubleSlot = doublePaging.slot(forPage: currentPage)
        let focusPos = doublePaging.pages(inSlot: doubleSlot).firstIndex(of: currentPage) ?? 0

        if modeFlip && newDouble {
            // PORTRAIT single → LANDSCAPE spread. Rebuild the slots as spreads NOW, at the
            // current (~portrait) width, and lay the reader's slot out as `.focus`: the
            // page fills the width with its partner waiting one screen-width off the
            // adjoining edge — pixel-identical to the single page it replaces, so this swap
            // is invisible. The `.spread` settle inside the turn (below) then slides the
            // partner in and eases the page into its half. The page MORPHS into the spread;
            // it doesn't cross-dissolve into it.
            isDouble = true
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            collectionView.contentOffset = CGPoint(x: CGFloat(doubleSlot) * collectionView.bounds.width, y: 0)
            collectionView.layoutIfNeeded()          // realise the slot's cell at that offset
            morphReaderCell(atSlot: doubleSlot, toSpread: false, focusPos: focusPos)
        }

        // Drive the resize AND the page re-fit ourselves, inside the coordinator's
        // animation, so the whole turn is a single animation — smooth whether the chrome
        // (and status bar) is shown or hidden. layoutIfNeeded forces the cells to re-fit
        // to the new width right here, within the turn, instead of on a later, possibly
        // un-synced layout pass; then we re-align the current page to the new width.
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.collectionView.frame = CGRect(origin: .zero, size: size)
            self.layout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
            let slot: Int
            if modeFlip && newDouble {
                // Settle focus → spread: the partner glides in, the page eases into its half.
                self.morphReaderCell(atSlot: doubleSlot, toSpread: true, focusPos: focusPos)
                slot = doubleSlot
            } else if modeFlip {
                // LANDSCAPE spread → PORTRAIT single: reverse it on the still-live spread
                // cell (the page grows back to full width, the partner glides out); the
                // completion reload then swaps in the single-page slots behind the now-
                // identical, full-width frame. The structure stays double until then, so
                // the partner is available to animate out.
                self.morphReaderCell(atSlot: doubleSlot, toSpread: false, focusPos: focusPos)
                slot = doubleSlot
            } else {
                slot = self.paging.slot(forPage: self.currentPage)
            }
            self.collectionView.contentOffset = CGPoint(x: CGFloat(slot) * size.width, y: 0)
        }, completion: { [weak self] _ in
            guard let self else { return }
            if modeFlip && !newDouble {
                // Settle the real single-page structure behind the morphed (full-width)
                // page — invisible, because its partner is already off screen.
                self.isDouble = false
                let slot = self.paging.slot(forPage: self.currentPage)
                self.collectionView.reloadData()
                self.collectionView.layoutIfNeeded()
                self.collectionView.contentOffset = CGPoint(x: CGFloat(slot) * self.collectionView.bounds.width, y: 0)
            }
            self.isRotating = false
            self.collectionView.frame = self.view.bounds   // reconcile any drift
        })
    }

    /// Set a rotation-morph endpoint (`.focus` ⇄ `.spread`) on the cell that owns `slot`,
    /// if it's on screen. Called inside the coordinator animation so the frame changes
    /// tween; see `viewWillTransition` and `ReaderPageCell.setRotationSpread`.
    private func morphReaderCell(atSlot slot: Int, toSpread: Bool, focusPos: Int) {
        let indexPath = IndexPath(item: slot, section: 0)
        (collectionView.cellForItem(at: indexPath) as? ReaderPageCell)?
            .setRotationSpread(toSpread, focusPos: focusPos)
    }

    // MARK: Public

    /// Re-evaluate single vs double layout (e.g. the user toggled double-page).
    func syncLayoutMode() {
        // Not during a rotation — viewWillTransition already rebuilds the slots then,
        // and a second reloadData mid-rotation would re-read pages and snap the turn.
        guard let cv = collectionView, cv.bounds.width > 0, !isRotating else { return }
        let want = wantsDouble(for: cv.bounds.size)
        guard want != isDouble else { return }
        let page = currentPage
        isDouble = want
        cv.reloadData()
        cv.layoutIfNeeded()
        if let offset = offset(forSlot: paging.slot(forPage: page)) {
            cv.setContentOffset(offset, animated: false)
        }
    }

    /// Rebuilds visible pages (e.g. after the paper effect toggled).
    func reloadCurrent() {
        let page = currentPage
        collectionView.reloadData()
        DispatchQueue.main.async { [weak self] in
            guard let self, let offset = self.offset(forSlot: self.paging.slot(forPage: page)) else { return }
            self.collectionView.setContentOffset(offset, animated: false)
        }
    }

    /// Jumps to a page (page grid / bookmarks) instantly.
    func jump(to page: Int) {
        let target = clampPage(page)
        currentPage = target
        if let offset = offset(forSlot: paging.slot(forPage: target)) {
            collectionView.setContentOffset(offset, animated: false)
        }
        onPageChanged?(target)
        prefetchNeighbours(of: target)
    }

    // MARK: Navigation

    private func go(toSlot slot: Int, animated: Bool) {
        let target = min(max(slot, 0), max(paging.slotCount - 1, 0))
        guard target != paging.slot(forPage: currentPage), let offset = offset(forSlot: target) else { return }
        currentPage = paging.pages(inSlot: target).first ?? currentPage
        if animated {
            // Ease the offset each frame (not a UIView.animate to the destination) so
            // both pages glide, like a drag, with a snappy, lightly-bouncing settle —
            // see EasedScrollAnimator.
            isProgrammaticScroll = true
            pageTurn.animate(collectionView, to: offset,
                             duration: settings.pageTurnDuration,
                             overshoot: settings.movementOvershoot) { [weak self] in
                self?.isProgrammaticScroll = false
            }
        } else {
            pageTurn.cancel()
            collectionView.setContentOffset(offset, animated: false)
        }
        onPageChanged?(currentPage)
        prefetchNeighbours(of: currentPage)
    }

    private func offset(forSlot slot: Int, width: CGFloat? = nil) -> CGPoint? {
        let w = width ?? collectionView.bounds.width
        guard w > 0 else { return nil }
        return CGPoint(x: CGFloat(slot) * w, y: 0)
    }

    private func clampPage(_ page: Int) -> Int { min(max(page, 0), max(pageCount - 1, 0)) }
    private func wantsDouble(for size: CGSize) -> Bool { settings.doublePage && size.width > size.height }

    /// Warm the neighbouring pages. In double-page mode we also prefetch around the
    /// spread's right half so the *next* spread arrives with both pages ready —
    /// otherwise its right page would fade in on the swipe.
    private func prefetchNeighbours(of page: Int) {
        store.prefetch(around: page, maxPixel: ReaderPageCell.displayMaxPixel)
        if isDouble, let right = paging.pages(inSlot: paging.slot(forPage: page)).last, right != page {
            store.prefetch(around: right, maxPixel: ReaderPageCell.displayMaxPixel)
        }
    }

    // MARK: Data source

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { paging.slotCount }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: ReaderPageCell.reuseID, for: indexPath) as! ReaderPageCell
        cell.configure(slotIndex: indexPath.item,
                       pageIndices: paging.pages(inSlot: indexPath.item),
                       isDouble: isDouble,
                       store: store, settings: settings, delegate: self)
        return cell
    }

    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        cv.bounds.size
    }

    /// A slot that scrolls off screen resets to its default fit, so returning to it
    /// (or reusing the cell) never shows a stuck fit-height.
    func collectionView(_ cv: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        (cell as? ReaderPageCell)?.resetToDefault()
    }

    /// Warm the images for slots the collection view is about to need, so a tapped
    /// page turn lands on an already-decoded page (seamless, like a swipe) instead
    /// of a black flash.
    func collectionView(_ cv: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            for page in paging.pages(inSlot: indexPath.item) {
                store.requestImage(at: page, maxPixel: ReaderPageCell.displayMaxPixel) { _, _ in }
            }
        }
    }

    // MARK: Scroll tracking (user swipes)

    /// A finger on the page takes over from an in-flight tap turn: stop interpolating
    /// and hand control back to the scroll view so the drag (and its page sync) is clean.
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard pageTurn.isRunning else { return }
        pageTurn.cancel()
        isProgrammaticScroll = false
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { syncCurrentPage() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { syncCurrentPage() }
    }

    private func syncCurrentPage() {
        guard !isProgrammaticScroll, collectionView.bounds.width > 0 else { return }
        let slot = Int((collectionView.contentOffset.x / collectionView.bounds.width).rounded())
        let clamped = min(max(slot, 0), max(paging.slotCount - 1, 0))
        let landed = paging.pages(inSlot: clamped).first ?? 0
        guard landed != currentPage else { return }
        currentPage = landed
        onPageChanged?(landed)
        prefetchNeighbours(of: landed)
    }

    // MARK: ReaderPageCellDelegate

    func pageCell(_ cell: ReaderPageCell, didSingleTapAtX x: CGFloat, width: CGFloat) {
        // Tap-to-navigate is opt-in (off by default): unless it's enabled, a tap
        // anywhere just toggles the chrome and never turns the page. This applies to
        // every view (single, spread, focus) since all taps funnel through here.
        guard settings.tapToNavigate else { onToggleChrome?(); return }
        let slot = paging.slot(forPage: currentPage)
        if x < width * 0.25 {
            go(toSlot: slot - 1, animated: true)
        } else if x > width * 0.75 {
            go(toSlot: slot + 1, animated: true)
        } else {
            onToggleChrome?()
        }
    }
}
