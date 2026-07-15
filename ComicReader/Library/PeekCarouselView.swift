//
//  PeekCarouselView.swift
//  Comic Reader
//
//  The cover carousel: one large, uncropped cover centred with its neighbours peeking in
//  either side, swiped left/right, with the centred comic's details pinned below. Used by the
//  Library's "Discover" mode (which adds the filter segments) and by Recents.
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
    let onOpen: (ComicBook) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("library.discoveryMode") private var filterRaw = DiscoveryFilter.discover.rawValue

    @State private var centeredID: UUID?

    /// How much of each neighbour stays visible either side — this is what makes it a peek
    /// carousel, and it (not a height percentage) is what bounds the cover's size.
    private let peekInset: CGFloat = 52
    private let slotSpacing: CGFloat = 14
    /// Room around the cover so its shadow isn't clipped by the ScrollView's bounds.
    private let shadowPad: CGFloat = 28
    /// Fixed, so swiping between comics with different title lengths can't resize the panel
    /// and make the covers jump.
    private let panelHeight: CGFloat = 132

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

    var body: some View {
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
                infoPanel(book)
                    .frame(height: panelHeight)
                    .padding(.horizontal)
            }
        }
        .padding(.bottom, FloatingTabBar.reservedSpace)
        .task { await backfillCoverAspects() }
        .onAppear { if centeredID == nil { centeredID = visibleBooks.first?.id } }
        .onChange(of: filterRaw) { _, _ in centeredID = visibleBooks.first?.id }
        .onChange(of: randomTrigger) { _, _ in jumpToRandom() }
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
                        .zIndex(book.id == centeredID ? 1 : 0)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        // Without this the first and last card could never reach the centre.
        .safeAreaPadding(.horizontal, max(0, (size.width - slotW) / 2))
        .scrollPosition(id: $centeredID, anchor: .center)
        .sensoryFeedback(.selection, trigger: centeredID)
    }

    // MARK: Card

    private func card(_ book: ComicBook, slotW: CGFloat, boxH: CGFloat) -> some View {
        // Width-driven: the cover fills its slot, and only a very tall cover gets capped by the
        // height left once the shadow has room. Either way it is never cropped.
        let aspect = book.coverAspect ?? (2.0 / 3.0)
        let coverH = min(max(80, boxH - shadowPad * 2), slotW / aspect)
        let coverW = coverH * aspect
        let isCentered = book.id == centeredID

        return cover(book, width: coverW, height: coverH)
            .frame(width: slotW, height: boxH)
            .contentShape(Rectangle())
            .onTapGesture {
                if isCentered {
                    onOpen(book)      // its details are already on screen — a tap just reads it
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

    private func infoPanel(_ book: ComicBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Button { onOpen(book) } label: {
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
