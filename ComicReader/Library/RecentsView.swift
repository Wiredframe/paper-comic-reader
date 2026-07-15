//
//  RecentsView.swift
//  Comic Reader
//
//  The "Recents" tab: comics ordered by when they were last opened.
//

import SwiftUI
import SwiftData

struct RecentsView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<ComicBook> { $0.dateOpened != nil },
           sort: \ComicBook.dateOpened, order: .reverse)
    private var books: [ComicBook]

    @State private var openedBook: ComicBook?

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    ScrollView {
                        ContentUnavailableView("No recent comics",
                                               systemImage: "clock",
                                               description: Text("Comics you open show up here."))
                            .padding(.top, 80)
                    }
                } else {
                    // The cover carousel, in the order the @Query already gives us (most
                    // recently opened first) — so no filter segments here.
                    PeekCarouselView(books: books, showsFilters: false,
                                     onRemoveFromRecents: removeFromRecents) { openedBook = $0 }
                }
            }
            .navigationTitle("Recents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !books.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", systemImage: "clock.badge.xmark", action: clearRecents)
                    }
                }
            }
        }
        .fullScreenCover(item: $openedBook) { book in
            ReaderView(book: book)
        }
    }

    /// Clears the Recents list by forgetting every open date. Comics and their
    /// bookmarks stay untouched — only the "recently read" ordering is reset.
    private func clearRecents() {
        for book in books { book.dateOpened = nil }
        try? context.save()
    }

    /// Drops one comic from Recents without touching the library, its bookmarks or its open
    /// count — just forgets when it was last opened. (The cover grid offered this in its
    /// context menu; the carousel puts it in the info panel.)
    private func removeFromRecents(_ book: ComicBook) {
        book.dateOpened = nil
        try? context.save()
    }
}
