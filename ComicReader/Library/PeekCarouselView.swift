//
//  PeekCarouselView.swift
//  Comic Reader
//
//  The cover carousel: one large, uncropped cover centred with its neighbours peeking in
//  either side, swiped left/right, with the centred comic's details pinned below and its
//  bookmarks one page further down. Used by the Library's "Discover" mode (which adds the
//  filter segments) and by Recents.
//
//  Ordering is NOT decided here — the caller hands the books in already, so Discover follows
//  the Library's sort menu and Recents its most-recent-first query. The segments only pick
//  WHICH comics are in the deck.
//

import SwiftUI
import SwiftData

/// Which comics the Library's Discover mode puts in the deck. Order comes from the sort menu;
/// this only filters. Raw string in @AppStorage, like `LibrarySort` / `LibraryViewMode`.
enum DiscoveryFilter: String, CaseIterable, Identifiable {
    case discover, popular, dust

    var id: String { rawValue }

    var label: String {
        switch self {
        case .discover: return "Discover"
        case .popular:  return "Popular"
        case .dust:     return "Gathering Dust"
        }
    }

    /// Popularity is "you came back to it" (opened more than once); dust is "you never opened
    /// it at all". A comic opened exactly once is neither — it only shows under Discover.
    func matches(_ book: ComicBook) -> Bool {
        switch self {
        case .discover: return true
        case .popular:  return book.openCount >= 2
        case .dust:     return book.openCount == 0
        }
    }

    var emptyTitle: String {
        switch self {
        case .discover: return "No comics"
        case .popular:  return "Nothing's popular yet"
        case .dust:     return "Nothing's gathering dust"
        }
    }

    var emptyMessage: String {
        switch self {
        case .discover: return "Import a CBZ or CBR to get started."
        case .popular:  return "Comics you open more than once show up here."
        case .dust:     return "You've opened every comic in your library."
        }
    }

    var emptyIcon: String {
        switch self {
        case .discover: return "books.vertical"
        case .popular:  return "flame"
        case .dust:     return "wind"
        }
    }

    static func from(_ raw: String) -> DiscoveryFilter { DiscoveryFilter(rawValue: raw) ?? .discover }
}

struct PeekCarouselView: View {
    /// Already in the order they should appear — the Library passes its sorted books, Recents
    /// its most-recently-opened-first query.
    let books: [ComicBook]
    /// Library shows the filter segments; Recents doesn't (its deck is simply "what you opened").
    var showsFilters: Bool = true
    /// Bumped by the Library's shuffle button to glide to a random comic in the current deck.
    var randomTrigger: Int = 0
    /// Only Recents supplies this — it puts a "forget this one" button in the panel, which the
    /// cover grid used to offer via its context menu.
    var onRemoveFromRecents: ((ComicBook) -> Void)? = nil
    /// Pair with `.navigationTransition(.zoom(sourceID: book.id, in:))` on the reader the
    /// caller presents: the cover grows into the reader, and the presentation gains the
    /// system's interactive drag-down dismiss.
    var transitionNamespace: Namespace.ID? = nil
    /// Set by the Library to bring one comic to the centre — used when a comic is opened from
    /// outside the app, which focuses it here rather than opening the reader. One-shot: cleared
    /// back to nil once the deck has moved, so returning to this view later doesn't re-snap.
    var focusID: Binding<UUID?>? = nil
    /// The page is nil for "open where you left off", or a bookmark's page for a direct jump.
    let onOpen: (ComicBook, Int?) -> Void

    @Environment(\.modelContext) private var context
    @AppStorage("library.discoveryMode") private var filterRaw = DiscoveryFilter.discover.rawValue

    @State private var centeredID: UUID?
    /// The comic the delete menu is confirming, if any. Drives the confirmation dialog below.
    @State private var bookToDelete: ComicBook?
    /// A focus request that had to switch the filter to Discover first (the comic wasn't in the
    /// current segment). Held until the filter change lands, then centred — see `focus(on:)`.
    @State private var pendingFocusAfterFilterChange: UUID?

