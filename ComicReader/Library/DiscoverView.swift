//
//  DiscoverView.swift
//  Comic Reader
//
//  The Library's "Discover" layout: one large, uncropped cover centred with its neighbours
//  peeking in from either side, swiped left/right. Three orderings — a shuffle, most-opened
//  ("Popular") and least-opened ("Gathering Dust") — all driven by ComicBook.openCount.
//  Tapping the centred cover slides an info panel out beneath it.
//

import SwiftUI
import SwiftData

/// Which comics the carousel shows, and in what order. Raw string in @AppStorage, like
/// `LibrarySort` / `LibraryViewMode`.
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

struct DiscoverView: View {
    let books: [ComicBook]
    let onOpen: (ComicBook) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("library.discoveryMode") private var modeRaw = DiscoveryMode.discover.rawValue

    /// The carousel's order, as a snapshot of ids — deliberately NOT a computed property over
    /// `books`: every `context.save()` anywhere republishes the @Query, which would reshuffle
    /// the deck mid-swipe. Ids (not references) so a deleted book can't dangle.
    @State private var order: [UUID] = []
    @State private var centeredID: UUID?
    @State private var expanded = false

    private var mode: DiscoveryMode { .from(modeRaw) }

    /// How much of each neighbour stays visible either side — this is what makes it a peek
    /// carousel, and it (not a height percentage) is what bounds the cover's size.
    private let peekInset: CGFloat = 52
    private let slotSpacing: CGFloat = 14
    /// Must be a constant — `.frame(height: nil)` doesn't animate.
    private let panelHeight: CGFloat = 128

    private var orderedBooks: [ComicBook] {
        let byID = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return order.compactMap { byID[$0] }
    }

    /// "Popular" on a library nobody has opened yet would silently degrade to date-added order
    /// and claim a popularity that doesn't exist.
    private var popularIsEmpty: Bool {
        mode == .popular && books.allSatisfy { $0.openCount == 0 }
    }

    var body: some View {
        VStack(spacing: 12) {
            modePicker
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
        // the available height. Either way it is never cropped.
        let aspect = book.coverAspect ?? (2.0 / 3.0)
        let coverH = min(boxH, slotW / aspect)
        let coverW = coverH * aspect
        let isCentered = book.id == centeredID
        let showPanel = expanded && isCentered
        // Shrink the cover by exactly the drawer's height — derived, so cover + panel fill the
        // box at any aspect instead of overflowing.
        let shrink = coverH > 0 ? min(1, max(0.4, (boxH - panelHeight - 10) / coverH)) : 1

        return ZStack(alignment: .top) {
            if showPanel {
                infoPanel(book)
                    .frame(width: slotW, height: panelHeight)
                    .offset(y: coverH * shrink + 10)
                    .transition(.opacity)
            }
            cover(book, width: coverW, height: coverH)
                // A pure GPU transform — no relayout, no re-decode.
                .scaleEffect(showPanel ? shrink : 1, anchor: .top)
        }
        .frame(width: slotW, height: boxH, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.28)) {
                if isCentered {
                    expanded.toggle()
                } else {
                    // Tapping a neighbour brings it to the middle.
                    centeredID = book.id
                    expanded = false
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(book.title)
    }

    private func cover(_ book: ComicBook, width: CGFloat, height: CGFloat) -> some View {
        DiskImage(url: book.coverURL, contentMode: .fit,
                  maxPixel: ImageDownsampler.libraryCardPixel)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.1)))
            .overlay(alignment: .bottom) { grabber }
            .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    /// The affordance for the info panel. Tapping anywhere on the centred card works — this
    /// just advertises it. Deliberately not a drag: a vertical DragGesture on a child of a
    /// horizontal ScrollView competes for the gesture and can kill the swipe.
    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(0.9))
            .frame(width: 36, height: 5)
            .shadow(color: .black.opacity(0.5), radius: 3)
            .padding(.bottom, 10)
            .accessibilityHidden(true)
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

            HStack(spacing: 10) {
                Button { onOpen(book) } label: {
                    Label("Read", systemImage: "book").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { toggleRead(book) } label: {
                    Image(systemName: book.isRead ? "circle" : "checkmark.circle")
                        .frame(width: 44, height: 30)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(book.isRead ? "Mark as unread" : "Mark as read")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func toggleRead(_ book: ComicBook) {
        book.isRead.toggle()
        try? context.save()
    }

    // MARK: Order

    private func reseed() {
        order = ordered(books).map(\.id)
        centeredID = order.first     // otherwise there's no subject until the first scroll
        expanded = false
    }

    /// Keep the existing order and just fold the change in — an import landing while Discover
    /// is open must not reshuffle the deck under the user.
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
