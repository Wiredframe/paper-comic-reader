//
//  BookmarkCarouselView.swift
//  Comic Reader
//
//  The Bookmarks tab's carousel: the same peek deck the Library uses, dealt bookmarked pages
//  instead of covers, with the centred bookmark's details pinned below. Unlike the Library's
//  carousel there is nothing a page further down — a bookmark has no sub-items — so this is a
//  plain deck with no vertical scrolling.
//

import SwiftUI
import SwiftData

struct BookmarkCarouselView: View {
    /// Already in the order they should appear — the caller applies the sort menu.
    let bookmarks: [Bookmark]
    /// Bumped by the shuffle button to glide to a random bookmark in the deck.
    var randomTrigger: Int = 0
    /// Jump into the comic at the bookmarked page.
    let onOpenBookmark: (Bookmark) -> Void
    /// Open the comic the bookmark belongs to, where reading left off.
    let onOpenComic: (ComicBook) -> Void

    @Environment(\.modelContext) private var context

    @State private var centeredID: UUID?

    /// Fixed, so swiping between bookmarks with different comic-title lengths can't resize the
    /// panel and make the pages jump.
    private let panelHeight: CGFloat = 132

    /// The bookmark the pinned panel describes — the same one the deck draws as centred.
    private var centered: Bookmark? { peekCentered(in: bookmarks, id: centeredID) }

    var body: some View {
        VStack(spacing: 16) {
            PeekDeck(items: bookmarks, centeredID: $centeredID, art: art, onOpen: onOpenBookmark)

            if let mark = centered {
                infoPanel(mark)
                    .frame(height: panelHeight)
                    .padding(.horizontal)
            }
        }
        .padding(.bottom, FloatingTabBar.reservedSpace)
        .task { await backfillPageAspects() }
        .onAppear { if centeredID == nil { centeredID = bookmarks.first?.id } }
        .onChange(of: randomTrigger) { _, _ in jumpToRandom() }
    }

    // MARK: Deck adapter

    /// How a bookmark looks in the deck: the page shot, and the shape needed to size a card
    /// that doesn't crop it. Only bookmarks made before `pageAspect` existed lack one, and only
    /// until the backfill lands.
    private func art(_ mark: Bookmark) -> PeekArt {
        PeekArt(url: mark.thumbURL,
                aspect: mark.pageAspect ?? (2.0 / 3.0),
                label: "\(mark.book?.title ?? "Bookmark"), \(mark.pageLabel)")
    }

    // MARK: Pinned info panel

    private func infoPanel(_ mark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mark.book?.title ?? "—")
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 5) {
                Text(mark.pageLabel)
                if let book = mark.book {
                    Text("of \(book.pageCount)")
                }
                Text("·")
                Text("Added \(mark.dateAdded.formatted(date: .abbreviated, time: .omitted))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            // Two ways in, because a bookmark is a place in a comic and sometimes you want the
            // place and sometimes the comic: Read lands on the bookmarked page, Comic opens it
            // wherever reading left off.
            HStack(spacing: 10) {
                Button { onOpenBookmark(mark) } label: {
                    Label("Read", systemImage: "bookmark.fill")
                        .frame(maxWidth: .infinity, minHeight: buttonLabelHeight)
                }
                .buttonStyle(.borderedProminent)

                if let book = mark.book {
                    Button { onOpenComic(book) } label: {
                        Label("Comic", systemImage: "book")
                            .frame(maxWidth: .infinity, minHeight: buttonLabelHeight)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var buttonLabelHeight: CGFloat { 24 }

    // MARK: Random

    /// Glide to a random bookmark — the shuffle button in this mode moves the deck rather than
    /// yanking the reader open. Excludes the current one so it always visibly goes somewhere.
    private func jumpToRandom() {
        let others = bookmarks.filter { $0.id != centeredID }
        guard let pick = others.randomElement() ?? bookmarks.first else { return }
        withAnimation(.snappy(duration: 0.45)) { centeredID = pick.id }
    }

    // MARK: Backfill

    /// Bookmarks made before `pageAspect` existed have none, and the cards need it to size
    /// without cropping. Probe the JPEG headers off-main (no bitmap decode), then apply in one
    /// batch with a SINGLE save — a per-bookmark save would republish the @Query N times.
    private func backfillPageAspects() async {
        let pending: [(UUID, URL)] = bookmarks
            .filter { $0.pageAspect == nil }
            .map { ($0.id, $0.thumbURL) }
        guard !pending.isEmpty else { return }

        let probed: [UUID: Double] = await Task.detached(priority: .utility) {
            var found: [UUID: Double] = [:]
            for (id, url) in pending {
                if let aspect = ImageDownsampler.pixelAspect(ofImageAt: url) { found[id] = aspect }
            }
            return found
        }.value
        guard !probed.isEmpty else { return }

        for mark in bookmarks where mark.pageAspect == nil {
            if let aspect = probed[mark.id] { mark.pageAspect = aspect }
        }
        try? context.save()
    }
}