    /// Fixed, so swiping between comics with different title lengths can't resize the panel
    /// and make the covers jump.
    private let panelHeight: CGFloat = 132

    private static let deckAnchor = "deck"
    private static let bookmarksAnchor = "bookmarks"
    /// Two columns regardless of the library's zoom setting: this section exists to show the
    /// bookmarked pages BIG, which is the whole reason it's worth a screen of its own.
    private static let bookmarkColumns = Array(repeating: GridItem(.flexible(),
                                                                   spacing: LibraryGridMetrics.spacing),
                                               count: 2)

    private var filter: DiscoveryFilter { .from(filterRaw) }

    private var visibleBooks: [ComicBook] {
        guard showsFilters else { return books }
        let filtered = books.filter { filter.matches($0) }
        // Popular is *about* how often a comic was opened, so it orders itself — most-opened
        // first — instead of following the library's sort menu like the other segments do.
        // Tie-break on dateAdded so equal-count comics keep a stable order across recomputes.
        guard filter == .popular else { return filtered }
        return filtered.sorted { ($0.openCount, $0.dateAdded) > ($1.openCount, $1.dateAdded) }
    }

    /// The comic the pinned panel describes — the same one the deck draws as centred.
    private var centeredBook: ComicBook? { peekCentered(in: visibleBooks, id: centeredID) }

    /// The relationship is a set, not a sequence — for a per-comic section, reading order is
    /// the only order that makes sense.
    private func bookmarks(of book: ComicBook) -> [Bookmark] {
        book.bookmarks.sorted { $0.pageIndex < $1.pageIndex }
    }

    private func sectionBook() -> ComicBook? {
        guard let book = centeredBook, !book.bookmarks.isEmpty else { return nil }
        return book
    }

    /// The deck fills exactly one screen and the centred comic's bookmarks sit on the next.
    /// A comic without bookmarks has content exactly one screen tall, so `.basedOnSize` means
    /// it doesn't scroll or bounce at all — indistinguishable from a plain deck.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // Exactly one container height — which is also `.paging`'s page size, so
                    // the page boundary lands on the section's first pixel by construction
                    // rather than by arithmetic. (This is the canonical paging pattern, and
                    // the reason it survives the tab bar: whatever the container height turns
                    // out to be, both sides read the same number.) The tab bar's room is no
                    // longer reserved by hand — the native TabView insets the scroll content.
                    deck(proxy: proxy)
                        .containerRelativeFrame(.vertical)
                        .id(Self.deckAnchor)

