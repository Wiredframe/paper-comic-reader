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
    /// Fired at the start of a device rotation. The chrome (and with it the status
    /// bar) is revealed for the turn so the resize animates smoothly; it auto-hides
    /// again shortly after.
    var onWillRotate: (() -> Void)?

    private let layout = PagingFlowLayout()
    private var collectionView: UICollectionView!

    private var paging: ReaderPaging { ReaderPaging(pageCount: pageCount, double: isDouble) }

    init(store: PageImageStore, settings: ReaderSettings, startIndex: Int) {
        self.store = store
        self.settings = settings
        self.pageCount = max(store.pageCount, 0)
        self.currentPage = min(max(startIndex, 0), max(pageCount - 1, 0))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

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
        collectionView.backgroundColor = .black
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.register(ReaderPageCell.self, forCellWithReuseIdentifier: ReaderPageCell.reuseID)
        view.addSubview(collectionView)

        prefetchNeighbours(of: currentPage)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
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
        let newDouble = wantsDouble(for: size)
        isRotating = true
        // Reveal the chrome (and status bar) so the rotation resizes under a stable
        // safe area and animates smoothly; it auto-hides again a couple seconds later.
        onWillRotate?()

        // A single<->double change needs a reloadData; do it once, up front (never
        // mid-animation, which would rebuild every cell and snap the turn), and
        // restore the current slot's offset since reloadData resets it to zero.
        if newDouble != isDouble {
            isDouble = newDouble
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            if let offset = offset(forSlot: paging.slot(forPage: currentPage)) {
                collectionView.contentOffset = offset
            }
        }
        // The offset for the NEW width is supplied by PagingFlowLayout's
        // targetContentOffset as the bounds change, so the turn animates straight to
        // the right page — no manual, after-the-fact correction that snaps.
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.isRotating = false
        }
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
            let duration = settings.fastAnimations ? 0.14 : 0.28
            isProgrammaticScroll = true
            UIView.animate(withDuration: duration, delay: 0,
                           options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
                self.collectionView.setContentOffset(offset, animated: false)
            } completion: { _ in
                self.isProgrammaticScroll = false
            }
        } else {
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
