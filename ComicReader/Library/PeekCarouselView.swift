//
//  PeekCarouselView.swift
//  Comic Reader
//
//  The cover carousel: one large, uncropped cover centred with its neighbours peeking in
//  either side, swiped left/right, with the centred comic's details pinned below. Used by the
//  Library's "Discover" mode (which adds the filter segments and the bookmarks section) and by
//  Recents (deliberately reduced to just the deck).
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
    /// Library puts the centred comic's bookmarks one page below the fold. Recents deliberately
    /// stays reduced: it's the "get me back into what I was reading" screen, so it renders the
    /// bare deck with no vertical scrolling at all.
    var showsBookmarks: Bool = true
    /// Bumped by the Library's shuffle button to glide to a random comic in the current deck.
    var randomTrigger: Int = 0
    /// Only Recents supplies this — it puts a "forget this one" button in the panel, which the
    /// cover grid used to offer via its context menu.
    var onRemoveFromRecents: ((ComicBook) -> Void)? = nil
    /// The page is nil for "open where you left off", or a bookmark's page for a direct jump.
    let onOpen: (ComicBook, Int?) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("library.discoveryMode") private var filterRaw = DiscoveryFilter.discover.rawValue

    @State private var centeredID: UUID?
    /// Bumped when something off-deck changes the centred comic (the toolbar's shuffle is
    /// reachable while the bookmarks are on screen), so the view can scroll back up to show it.
    @State private var scrollTopTick = 0

    /// How much of each neighbour stays visible either side — this is what makes it a peek
    /// carousel, and it (not a height percentage) is what bounds the cover's size.
    private let peekInset: CGFloat = 52
    private let slotSpacing: CGFloat = 14
    // Room for the cover's shadow, which the ScrollView would otherwise clip. A Gaussian blur
    // spreads roughly 1.5x its radius, so `.shadow(radius: 18, y: 8)` actually reaches about
    // 27 + 8 = 35pt below the cover and 27 - 8 = 19pt above — not the 26/10 the radius alone
    // suggests. Asymmetric on purpose: reserving the same both sides wasted room up top and
    // still clipped the tail against the panel.
    private let shadowTop: CGFloat = 20
    private let shadowBottom: CGFloat = 40
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
        return books.filter { filter.matches($0) }
    }

    /// The comic the pinned panel describes. Falls back to the first so the panel has a
    /// subject before the first scroll settles.
    private var centeredBook: ComicBook? {
        if let id = centeredID, let match = visibleBooks.first(where: { $0.id == id }) { return match }
        return visibleBooks.first
    }

    /// The relationship is a set, not a sequence — for a per-comic section, reading order is
    /// the only order that makes sense.
    private func bookmarks(of book: ComicBook) -> [Bookmark] {
        book.bookmarks.sorted { $0.pageIndex < $1.pageIndex }
    }

    private func sectionBook() -> ComicBook? {
        guard showsBookmarks, let book = centeredBook, !book.bookmarks.isEmpty else { return nil }
        return book
    }

    var body: some View {
        Group {
            if showsBookmarks {
                scrollingBody
            } else {
                // Recents: the deck and nothing else, exactly as it was before the bookmarks
                // section existed — no vertical scroll view to compete with the carousel.
                deck(proxy: nil)
            }
        }
        .task { await backfillCoverAspects() }
        .onAppear { if centeredID == nil { centeredID = visibleBooks.first?.id } }
        .onChange(of: filterRaw) { _, _ in centeredID = visibleBooks.first?.id }
        .onChange(of: randomTrigger) { _, _ in
            scrollTopTick += 1
            jumpToRandom()
        }
    }

    /// Library: the deck fills exactly one screen, the centred comic's bookmarks sit on the
    /// next one. A comic without bookmarks has content exactly one screen tall, so
    /// `.basedOnSize` means it doesn't scroll or bounce at all — indistinguishable from the
    /// deck-only layout.
    private var scrollingBody: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // One full container height, with the tab-bar room kept INSIDE the deck
                    // (as the padding it always was). That keeps the resting layout identical
                    // to the deck-only version, and makes the page boundary land exactly on
                    // the section's first pixel — a deck sized `height - reservedSpace` would
                    // put paging out of step by those 74pt and clip the section header.
                    deck(proxy: proxy)
                        .containerRelativeFrame(.vertical)
                        .id(Self.deckAnchor)

                    if let book = sectionBook() {
                        bookmarkSection(book)
                            .id(Self.bookmarksAnchor)
                            .padding(.bottom, FloatingTabBar.reservedSpace)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .onChange(of: scrollTopTick) { _, _ in
                withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(Self.deckAnchor, anchor: .top) }
            }
        }
    }

    // MARK: Deck (filters + carousel + pinned panel)

    private func deck(proxy: ScrollViewProxy?) -> some View {
        VStack(spacing: 16) {
            if showsFilters { filterPicker }

            GeometryReader { geo in
                if visibleBooks.isEmpty {
                    ContentUnavailableView(filter.emptyTitle,
                                           systemImage: filter.emptyIcon,
                                           description: Text(filter.emptyMessage))
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    carousel(in: geo.size)
                }
            }

            // Pinned: it doesn't travel with the cards, only its contents change as you swipe.
            if let book = centeredBook {
                infoPanel(book, proxy: proxy)
                    .frame(height: panelHeight)
                    .padding(.horizontal)
            }
        }
        .padding(.bottom, FloatingTabBar.reservedSpace)
    }

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

    // MARK: Carousel

    private func carousel(in size: CGSize) -> some View {
        // The slot is what the peek leaves over; the cover then fills it (unless it's so tall
        // that the height caps it first — see `card`).
        let slotW = max(120, size.width - 2 * peekInset)
        // Read once here: `.scrollTransition`'s closure is @Sendable and can't touch
        // main-actor state like the environment.
        let animate = !reduceMotion

        return ScrollView(.horizontal) {
            LazyHStack(spacing: slotSpacing) {
                ForEach(visibleBooks) { book in
                    card(book, slotW: slotW, boxH: size.height)
                        .frame(width: slotW)
                        // Visual only — the layout keeps a clean, even stride, so viewAligned
                        // still snaps each card dead centre while they visually overlap.
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(animate ? 1 - 0.14 * abs(phase.value) : 1)
                                .offset(x: animate ? -phase.value * 26 : 0)   // pull neighbours inward
                                .opacity(animate ? 1 - 0.3 * abs(phase.value) : 1)
                        }
                        .zIndex(centeredBook?.id == book.id ? 1 : 0)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        // These margins are what let the first and last card reach the middle — and together
        // with viewAligned they ARE the centring. Note there is deliberately no
        // `anchor: .center` on scrollPosition below: that would centre a second time, pushing
        // every card one full inset to the right.
        .contentMargins(.horizontal, max(0, (size.width - slotW) / 2), for: .scrollContent)
        .scrollPosition(id: $centeredID)
        .sensoryFeedback(.selection, trigger: centeredID)
    }

    // MARK: Card

    private func card(_ book: ComicBook, slotW: CGFloat, boxH: CGFloat) -> some View {
        // Width-driven: the cover fills its slot, and only a very tall cover gets capped by the
        // height left once the shadow has room. Either way it is never cropped.
        let aspect = book.coverAspect ?? (2.0 / 3.0)
        let coverH = min(max(80, boxH - shadowTop - shadowBottom), slotW / aspect)
        let coverW = coverH * aspect
        // Fall back to `centeredBook` so the first card counts as centred before any scroll
        // has reported an id — otherwise its first tap would try to centre it instead of
        // opening it.
        let isCentered = centeredBook?.id == book.id

        // Spacers with different minimums: the cover still sits about centred when there's
        // room to spare, but can never come closer to either edge than its shadow needs.
        return VStack(spacing: 0) {
            Spacer(minLength: shadowTop)
            cover(book, width: coverW, height: coverH)
            Spacer(minLength: shadowBottom)
        }
            .frame(width: slotW, height: boxH)
            .contentShape(Rectangle())
            .onTapGesture {
                if isCentered {
                    onOpen(book, nil)   // its details are already on screen — a tap just reads it
                } else {
                    withAnimation(.snappy(duration: 0.28)) { centeredID = book.id }
                }
            }
    }

    private func cover(_ book: ComicBook, width: CGFloat, height: CGFloat) -> some View {
        DiskImage(url: book.coverURL, contentMode: .fit,
                  maxPixel: ImageDownsampler.libraryCardPixel)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
            .accessibilityLabel(book.title)
    }

    // MARK: Pinned info panel

    private func infoPanel(_ book: ComicBook, proxy: ScrollViewProxy?) -> some View {
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

            // One control size for the row, and a shared label height, so every button is
            // exactly as tall as its neighbour.
            HStack(spacing: 10) {
                Button { onOpen(book, nil) } label: {
                    Label("Read", systemImage: "book")
                        .frame(maxWidth: .infinity, minHeight: buttonLabelHeight)
                }
                .buttonStyle(.borderedProminent)

                Button { toggleRead(book) } label: {
                    Image(systemName: book.isRead ? "circle" : "checkmark.circle")
                        .frame(width: 28, height: buttonLabelHeight)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(book.isRead ? "Mark as unread" : "Mark as read")

                // Doubles as the "there's more below" hint: the bookmarks live a page down,
                // where nothing is visible until you scroll, so their existence has to be
                // announced up here. Only shown when there ARE some, which is exactly what
                // makes the section free for everyone else.
                if showsBookmarks, !marks.isEmpty, let proxy {
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

                if let onRemoveFromRecents {
                    Button { onRemoveFromRecents(book) } label: {
                        Image(systemName: "clock.badge.xmark")
                            .frame(width: 28, height: buttonLabelHeight)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Remove from Recents")
                }
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
