//
//  BookmarksView.swift
//  Comic Reader
//
//  The "Bookmarks" tab: every bookmark from every comic, as page-screenshot cards
//  with a compact caption (comic · page). Tapping one opens that comic straight to
//  the bookmarked page.
//

import SwiftUI
import SwiftData

struct BookmarksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bookmark.dateAdded, order: .reverse) private var bookmarks: [Bookmark]
    @AppStorage("library.columns") private var columns = 2

    @State private var target: ReaderTarget?

    /// Skip any orphaned bookmarks whose comic was deleted.
    private var validBookmarks: [Bookmark] { bookmarks.filter { $0.book != nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if validBookmarks.isEmpty {
                    ContentUnavailableView("No bookmarks",
                                           systemImage: "bookmark",
                                           description: Text("Tap the bookmark button while reading a comic."))
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: LibraryGridMetrics.spacing) {
                        ForEach(validBookmarks) { bookmark in
                            BookmarkCard(bookmark: bookmark,
                                         maxPixel: LibraryGridMetrics.coverMaxPixel(columns: columns)) {
                                if let book = bookmark.book {
                                    target = ReaderTarget(book: book, page: bookmark.pageIndex)
                                }
                            } onDelete: {
                                delete(bookmark)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, FloatingTabBar.reservedSpace)
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let bookmark = validBookmarks.randomElement(), let book = bookmark.book {
                            target = ReaderTarget(book: book, page: bookmark.pageIndex)
                        }
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .accessibilityLabel("Open a random bookmark")
                    .disabled(validBookmarks.isEmpty)
                }
            }
        }
        .fullScreenCover(item: $target) { target in
            ReaderView(book: target.book, initialPage: target.page)
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: LibraryGridMetrics.spacing),
              count: max(1, columns))
    }

    private func delete(_ bookmark: Bookmark) {
        try? Storage.fm.removeItem(at: bookmark.thumbURL)
        context.delete(bookmark)
        try? context.save()
    }
}