                    if let book = sectionBook() {
                        bookmarkSection(book)
                            .id(Self.bookmarksAnchor)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .confirmationDialog("Delete “\(bookToDelete?.title ?? "")”?",
                                isPresented: Binding(get: { bookToDelete != nil },
                                                     set: { if !$0 { bookToDelete = nil } }),
                                titleVisibility: .visible, presenting: bookToDelete) { book in
                Button("Delete", role: .destructive) { deleteFromCarousel(book) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes the comic and its bookmarks from your library.")
            }
            .task { await backfillCoverAspects() }
            .onAppear {
                // A focus set before this view existed (a cold-launch open) is handled here,
                // since onChange won't fire for a value that arrived with the view.
                if let id = focusID?.wrappedValue {
                    focus(on: id)
                    focusID?.wrappedValue = nil
                } else if centeredID == nil {
                    centeredID = visibleBooks.first?.id
                }
            }
            .onChange(of: focusID?.wrappedValue) { _, id in
                guard let id else { return }
                focus(on: id)
                focusID?.wrappedValue = nil   // one-shot
            }
            .onChange(of: filterRaw) { _, _ in
                // A focus that needed Discover to become visible lands now that the segment has
                // switched; otherwise a plain segment change just re-centres on the first card.
                if let id = pendingFocusAfterFilterChange {
                    pendingFocusAfterFilterChange = nil
                    withAnimation(.snappy(duration: 0.3)) { centeredID = id }
                } else {
                    centeredID = visibleBooks.first?.id
                }
            }
            // The toolbar's shuffle is reachable while the bookmarks are on screen, so bring
            // the deck back up to show the comic it just moved to.
            .onChange(of: randomTrigger) { _, _ in
                withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(Self.deckAnchor, anchor: .top) }
                jumpToRandom()
            }
        }
    }

    // MARK: Deck (filters + carousel + pinned panel)

    private func deck(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 16) {
            if showsFilters { filterPicker }

            if visibleBooks.isEmpty {
                ContentUnavailableView(filter.emptyTitle,
                                       systemImage: filter.emptyIcon,
                                       description: Text(filter.emptyMessage))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PeekDeck(items: visibleBooks, centeredID: $centeredID, art: art,
                         onOpen: { onOpen($0, nil) },
                         transitionNamespace: transitionNamespace)
            }

            // Pinned: it doesn't travel with the cards, only its contents change as you swipe.
            if let book = centeredBook {
                infoPanel(book, proxy: proxy)
                    .frame(height: panelHeight)
                    .padding(.horizontal)
            }
        }
        // The tab bar's safe area puts the panel right up against the glass. Safe to add
        // inside: `containerRelativeFrame` pins the deck's total height, so this squeezes the
        // content rather than growing the deck — the paging boundary doesn't move.
        .padding(.bottom, panelGap)
    }

    /// Breathing room between the info panel and the tab bar below it.
    private var panelGap: CGFloat { 10 }

    // MARK: Filter segments

    private var filterPicker: some View {
        Picker("Show", selection: $filterRaw) {
            ForEach(DiscoveryFilter.allCases) { filter in
                Text(filter.label).tag(filter.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: Deck adapter

    /// How a comic looks in the deck: its cover, and the shape needed to size a card that
    /// doesn't crop it. `coverAspect` is nil only until `backfillCoverAspects` has run over
    /// comics imported before it existed — 2:3 is the usual comic-book cover.
    private func art(_ book: ComicBook) -> PeekArt {
        PeekArt(url: book.coverURL, aspect: book.coverAspect ?? (2.0 / 3.0), label: book.title)
    }

    // MARK: Pinned info panel

    private func infoPanel(_ book: ComicBook, proxy: ScrollViewProxy) -> some View {
        let marks = bookmarks(of: book)

        return VStack(alignment: .leading, spacing: 8) {
            Text(book.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 5) {
                Text(book.format == .zip ? "CBZ" : "CBR")
                Text("·")
                Text(book.pageCountLabel)
                Text("·")
                Text(book.openCountLabel)
                if book.progress > 0 { ProgressPie(progress: book.progress, size: 12) }
                if book.isRead { ReadCheck(size: 12) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            // Read keeps its label; everything that isn't reading or the bookmarks hint goes
            // in the overflow. With four buttons abreast "Read" was truncated down to nothing
            // — and Mark as Read / Remove from Recents are rare enough to earn a tap.
            HStack(spacing: 10) {
                Button { onOpen(book, nil) } label: {
                    Label("Read", systemImage: "book")
                        .frame(maxWidth: .infinity, minHeight: buttonLabelHeight)
                        // The accent is a bright orange-yellow — white on it barely reads.
                        .foregroundStyle(.black)
                }
                .buttonStyle(.borderedProminent)

                // Doubles as the "there's more below" hint: the bookmarks live a page down,
                // where nothing is visible until you scroll, so their existence has to be
                // announced up here. Only shown when there ARE some, which is exactly what
                // makes the section free for everyone else.
                if !marks.isEmpty {
                    Button {
                        withAnimation(.snappy(duration: 0.35)) {
                            proxy.scrollTo(Self.bookmarksAnchor, anchor: .top)
                        }
                    } label: {
                        Label("\(marks.count)", systemImage: "bookmark.fill")
                            .frame(minHeight: buttonLabelHeight)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("\(marks.count) bookmark\(marks.count == 1 ? "" : "s"), show below")
                }

                Menu {
                    Button { toggleRead(book) } label: {
                        Label(book.isRead ? "Mark as Unread" : "Mark as Read",
                              systemImage: book.isRead ? "circle" : "checkmark.circle")
                    }
                    if let onRemoveFromRecents {
                        Button { onRemoveFromRecents(book) } label: {
                            Label("Remove from Recents", systemImage: "clock.badge.xmark")
                        }
                    }
                    Divider()
                    // Same library delete the cover grid offers — with the same confirmation,
                    // since it also drops the archive and bookmarks from disk.
                    Button(role: .destructive) { bookToDelete = book } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: buttonLabelHeight)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("More actions for this comic")
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var buttonLabelHeight: CGFloat { 24 }

    private func toggleRead(_ book: ComicBook) {
        book.isRead.toggle()
        try? context.save()
    }

    /// Brings a comic to the centre of the deck. If the current segment hides it (a brand-new
    /// comic isn't "popular"), switch to Discover — which shows everything — and let the filter's
    /// onChange finish the move, so the two don't fight over `centeredID` in one update.
    private func focus(on id: UUID) {
        if visibleBooks.contains(where: { $0.id == id }) {
            withAnimation(.snappy(duration: 0.3)) { centeredID = id }
        } else {
            pendingFocusAfterFilterChange = id
            filterRaw = DiscoveryFilter.discover.rawValue
        }
    }

    /// Deletes the comic from the library. If it's the centred card, move to a neighbour
    /// first so the deck slides there rather than snapping back to the first card (which is
    /// what `peekCentered`'s fallback would do once the id no longer resolves).
    private func deleteFromCarousel(_ book: ComicBook) {
        if centeredID == book.id {
            let ids = visibleBooks.map(\.id)
            if let i = ids.firstIndex(of: book.id) {
                centeredID = i + 1 < ids.count ? ids[i + 1] : (i > 0 ? ids[i - 1] : nil)
            }
        }
        Importer.delete(book, from: context)
    }

    // MARK: Bookmarks section (one page below the deck)

    private func bookmarkSection(_ book: ComicBook) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // The panel is a screen up by the time this is on show, so the section has to say
            // whose bookmarks these are itself.
            VStack(alignment: .leading, spacing: 2) {
                Text("Bookmarks")
                    .font(.title3.weight(.semibold))
                Text(book.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            LazyVGrid(columns: Self.bookmarkColumns, spacing: LibraryGridMetrics.spacing) {
                ForEach(bookmarks(of: book)) { mark in
                    BookmarkCard(bookmark: mark, showsTitle: false,
                                 maxPixel: LibraryGridMetrics.coverMaxPixel(columns: 2)) {
                        onOpen(book, mark.pageIndex)
                    } onDelete: {
                        delete(mark)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 24)
    }

    private func delete(_ bookmark: Bookmark) {
        try? Storage.fm.removeItem(at: bookmark.thumbURL)
        context.delete(bookmark)
        try? context.save()
    }

    // MARK: Random

    /// Glide to a random comic in the current deck — the Library's shuffle button in this mode
    /// moves the carousel rather than opening something. Excludes the current one so it always
    /// visibly goes somewhere.
    private func jumpToRandom() {
        let others = visibleBooks.filter { $0.id != centeredID }
        guard let pick = others.randomElement() ?? visibleBooks.first else { return }
        withAnimation(.snappy(duration: 0.45)) { centeredID = pick.id }
    }

    // MARK: Backfill

    /// Comics imported before `coverAspect` existed have none, and the cards need it to size
    /// without cropping. Probe the JPEG headers off-main (no bitmap decode), then apply in one
    /// batch with a SINGLE save — a per-book save would republish the @Query N times.
    private func backfillCoverAspects() async {
        let pending: [(UUID, URL)] = books
            .filter { $0.coverAspect == nil }
            .compactMap { book in book.coverURL.map { (book.id, $0) } }
        guard !pending.isEmpty else { return }

        let probed: [UUID: Double] = await Task.detached(priority: .utility) {
            var found: [UUID: Double] = [:]
            for (id, url) in pending {
                if let aspect = ImageDownsampler.pixelAspect(ofImageAt: url) { found[id] = aspect }
            }
            return found
        }.value
        guard !probed.isEmpty else { return }

        for book in books where book.coverAspect == nil {
            if let aspect = probed[book.id] { book.coverAspect = aspect }
        }
        try? context.save()
    }
}
