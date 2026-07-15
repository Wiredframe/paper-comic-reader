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

    @AppStorage("library.columns") private var columns = 2
    @AppStorage(BookmarksViewMode.storageKey) private var viewModeRaw = BookmarksViewMode.defaultMode.rawValue
    @AppStorage("bookmarks.sortField") private var sortField = BookmarkSort.dateAdded.rawValue
    @AppStorage("bookmarks.sortAscending") private var sortAscending = false

    @State private var target: ReaderTarget?
    /// Bumped by the shuffle button in carousel mode — the deck glides to a random bookmark
    /// rather than opening one.
    @State private var randomTick = 0

    private var viewMode: BookmarksViewMode { .from(viewModeRaw) }

    /// Skip any orphaned bookmarks whose comic was deleted.
    private var validBookmarks: [Bookmark] { bookmarks.filter { $0.book != nil } }

    /// Bookmarks in the current sort order. Sorted in memory so the field/order can change live
    /// without a new @Query.
    private var sortedBookmarks: [Bookmark] {
        let ascending: [Bookmark]
        switch BookmarkSort(rawValue: sortField) ?? .dateAdded {
        case .dateAdded:
            ascending = validBookmarks.sorted { $0.dateAdded < $1.dateAdded }
        case .comic:
            // Keep a comic's bookmarks together, in reading order within it — a flat title sort
            // would scatter the pages of the same comic by whenever they happened to be made.
            ascending = validBookmarks.sorted {
                let lhs = $0.book?.title ?? "", rhs = $1.book?.title ?? ""
                if lhs != rhs { return lhs.localizedStandardCompare(rhs) == .orderedAscending }
                return $0.pageIndex < $1.pageIndex
            }
        case .page:
            // Tie-break on dateAdded: page numbers collide constantly across comics and
            // sorted(by:) isn't guaranteed stable, so ties would churn between recomputations.
            ascending = validBookmarks.sorted { ($0.pageIndex, $0.dateAdded) < ($1.pageIndex, $1.dateAdded) }
        }
        return sortAscending ? ascending : ascending.reversed()
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
                } else if viewMode == .carousel {
                    // No ScrollView here: the deck sizes its card from the real available
                    // height, the same way the Library's carousel does.
                    BookmarkCarouselView(bookmarks: sortedBookmarks, randomTrigger: randomTick) { mark in
                        open(mark)
                    } onOpenComic: { book in
                        target = ReaderTarget(book: book)
                    }
                } else if viewMode == .list {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedBookmarks) { mark in
                                BookmarkRow(bookmark: mark) { open(mark) } onDelete: { delete(mark) }
                                Divider().padding(.leading, 76)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, FloatingTabBar.reservedSpace)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: LibraryGridMetrics.spacing) {
                            ForEach(sortedBookmarks) { mark in
                                BookmarkCard(bookmark: mark,
                                             maxPixel: LibraryGridMetrics.coverMaxPixel(columns: columns)) {
                                    open(mark)
                                } onDelete: {
                                    delete(mark)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        // Clear the floating tab bar: its `.safeAreaInset` in RootTabView
                        // doesn't reach a ScrollView nested in a NavigationStack, so the last
                        // row would otherwise sit hidden behind the bar.
                        .padding(.bottom, FloatingTabBar.reservedSpace)
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .fullScreenCover(item: $target) { target in
            ReaderView(book: target.book, initialPage: target.page)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // In the carousel, shuffling means "show me something else" — glide the deck to
                // a random bookmark instead of yanking the reader open.
                if viewMode == .carousel { randomTick += 1 }
                else if let mark = validBookmarks.randomElement() { open(mark) }
            } label: {
                Image(systemName: "shuffle")
            }
            .accessibilityLabel(viewMode == .carousel ? "Show a random bookmark" : "Open a random bookmark")
            .disabled(validBookmarks.isEmpty)
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
        target = ReaderTarget(book: book, page: bookmark.pageIndex)
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
                    Text(bookmark.book?.title ?? "—")
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
