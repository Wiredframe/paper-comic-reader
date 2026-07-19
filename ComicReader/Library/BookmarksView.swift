//
//  BookmarksView.swift
//  Comic Reader
//
//  The "Bookmarks" tab: every bookmark from every comic, as a grid of page screenshots, a
//  compact list, or the peek carousel. Tapping one opens that comic straight to the bookmarked
//  page. Mirrors the Library tab's sort / view-mode machinery, on its own @AppStorage keys.
//

import SwiftUI
import SwiftData

/// How the bookmarks are ordered. Persisted as a raw string in @AppStorage, like `LibrarySort`.
enum BookmarkSort: String, CaseIterable {
    case dateAdded, comic, page
}

/// Which layout the Bookmarks tab shows. Its own key, so it doesn't move when the Library's
/// does — the two tabs are browsed for different reasons.
enum BookmarksViewMode: String, CaseIterable, Identifiable {
    case gallery, list, carousel

    var id: String { rawValue }
    static let storageKey = "bookmarks.viewMode"
    /// Same reasoning as the Library's: the deck shows the pages off, the grid lists them.
    static let defaultMode = carousel
    static func from(_ raw: String) -> BookmarksViewMode { BookmarksViewMode(rawValue: raw) ?? defaultMode }
}

struct BookmarksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bookmark.dateAdded, order: .reverse) private var bookmarks: [Bookmark]

    /// Cache backing the sorted/filtered list (see `derived`). A reference type so refreshing it
    /// mid-render doesn't count as a `@State` change.
    @State private var derivedCache = BookmarksDerived()

    @AppStorage("library.columns") private var columns = 2
    @AppStorage(BookmarksViewMode.storageKey) private var viewModeRaw = BookmarksViewMode.defaultMode.rawValue
    @AppStorage("bookmarks.sortField") private var sortField = BookmarkSort.dateAdded.rawValue
    @AppStorage("bookmarks.sortAscending") private var sortAscending = false

    @State private var target: ReaderTarget?
    /// Live search query — narrows to bookmarks whose comic matches on title / story title /
    /// issue number (see `ComicBook.matches`).
    @State private var searchText = ""
    /// Bumped by the shuffle button in carousel mode — the deck glides to a random bookmark
    /// rather than opening one.
    @State private var randomTick = 0
    /// Ties a bookmark's page card to the reader it opens, so the page grows into the reader
    /// instead of the reader sliding up over it — and the reader gains the system's drag-down
    /// dismiss along with it. Mirrors Library / Recents; the source is the *bookmark*, not the
    /// comic, so several bookmarks of one comic each zoom from their own card.
    @Namespace private var readerZoom

    private var viewMode: BookmarksViewMode { .from(viewModeRaw) }

    /// Skip any orphaned bookmarks whose comic was deleted.
    private var validBookmarks: [Bookmark] { bookmarks.filter { $0.book != nil } }

    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The single ordered + filtered list all three layouts render (carousel, list, grid), so
    /// search reaches every one. Read from the memoized derivation — the locale sort only reruns
    /// when `bookmarkSortSignature` changes, not on every @Query republish.
    private var displayedBookmarks: [Bookmark] { derived.displayed }

    /// Bookmarks in the current sort order, then narrowed by the search query (a bookmark matches
    /// when its comic does). Sorted in memory so the field/order can change live without a new
    /// @Query. Called only from `derived`, behind the signature cache.
    private func computeDisplayedBookmarks() -> [Bookmark] {
        let ascending: [Bookmark]
        switch BookmarkSort(rawValue: sortField) ?? .dateAdded {
        case .dateAdded:
            ascending = validBookmarks.sorted { $0.dateAdded < $1.dateAdded }
        case .comic:
            // Keep a comic's bookmarks together, in reading order within it — a flat title sort
            // would scatter the pages of the same comic by whenever they happened to be made.
            ascending = validBookmarks.sorted {
                let lhs = $0.book?.displayTitle ?? "", rhs = $1.book?.displayTitle ?? ""
                if lhs != rhs { return lhs.localizedStandardCompare(rhs) == .orderedAscending }
                return $0.pageIndex < $1.pageIndex
            }
        case .page:
            // Tie-break on dateAdded: page numbers collide constantly across comics and
            // sorted(by:) isn't guaranteed stable, so ties would churn between recomputations.
            ascending = validBookmarks.sorted { ($0.pageIndex, $0.dateAdded) < ($1.pageIndex, $1.dateAdded) }
        }
        var result = sortAscending ? ascending : ascending.reversed()
        if !trimmedQuery.isEmpty { result = result.filter { $0.book?.matches(searchQuery: trimmedQuery) ?? false } }
        return result
    }

    // MARK: Derived-list memoization (mirrors LibraryView)

    /// A hash of everything that can change the ordered/filtered output: the sort field/order, the
    /// search query, and per bookmark its identity, page and date — plus its comic's title only
    /// when that's actually consulted (the .comic sort or an active search). O(n) scalar hashing,
    /// far cheaper than the locale sort it gates, and the title is one the layouts already read.
    private var bookmarkSortSignature: Int {
        var hasher = Hasher()
        hasher.combine(sortField)
        hasher.combine(sortAscending)
        hasher.combine(trimmedQuery)
        hasher.combine(bookmarks.count)
        let readsComic = (BookmarkSort(rawValue: sortField) ?? .dateAdded) == .comic || !trimmedQuery.isEmpty
        for mark in bookmarks {
            hasher.combine(mark.id)
            hasher.combine(mark.pageIndex)
            hasher.combine(mark.dateAdded)
            if readsComic { hasher.combine(mark.book?.displayTitle) }
        }
        return hasher.finalize()
    }

    /// Resolves — and caches — the sorted/filtered list for the current inputs, recomputing only
    /// when `bookmarkSortSignature` changes. Same non-observable-`@State`-during-render technique
    /// as `LibraryView.derived`: no state-change, no loop, and synchronous (no empty frame).
    private var derived: BookmarksDerived {
        let signature = bookmarkSortSignature
        let cache = derivedCache
        if cache.signature != signature {
            cache.signature = signature
            cache.displayed = computeDisplayedBookmarks()
        }
        return cache
    }

    var body: some View {
        NavigationStack {
            Group {
                if validBookmarks.isEmpty {
                    ScrollView {
                        ContentUnavailableView("No bookmarks",
                                               systemImage: "bookmark",
                                               description: Text("Tap the bookmark button while reading a comic."))
                            .padding(.top, 80)
                    }
                } else if displayedBookmarks.isEmpty {
                    ScrollView { ContentUnavailableView.search(text: trimmedQuery).padding(.top, 80) }
                } else if viewMode == .carousel {
                    // No ScrollView here: the deck sizes its card from the real available
                    // height, the same way the Library's carousel does.
                    BookmarkCarouselView(bookmarks: displayedBookmarks, randomTrigger: randomTick,
                                         transitionNamespace: readerZoom) { mark in
                        open(mark)
                    } onOpenComic: { book in
                        // "Comic" opens the book itself, from the start — the counterpart to
                        // "Read", which lands on the bookmarked page. Page 0, not the resume page.
                        target = ReaderTarget(book: book, page: 0)
                    }
                } else if viewMode == .list {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(displayedBookmarks) { mark in
                                BookmarkRow(bookmark: mark) { open(mark) } onDelete: { delete(mark) }
                                Divider().padding(.leading, 76)
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: LibraryGridMetrics.spacing) {
                            ForEach(displayedBookmarks) { mark in
                                BookmarkCard(bookmark: mark,
                                             maxPixel: LibraryGridMetrics.coverMaxPixel(columns: columns)) {
                                    open(mark)
                                } onDelete: {
                                    delete(mark)
                                }
                            }
                        }
                        .padding(.horizontal, LibraryGridMetrics.spacing)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            // Search only in the browse layouts — the carousel is a swipe-deck, where a lookup
            // field is the wrong tool (same reasoning as Library's Discover).
            .comicSearchable(active: viewMode != .carousel, text: $searchText)
            // Entering the carousel has no field to clear the query, so clear it here or it would
            // keep narrowing the deck invisibly.
            .onChange(of: viewModeRaw) { _, raw in
                if BookmarksViewMode.from(raw) == .carousel { searchText = "" }
            }
            .toolbar { toolbar }
        }
        .fullScreenCover(item: $target) { target in
            ReaderView(book: target.book, initialPage: target.page)
                // Resolves against the centred bookmark's page card in the carousel deck, which
                // is keyed by the bookmark's id. Opens from the "Comic" button, the list and the
                // grid carry no matching source, so those fall back to the standard slide-up.
                .navigationTransition(.zoom(sourceID: target.sourceID ?? target.book.id, in: readerZoom))
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // In the carousel, shuffling means "show me something else" — glide the deck to
                // a random bookmark instead of yanking the reader open. Stays within the current
                // search results, like the deck it drives.
                if viewMode == .carousel { randomTick += 1 }
                else if let mark = displayedBookmarks.randomElement() { open(mark) }
            } label: {
                Image(systemName: "shuffle")
            }
            .accessibilityLabel(viewMode == .carousel ? "Show a random bookmark" : "Open a random bookmark")
            .disabled(displayedBookmarks.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Menu {
                    Picker("Sort By", selection: $sortField) {
                        Label("Date Added", systemImage: "calendar").tag(BookmarkSort.dateAdded.rawValue)
                        Label("Comic", systemImage: "book").tag(BookmarkSort.comic.rawValue)
                        Label("Page", systemImage: "number").tag(BookmarkSort.page.rawValue)
                    }
                    Divider()
                    Picker("Order", selection: $sortAscending) {
                        Label("Ascending", systemImage: "arrow.up").tag(true)
                        Label("Descending", systemImage: "arrow.down").tag(false)
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                Divider()
                Picker("View", selection: $viewModeRaw) {
                    Label("Gallery", systemImage: "square.grid.2x2").tag(BookmarksViewMode.gallery.rawValue)
                    Label("List", systemImage: "list.bullet").tag(BookmarksViewMode.list.rawValue)
                    Label("Carousel", systemImage: "rectangle.stack").tag(BookmarksViewMode.carousel.rawValue)
                }
                // Column zoom only means something in the gallery grid.
                if viewMode == .gallery {
                    Divider()
                    Button { columns = max(1, columns - 1) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                    Button { columns = min(4, columns + 1) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Sort and view options")
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: LibraryGridMetrics.spacing),
              count: max(1, columns))
    }

    private func open(_ bookmark: Bookmark) {
        guard let book = bookmark.book else { return }
        // sourceID is the bookmark's own id — the key its card carries in the carousel deck — so
        // the reader zooms out of that page. In list / gallery there's no such source and it
        // falls back to the slide-up.
        target = ReaderTarget(book: book, page: bookmark.pageIndex, sourceID: bookmark.id)
    }

    private func delete(_ bookmark: Bookmark) {
        try? Storage.fm.removeItem(at: bookmark.thumbURL)
        context.delete(bookmark)
        try? context.save()
    }
}

/// The list-mode row, mirroring the Library's comic row: small page shot, comic title, page.
private struct BookmarkRow: View {
    let bookmark: Bookmark
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                DiskImage(url: bookmark.thumbURL, contentMode: .fill, maxPixel: 260)
                    .frame(width: 44, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(bookmark.book?.displayTitle ?? "—")
                        .font(.body).foregroundStyle(.primary).lineLimit(2)
                    Text(bookmark.pageLabel)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Memoized product of the bookmark `@Query` — the sorted/filtered list. A plain (non-`@Observable`)
/// class so `BookmarksView` can hold it in `@State` and refresh it during a render without that
/// counting as a state change. See `BookmarksView.derived`.
private final class BookmarksDerived {
    var signature: Int?
    var displayed: [Bookmark] = []
}
