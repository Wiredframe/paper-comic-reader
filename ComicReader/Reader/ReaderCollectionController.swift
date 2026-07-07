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
    /// Reading a single spread page zoomed to full width: we temporarily drop to
    /// single-page slots so navigation is page-by-page. Cleared on rotation.
    private var spreadFocus = false
    private var isProgrammaticScroll = false
    private var pendingInitialScroll = true

    var onPageChanged: ((Int) -> Void)?
    var onToggleChrome: (() -> Void)?

    private let layout = UICollectionViewFlowLayout()
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
        let page = currentPage
        let newDouble = wantsDouble(for: size)
        // A rotation ends any single-page "focus" — go back to the natural layout.
        let rebuild = newDouble != isDouble || spreadFocus

        // Keep this minimal: let UIKit resize the collection view and re-fit the
        // cells (each cell re-fits in its own layoutSubviews, inside the rotation
        // animation — see ReaderPageCell). Here we only rebuild slots if the layout
        // mode flips and restore the current page's scroll position for the new
        // width. Doing less makes the rotation smooth and identical whether the
        // chrome / status bar is shown or hidden.
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            if rebuild {
                self.spreadFocus = false
                self.isDouble = newDouble
                self.collectionView.reloadData()
            }
            if let offset = self.offset(forSlot: self.paging.slot(forPage: page), width: size.width) {
                self.collectionView.setContentOffset(offset, animated: false)
            }
        })
    }

    // MARK: Public

    /// Re-evaluate single vs double layout (e.g. the user toggled double-page).
    func syncLayoutMode() {
        // While zoomed into a spread page (single-page focus) the single layout is
        // intentional — don't let a routine update snap it back to spreads.
        guard let cv = collectionView, cv.bounds.width > 0, !spreadFocus else { return }
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
                       isFocusedSingle: spreadFocus,
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

    /// Zoom into a spread's page: drop to single-page slots at that page so reading
    /// is page-by-page and full-width (double-tap again returns to the spread).
    func pageCell(_ cell: ReaderPageCell, didRequestFocusOnPage page: Int) {
        guard isDouble else { return }
        spreadFocus = true
        isDouble = false
        setLayout(scrollingToPage: clampPage(page))
        zoomPopCurrentCell()
        onPageChanged?(currentPage)
    }

    func pageCellDidRequestExitFocus(_ cell: ReaderPageCell) {
        guard spreadFocus else { return }
        spreadFocus = false
        isDouble = wantsDouble(for: collectionView.bounds.size)
        setLayout(scrollingToPage: currentPage)
        zoomPopCurrentCell()
    }

    /// Rebuild the slots for the current `isDouble`/`spreadFocus` and land on `page`.
    private func setLayout(scrollingToPage page: Int) {
        currentPage = page
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        if let offset = offset(forSlot: paging.slot(forPage: page)) {
            collectionView.setContentOffset(offset, animated: false)
        }
        prefetchNeighbours(of: page)
    }

    /// A quick scale-in on the current page — the zoom "pop" when entering or leaving
    /// the full-width single-page view (the layout swap itself is instant).
    private func zoomPopCurrentCell() {
        let slot = paging.slot(forPage: currentPage)
        guard let cell = collectionView.cellForItem(at: IndexPath(item: slot, section: 0)) else { return }
        cell.contentView.alpha = 0.5
        cell.contentView.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
        UIView.animate(withDuration: settings.fastAnimations ? 0.22 : 0.32, delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            cell.contentView.alpha = 1
            cell.contentView.transform = .identity
        }
    }
}
