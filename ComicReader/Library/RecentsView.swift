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

    @AppStorage("library.columns") private var columns = 2
    @State private var openedBook: ComicBook?

    var body: some View {
        NavigationStack {
            ScrollView {
                if books.isEmpty {
                    ContentUnavailableView("No recent comics",
                                           systemImage: "clock",
                                           description: Text("Comics you open show up here."))
                        .padding(.top, 80)
                } else {
                    LibraryGrid(books: books, columns: columns, inRecents: true) { openedBook = $0 }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, FloatingTabBar.reservedSpace)
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
}
