//
//  ReaderCollectionController.swift
//  Comic Reader
//
//  The landscape reader: a horizontal, paging UICollectionView of page slots. With
//  double-page off a slot is one page; with it on a slot is a spread. The page↔slot
//  pairing is FIXED (the cover, page 1, is always alone, then pages pair up: 2·3, 4·5, …),
//  so a page that is the right half of a spread can never become the left half of another,
//  and a bookmark or resume page always lands on the same spread. Portrait is the strip
//  (ReaderStripController); ReaderContainerController hands over between the two.
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

final class ReaderCollectionController: UIViewController,
                                        UICollectionViewDataSource,
                                        UICollectionViewDataSourcePrefetching,
                                        UICollectionViewDelegateFlowLayout,
                                        UIGestureRecognizerDelegate,
                                        ReaderPageCellDelegate {

    private let store: PageImageStore
    private let settings: ReaderSettings
    let pageCount: Int
    /// The page the reader considers current. Source of truth across rotations.
    private(set) var currentPage: Int

    private var isDouble = false
    private var isRotating = false
    private var isTurning = false
    private var isProgrammaticScroll = false
    private var pendingInitialScroll = true

    /// The outgoing page's snapshot during a tap page turn (see `animatePageTurn`). While
    /// it's on screen it also gates touches, so a turn can't be interrupted mid-flight.
    private var turnSnapshot: UIView?

    /// The reader is reading one half of a spread at fit-width (picked up by a double-tap zoom,
    /// put down by the double tap back out). Kept here because cells are recycled and this has to
    /// outlive them: with Keep Zoom Across Pages on it's what makes the NEXT slot open zoomed too.
    /// Tracked whether or not the setting is on (only `isCarrying` reads the setting), so switching
    /// it mid-read doesn't need the reader to be re-armed.
    private var carriesFocus = false

    /// The slot on screen was entered from its END (a backward page change while the fit-width look
    /// is carried), so it rests at the bottom of its page rather than the top. The half it rests on
    /// needs no flag of its own: that is `currentPage`, which already follows the page being read.
    /// Only `land(onSlot:)` and `settle(onPage:)` write this and `currentPage`, and they always
    /// write both, so the two can't drift apart.
    private var entryAtBottom = false

    var onPageChanged: ((Int) -> Void)?
    /// Fires when the slot now on screen holds the FINAL page. Separate from onPageChanged
    /// because `currentPage` is the slot's LEFT half: for an odd-length comic in double-page
    /// mode the last page is the right half of the closing spread and so never equals
    /// currentPage — a `currentPage == last` read check would never fire (see ReaderView.markRead).
    var onReachedEnd: (() -> Void)?
    var onToggleChrome: (() -> Void)?
    var onDismissRequest: (() -> Void)?

    /// Pull down to close. The system's drag-down dismiss is off in landscape (see ReaderView),
    /// so the reader offers its own: the pages follow the finger down, and far or fast enough a
    /// release asks to close, which rotates to portrait first and then zooms back to the cover.
    private var dismissPan: UIPanGestureRecognizer!
    private var isPullingDown = false
    /// How far (share of the height) or how fast (points per second) a pull has to go to close.
    private static let dismissDistance: CGFloat = 0.18
    private static let dismissVelocity: CGFloat = 900

    private let layout = PagingFlowLayout()
    private var collectionView: UICollectionView!

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

        dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        dismissPan.delegate = self
        view.addGestureRecognizer(dismissPan)

        store.setActivePage(currentPage)   // before the first prefetch, so a resume deep in the comic isn't skipped
        prefetchNeighbours(of: currentPage)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Own the frame for every NON-rotation layout (initial size, safe-area / split
        // changes). During a rotation the coordinator block below drives it instead, and
        // during a tap page turn the collection view carries a transform (see
        // animatePageTurn) that a frame assignment would fight — so in both cases we leave
        // it alone and reconcile the frame when the animation completes.
        if !isRotating && !isTurning && !isPullingDown { collectionView.frame = view.bounds }
        guard collectionView.bounds.width > 0, pageCount > 0 else { return }
        // Self-healing: paging being off is the one state a missed sync could strand the reader
        // in, so every settled layout re-derives it from the cell rather than trusting the last
        // write. Cheap (one lookup, one Bool) and skipped mid-rotation, where fits are transient.
        if !isRotating { syncSidewaysNavigation() }
        if pendingInitialScroll {
            isDouble = wantsDouble(for: collectionView.bounds.size)
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            if let offset = offset(forSlot: paging.slot(forPage: currentPage)) {
                collectionView.contentOffset = offset
            }
            pendingInitialScroll = false
            syncSidewaysNavigation()
        }
    }

    /// A size change that stays landscape (iPad multitasking): re-fit the slots to the new width
    /// inside the transition's own animation. Crossing into portrait never reaches here; the
    /// container swaps to the strip instead (see ReaderContainerController).
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        endActiveTurn()                 // settle any in-flight page turn before resizing
        carriesFocus = false
        settle(onPage: currentPage)
        isRotating = true
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.collectionView.frame = CGRect(origin: .zero, size: size)
            self.layout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
            if let offset = self.offset(forSlot: self.paging.slot(forPage: self.currentPage)) {
                self.collectionView.contentOffset = offset
            }
        }, completion: { [weak self] _ in
            guard let self else { return }
            self.isRotating = false
            self.collectionView.frame = self.view.bounds   // reconcile any drift
            self.syncSidewaysNavigation()
        })
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
        syncSidewaysNavigation()
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
        endActiveTurn()
        let target = clampPage(page)
        let slot = paging.slot(forPage: target)
        // A jump is a page change too, so the carried fit-width look comes along, on the page that
        // was actually asked for: a bookmark on a right page opens on that right page. Landing
        // inside the spread already on screen brings no new cell with it, hence the refresh.
        land(onSlot: slot, page: target)
        if let offset = offset(forSlot: slot) {
            collectionView.setContentOffset(offset, animated: false)
        }
        refreshVisibleOpenings()
        notifyPageChange()
        prefetchNeighbours(of: target)
    }

    // MARK: Navigation

    private func go(toSlot slot: Int, animated: Bool, swiped: Bool = false) {
        let target = min(max(slot, 0), max(paging.slotCount - 1, 0))
        guard target != paging.slot(forPage: currentPage), let offset = offset(forSlot: target) else { return }
        // Land BEFORE the offset moves: the cell can be shown at any point after this (a prefetched
        // one may already exist), and `opening(forSlot:)` reads the landing, not the other way
        // round, so nothing depends on when that happens.
        land(onSlot: target)
        if animated {
            animatePageTurn(to: offset, swiped: swiped)
        } else {
            endActiveTurn()
            collectionView.setContentOffset(offset, animated: false)
        }
        notifyPageChange()
        prefetchNeighbours(of: currentPage)
    }

    /// A tap page turn, driven by Core Animation so it runs on the render server at the full
    /// ProMotion rate (like the double-tap zoom and the rotation) rather than a main-thread
    /// per-frame loop, which drops frames on any main-thread hitch.
    ///
    /// The outgoing page is snapshotted and the *live* collection view — already committed to
    /// the destination offset — is slid in from the opposite edge by animating its transform;
    /// both slides are a single `UIView.animate` (standard ease-in-out). The snapshot sits on
    /// top for the duration, so it also swallows taps and the turn can't be interrupted into
    /// an inconsistent state.
    private func animatePageTurn(to targetOffset: CGPoint, swiped: Bool = false) {
        endActiveTurn()
        let width = collectionView.bounds.width
        guard width > 0, let snapshot = collectionView.snapshotView(afterScreenUpdates: false) else {
            collectionView.setContentOffset(targetOffset, animated: false)
            return
        }
        let forward = targetOffset.x > collectionView.contentOffset.x
        let cvFrame = collectionView.frame

        isTurning = true
        isProgrammaticScroll = true

        // Cover the screen with the current page, then commit the live view to the target and
        // push it one screen-width off the incoming edge — all behind the snapshot, so there
        // is no visible jump before the slide.
        snapshot.frame = cvFrame
        snapshot.isUserInteractionEnabled = true      // swallow taps until the turn settles
        view.addSubview(snapshot)
        turnSnapshot = snapshot
        collectionView.setContentOffset(targetOffset, animated: false)
        collectionView.transform = CGAffineTransform(translationX: forward ? width : -width, y: 0)

        UIView.animate(withDuration: swiped ? settings.swipeTurnDuration : settings.pageTurnDuration,
                       delay: 0, options: [swiped ? .curveEaseOut : .curveEaseInOut]) {
            snapshot.frame = cvFrame.offsetBy(dx: forward ? -width : width, dy: 0)
            self.collectionView.transform = .identity
        } completion: { [weak self] _ in
            self?.endActiveTurn()
        }
    }

    /// Tear down a page turn — remove the outgoing snapshot and reconcile the collection
    /// view's transform / frame. Safe to call when no turn is running, and idempotent, so it
    /// doubles as the animation's completion and as a "settle now" for jumps / rotations that
    /// arrive mid-turn.
    private func endActiveTurn() {
        guard isTurning else { return }
        turnSnapshot?.removeFromSuperview()
        turnSnapshot = nil
        collectionView.transform = .identity
        collectionView.frame = view.bounds
        isTurning = false
        isProgrammaticScroll = false
    }

    private func offset(forSlot slot: Int) -> CGPoint? {
        let w = collectionView.bounds.width
        guard w > 0 else { return nil }
        return CGPoint(x: CGFloat(slot) * w, y: 0)
    }

    private func clampPage(_ page: Int) -> Int { min(max(page, 0), max(pageCount - 1, 0)) }
    private func wantsDouble(for size: CGSize) -> Bool { settings.doublePage && size.width > size.height }

    // MARK: Reading position (and Keep Zoom Across Pages)

    /// Whether the reader is carrying the fit-width look at all. Asked at the moment a slot is
    /// shown, never remembered on a cell, so turning the zoom on or off can't leave a slot behind
    /// in the state it had when it was built.
    private var isCarrying: Bool { settings.keepZoom && carriesFocus && isDouble }

    /// The reader moved to another slot: a page turn, a swipe, a jump to `page`.
    ///
    /// One rule for all of them, in one place. Reading backward while the fit-width look is carried
    /// enters the slot on its LAST page at the bottom, where reading forward would have left it;
    /// everything else enters on the first page from the top. A jump names its own page and always
    /// arrives at the top.
    private func land(onSlot slot: Int, page: Int? = nil) {
        let pages = paging.pages(inSlot: slot)
        let fromEnd = page == nil && isCarrying && slot < paging.slot(forPage: currentPage)
        entryAtBottom = fromEnd
        currentPage = page ?? ((fromEnd ? pages.last : pages.first) ?? currentPage)
    }

    /// The reader moved WITHIN the slot on screen: a double-tap zoom, a tap-scroll across the
    /// gutter, a hand pan. The page it rests on is now the cell's business, not the arrival's.
    private func settle(onPage page: Int) {
        entryAtBottom = false
        currentPage = page
    }

    /// How `slot` should look when it goes on screen. The single source for it, so a slot can't be
    /// prepared one way and shown another.
    ///
    /// The slot on screen reads its half straight off `currentPage`, which already follows the page
    /// being read, so it stays right however long ago the cell was built. Slots either side are
    /// answered by direction: ahead of the reader opens on the left page from the top, behind on
    /// the right page at the bottom. That also covers a swipe, whose incoming cell is prepared
    /// while dragging, before `currentPage` moves.
    private func opening(forSlot slot: Int) -> ReaderPageCell.Opening {
        let pages = paging.pages(inSlot: slot)
        guard isCarrying, !pages.isEmpty else { return .standard }
        let currentSlot = paging.slot(forPage: currentPage)
        if slot == currentSlot {
            return .page(column: pages.firstIndex(of: currentPage) ?? 0, atEnd: entryAtBottom)
        }
        return slot < currentSlot ? .page(column: pages.count - 1, atEnd: true)
                                  : .page(column: 0, atEnd: false)
    }

    /// Re-settle what is already on screen. `willDisplay` covers every slot that ARRIVES; this is
    /// for the move that doesn't bring one in, a jump landing inside the spread already shown.
    private func refreshVisibleOpenings() {
        for case let cell as ReaderPageCell in collectionView.visibleCells {
            cell.prepareForDisplay(opening(forSlot: cell.slotIndex))
        }
    }

    /// Report the current page, then — separately — whether the slot on screen holds the final
    /// page. `currentPage` is the slot's left half, so the last page of an odd-length comic in
    /// double mode is the right half of the closing spread and never equals it; downstream
    /// read-status would otherwise never fire. See `onReachedEnd`.
    private func notifyPageChange() {
        store.setActivePage(currentPage)   // lets superseded prefetch decodes bail (see PageImageStore)
        onPageChanged?(currentPage)
        syncSidewaysNavigation()           // every caller here has just changed the slot or its half
        if pageCount > 0,
           paging.pages(inSlot: paging.slot(forPage: currentPage)).contains(pageCount - 1) {
            onReachedEnd?()
        }
    }

    /// Warm the neighbouring pages. In double-page mode we also prefetch around the
    /// spread's right half so the *next* spread arrives with both pages ready —
    /// otherwise its right page would fade in on the swipe.
    private func prefetchNeighbours(of page: Int) {
        store.prefetch(around: page)
        if isDouble, let right = paging.pages(inSlot: paging.slot(forPage: page)).last, right != page {
            store.prefetch(around: right)
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

    /// How a slot looks is decided HERE, and only here: this is the one callback that fires every
    /// time a slot actually goes on screen. `cellForItemAt` is not that moment (the collection view
    /// builds cells ahead of time and shows them again without rebuilding them), so a look decided
    /// there would be whatever the reader was doing when the cell happened to be built.
    /// This runs before the cell is drawn, so settling it here is invisible.
    func collectionView(_ cv: UICollectionView, willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        (cell as? ReaderPageCell)?.prepareForDisplay(opening(forSlot: indexPath.item))
        syncSidewaysNavigation()
    }

    /// A slot that scrolls off screen drops back to its default fit, so a stuck fit-height never
    /// greets you on the way back. What it opens at when it returns is decided in `willDisplay`.
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
                store.prefetchImage(at: page)
            }
        }
    }

    // MARK: Scroll tracking (user swipes)

    // A tap page turn can't be interrupted by a drag — its snapshot overlay swallows touches
    // until it settles (see animatePageTurn) — so there's nothing to hand back here; a swipe
    // only ever begins from a resting collection view.

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { syncCurrentPage() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { syncCurrentPage() }
    }

    private func syncCurrentPage() {
        guard !isProgrammaticScroll, collectionView.bounds.width > 0 else { return }
        let slot = Int((collectionView.contentOffset.x / collectionView.bounds.width).rounded())
        let clamped = min(max(slot, 0), max(paging.slotCount - 1, 0))
        guard clamped != paging.slot(forPage: currentPage) else { return }
        land(onSlot: clamped)          // same landing rule as a tapped turn, direction and all
        notifyPageChange()
        prefetchNeighbours(of: currentPage)
    }

    // MARK: ReaderPageCellDelegate

    func pageCell(_ cell: ReaderPageCell, didSingleTapAtX x: CGFloat, width: CGFloat) {
        // Tap-to-navigate is on by default (the user can turn it off): when it's off, a tap
        // anywhere just toggles the chrome and never turns the page. This applies to
        // every view (single, spread, focus) since all taps funnel through here.
        guard settings.tapToNavigate else { onToggleChrome?(); return }
        let slot = paging.slot(forPage: currentPage)
        // The shared nav zones (ReaderMetrics), so where a single tap navigates here exactly
        // matches where it fires instantly in the cell.
        if ReaderMetrics.isNavEdge(x, width: width) {
            go(toSlot: x < width / 2 ? slot - 1 : slot + 1, animated: true)
        } else {
            onToggleChrome?()
        }
    }

    /// The visible spread is now focused on a specific half (double-tap zoom, or a tap-scroll
    /// that crossed the gutter). Make that page current so rotation lands on it and the bookmark
    /// button acts on it — without moving the collection view, which stays on the same slot.
    func pageCell(_ cell: ReaderPageCell, didFocusPageAt globalIndex: Int) {
        let target = clampPage(globalIndex)
        guard target != currentPage else { return }
        settle(onPage: target)
        notifyPageChange()
        prefetchNeighbours(of: target)
    }

    /// A double tap zoomed into one half of the spread, or put it back down. That gesture is the
    /// on / off switch for the carried fit-width look, held here rather than in the cell because
    /// the cell is recycled at the next page change and this has to survive it.
    func pageCell(_ cell: ReaderPageCell, didChangeFitWidthFocus focused: Bool) {
        carriesFocus = focused
        settle(onPage: currentPage)   // the reader is driving the page now, not its arrival
        syncSidewaysNavigation()
    }

    /// The slot on screen is zoomed into its last half this way and has nothing left to cross to,
    /// so the swipe means the next / previous spread after all.
    func pageCell(_ cell: ReaderPageCell, didRequestTurn forward: Bool) {
        let slot = paging.slot(forPage: currentPage)
        go(toSlot: forward ? slot + 1 : slot - 1, animated: true, swiped: true)
    }

    func pageCellDidChangeSidewaysOwnership(_ cell: ReaderPageCell) {
        guard !isRotating else { return }   // the rotation re-syncs in its completion
        syncSidewaysNavigation()
    }

    /// Hand the collection view's paging to the slot on screen while it is zoomed into one half of
    /// a spread, and take it back the moment it isn't.
    ///
    /// Paging is by SLOT, and a slot is the whole spread, so a swipe from the left half turns past
    /// the right half without ever showing it. With Keep Zoom Across Pages on, the next spread
    /// then opens on ITS left half, and a reader who only ever swipes sees no right page at all.
    /// While the cell owns the direction it answers the swipe itself, crossing the gutter first
    /// and asking for a turn only when there is nothing left to cross to — the same order the edge
    /// taps have always used.
    ///
    /// Pulled from the cell rather than tracked here on purpose: the cell's `fit` is the fact, and
    /// two copies of a fact drift. Called from every path that can change either the slot on
    /// screen or its fit.
    private func syncSidewaysNavigation() {
        let slot = paging.slot(forPage: currentPage)
        let cell = collectionView.cellForItem(at: IndexPath(item: slot, section: 0)) as? ReaderPageCell
        collectionView.isScrollEnabled = !(cell?.ownsSidewaysNavigation ?? false)
    }


    // MARK: Pull down to close

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let height = max(view.bounds.height, 1)
        let pull = max(gesture.translation(in: view).y, 0)
        switch gesture.state {
        case .began:
            isPullingDown = true
            // The pull owns the touch now: stop the collection view's own pan from nudging the
            // band sideways with any drift in the finger (toggling it off cancels it).
            collectionView.panGestureRecognizer.isEnabled = false
            collectionView.panGestureRecognizer.isEnabled = true
        case .changed:
            // Follows the finger, easing off a little as it goes, like the system's own dismiss.
            let scale = 1 - min(pull / height, 1) * 0.12
            collectionView.transform = CGAffineTransform(translationX: 0, y: pull).scaledBy(x: scale, y: scale)
        case .ended, .cancelled, .failed:
            let closes = gesture.state == .ended
                && (pull > height * Self.dismissDistance || gesture.velocity(in: view).y > Self.dismissVelocity)
            UIView.animate(withDuration: settings.uiAnimationDuration, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState]) {
                self.collectionView.transform = .identity
            } completion: { _ in
                self.isPullingDown = false
                self.view.setNeedsLayout()
            }
            // The page settles back while the reader turns to portrait underneath, so what
            // zooms back to the cover is the page as it was, not a half-dragged one.
            if closes { onDismissRequest?() }
        default:
            break
        }
    }

    /// Only a pull that starts clearly downward, on a slot already at the top of its page, and
    /// with nothing else moving: everything else stays the page's or the collection view's.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan else { return true }
        guard !isTurning, !isRotating, collectionView.isDragging == false else { return false }
        let v = dismissPan.velocity(in: view)
        guard v.y > 0, v.y > abs(v.x) * 1.5 else { return false }
        let slot = paging.slot(forPage: currentPage)
        let cell = collectionView.cellForItem(at: IndexPath(item: slot, section: 0)) as? ReaderPageCell
        return cell?.isScrolledToTop ?? true
    }

    /// Alongside the page's own scroll view: at the top of a page it has nothing to do with a
    /// pull down anyway (it never bounces), and it must not be the one to swallow it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer === dismissPan && !(other is UIPinchGestureRecognizer)
    }
}
