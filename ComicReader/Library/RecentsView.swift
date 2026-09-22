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
    @Environment(FileOpenCoordinator.self) private var fileOpener

    @Query(filter: #Predicate<ComicBook> { $0.dateOpened != nil },
           sort: \ComicBook.dateOpened, order: .reverse)
    private var books: [ComicBook]

    @State private var target: ReaderTarget?
    /// Centres a comic in the carousel (a widget tap), so its cover is on screen to zoom out of.
    @State private var focusBookID: UUID?
    /// Ties the carousel's cover to the reader it opens — see LibraryView.
    @Namespace private var readerZoom

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
                    PeekCarouselView(books: books,
                                     showsFilters: false,
                                     onRemoveFromRecents: removeFromRecents,
                                     transitionNamespace: readerZoom,
                                     focusID: $focusBookID) { book, page in
                        target = ReaderTarget(book: book, page: page)
                    }
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
        .fullScreenCover(item: $target) { target in
            ReaderView(book: target.book, initialPage: target.page)
                .navigationTransition(.zoom(sourceID: target.book.id, in: readerZoom))
        }
        // A widget tap. On appear too: switching tabs creates this view with the request already
        // waiting. And on `openReaders`: a reader that was still up has just gone.
        .onAppear(perform: openWidgetRequest)
        .onChange(of: fileOpener.comicToken) { _, _ in openWidgetRequest() }
        .onChange(of: fileOpener.openReaders) { _, _ in openWidgetRequest() }
    }

    /// Opens the comic the Recent Comic widget was tapped for, at its resume page, zooming out of
    /// its cover in the carousel the way a tap on that cover would. That cover is the widget's own
    /// (the top of Recents), so the motion runs on from the widget, and the zoom is also what
    /// gives the reader its swipe-down dismiss.
    ///
    /// The cover is centred first and the reader presented a moment later: the zoom needs its
    /// source laid out on screen, and a freshly created carousel isn't yet on this runloop turn.
    private func openWidgetRequest() {
        guard fileOpener.openReaders == 0, target == nil,
              let id = fileOpener.pendingComicID else { return }
        focusBookID = id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard target == nil, fileOpener.openReaders == 0,
                  fileOpener.consumeComicID() == id else { return }
            var descriptor = FetchDescriptor<ComicBook>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            guard let book = try? context.fetch(descriptor).first else {
                // Deleted since the widget was drawn: nothing to open, and the widget is stale.
                RecentComicSync.refresh(in: context)
                return
            }
            target = ReaderTarget(book: book)
        }
    }

    /// Clears the Recents list by forgetting every open date. Comics and their
    /// bookmarks stay untouched — only the "recently read" ordering is reset.
    private func clearRecents() {
        for book in books { book.dateOpened = nil }
        try? context.save()
        RecentComicSync.refresh(in: context)
    }

    /// Drops one comic from Recents without touching the library, its bookmarks or its open
    /// count — just forgets when it was last opened. (The cover grid offered this in its
    /// context menu; the carousel puts it in the info panel.)
    private func removeFromRecents(_ book: ComicBook) {
        book.dateOpened = nil
        try? context.save()
        RecentComicSync.refresh(in: context)
    }
}
