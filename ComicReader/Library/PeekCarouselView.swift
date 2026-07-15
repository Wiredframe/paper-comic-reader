//
//  PeekCarouselView.swift
//  Comic Reader
//
//  The cover carousel: one large, uncropped cover centred with its neighbours peeking in
//  either side, swiped left/right, with the comic's details permanently below it. Used by
//  the Library's "Discover" mode (which adds the mode switcher and its own orderings) and by
//  Recents (which supplies its own most-recent-first order).
//

import SwiftUI
import SwiftData

/// Which comics the Library's Discover mode shows, and in what order. Raw string in
/// @AppStorage, like `LibrarySort` / `LibraryViewMode`.
enum DiscoveryMode: String, CaseIterable, Identifiable {
    case discover, popular, dust

    var id: String { rawValue }

    var label: String {
        switch self {
        case .discover: return "Discover"
        case .popular:  return "Popular"
        case .dust:     return "Gathering Dust"
        }
    }

    static func from(_ raw: String) -> DiscoveryMode { DiscoveryMode(rawValue: raw) ?? .discover }
}

struct PeekCarouselView: View {
    let books: [ComicBook]
    /// Library shows the Discover/Popular/Gathering Dust switcher and re-orders itself.
    /// Recents passes false and keeps the order it was handed (most recently opened first).
    var showsModes: Bool = true
    /// Only Recents supplies this — it puts a "forget this one" button in the panel, which
    /// the cover grid used to offer via its context menu.
    var onRemoveFromRecents: ((ComicBook) -> Void)? = nil
    let onOpen: (ComicBook) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("library.discoveryMode") private var modeRaw = DiscoveryMode.discover.rawValue

    /// The carousel's order, as a snapshot of ids — deliberately NOT a computed property over
    /// `books`: every `context.save()` anywhere republishes the @Query, which would reshuffle
    /// the deck mid-swipe. Ids (not references) so a deleted book can't dangle.
    @State private var order: [UUID] = []
    @State private var centeredID: UUID?

    private var mode: DiscoveryMode { .from(modeRaw) }

    /// How much of each neighbour stays visible either side — this is what makes it a peek
    /// carousel, and it (not a height percentage) is what bounds the cover's size.
    private let peekInset: CGFloat = 52
    private let slotSpacing: CGFloat = 14
    /// Room above the cover so its shadow isn't clipped by the ScrollView's bounds.
    private let shadowPad: CGFloat = 28
    private let coverToPanel: CGFloat = 16
    private let panelHeight: CGFloat = 132

    private var orderedBooks: [ComicBook] {
        let byID = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { byID[$0] }
    }

    /// "Popular" on a library nobody has opened yet would silently degrade to date-added order
    /// and claim a popularity that doesn't exist.
    private var popularIsEmpty: Bool {
        showsModes && mode == .popular && books.allSatisfy { $0.openCount == 0 }
    }

    var body: some View {
        VStack(spacing: 20) {
            if showsModes { modePicker }
            GeometryReader { geo in
                if popularIsEmpty {
                    ContentUnavailableView("Nothing's popular yet",
                                           systemImage: "flame",
                                           description: Text("Comics you open often show up here."))
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    carousel(in: geo.size)
                }
            }
        }
        .padding(.bottom, FloatingTabBar.reservedSpace)
        .task { await backfillCoverAspects() }
        .onAppear { if order.isEmpty { reseed() } }
        .onChange(of: modeRaw) { _, _ in reseed() }
        .onChange(of: books.map(\.id)) { _, _ in reconcile() }
    }

    // MARK: Mode switcher

    private var modePicker: some View {
        Picker("Discovery mode", selection: $modeRaw) {
            ForEach(DiscoveryMode.allCases) { mode in
                Text(mode.label).tag(mode.rawValue)
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
                ForEach(orderedBooks) { book in
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
        // Width-driven: the cover fills its slot, and only a very tall cover gets capped by
        // what's left once the panel and the shadow's breathing room are taken out. Either
        // way it is never cropped.
        let aspect = book.coverAspect ?? (2.0 / 3.0)
        // Exactly what's left once the shadow's top room, the gap and the panel are taken out
        // — so a typical cover stays width-driven (filling its slot) rather than being
        // needlessly capped by height.
        let maxCoverH = max(80, boxH - shadowPad - coverToPanel - panelHeight)
        let coverH = min(maxCoverH, slotW / aspect)
        let coverW = coverH * aspect
        let isCentered = book.id == centeredID

        return VStack(spacing: coverToPanel) {
            cover(book, width: coverW, height: coverH)
            infoPanel(book)
                .frame(width: slotW, height: panelHeight)
        }
        .padding(.top, shadowPad)
        .frame(width: slotW, height: boxH, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCentered {
                onOpen(book)          // the details are already on screen — a tap just reads it
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

    // MARK: Info panel

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

    // MARK: Order

    private func reseed() {
        order = ordered(books).map(\.id)
        centeredID = order.first     // otherwise there's no subject until the first scroll
    }

    /// Keep the existing order and just fold the change in — an import landing (or a comic
    /// being read, which re-sorts Recents) must not reshuffle the deck under the user.
    private func reconcile() {
        let live = Set(books.map(\.id))
        var next = order.filter { live.contains($0) }
        let known = Set(next)
        next.append(contentsOf: ordered(books).map(\.id).filter { !known.contains($0) })
        order = next
        if let id = centeredID, live.contains(id) { return }
        centeredID = order.first
    }

    private func ordered(_ books: [ComicBook]) -> [ComicBook] {
        // Recents hands us its own order (most recently opened first) — don't second-guess it.
        guard showsModes else { return books }
        switch mode {
        case .discover:
            return books.shuffled()
        case .popular:
            return books.sorted { ($0.openCount, $0.dateAdded) > ($1.openCount, $1.dateAdded) }
        case .dust:
            // Least-opened first; among equals the one untouched longest (never opened =
            // .distantPast) is the dustiest. Keyed on openCount, NOT dateOpened alone, because
            // Recents' "Clear" nils every dateOpened and would make the whole library look dusty.
            return books.sorted {
                ($0.openCount, $0.dateOpened ?? .distantPast, $0.dateAdded)
                    < ($1.openCount, $1.dateOpened ?? .distantPast, $1.dateAdded)
            }
        }
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
