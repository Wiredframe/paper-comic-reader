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
    /// Pair with `.navigationTransition(.zoom(sourceID: bookmark.id, in:))` on the reader the
    /// caller presents: the page card grows into the reader, and the presentation gains the
    /// system's interactive drag-down dismiss.
    var transitionNamespace: Namespace.ID? = nil
    /// Jump into the comic at the bookmarked page.
    let onOpenBookmark: (Bookmark) -> Void
    /// Open the comic itself, from the first page.
    let onOpenComic: (ComicBook) -> Void
    /// Asks the screen to present the story picker — it owns the sheet, this deck only centres the
    /// card. Optional, like the Library deck's `onRemoveFromRecents`: no handler, no menu item.
    var onAssignStory: ((Bookmark) -> Void)? = nil
    /// Removes the bookmark from the library. Routed up rather than done here so the delete and its
    /// thumbnail cleanup stay in one place (BookmarksView.delete), the way the list and the grid
    /// already do it.
    let onDelete: (Bookmark) -> Void

    @Environment(\.modelContext) private var context

    @State private var centeredID: UUID?

    /// Fixed, so swiping between bookmarks with different comic-title lengths can't resize the
    /// panel and make the pages jump. The story line is reserved whether or not a bookmark has one,
    /// for the same reason the height is fixed at all. Matches the Library deck's panel, so the two
    /// decks sit at the same height.
    private let panelHeight: CGFloat = 150

    /// The bookmark the pinned panel describes — the same one the deck draws as centred.
    private var centered: Bookmark? { peekCentered(in: bookmarks, id: centeredID) }

    var body: some View {
        VStack(spacing: 16) {
            PeekDeck(items: bookmarks, centeredID: $centeredID, art: art,
                     onOpen: onOpenBookmark, transitionNamespace: transitionNamespace)

            if let mark = centered {
                infoPanel(mark)
                    .frame(height: panelHeight)
                    .padding(.horizontal)
            }
        }
        // Breathing room between the panel and the tab bar's glass below it.
        .padding(.bottom, 10)
        .task { await backfillPageAspects() }
        .onAppear { if centeredID == nil { centeredID = bookmarks.first?.id } }
        .onChange(of: randomTrigger) { _, _ in jumpToRandom() }
    }

    // MARK: Deck adapter

    /// How a bookmark looks in the deck: the page shot, and the shape needed to size a card
    /// that doesn't crop it. Only bookmarks made before `pageAspect` existed lack one, and only
    /// until the backfill lands.
    private func art(_ mark: Bookmark) -> PeekArt {
        // The story leads when there is one, matching the panel below: it's the most specific thing
        // anyone can say about a bookmarked page, and the deck has no caption for VoiceOver to fall
        // back on.
        let comic = mark.book?.displayTitle ?? "Bookmark"
        let named = mark.storyLabel.map { "\($0), \(comic)" } ?? comic
        return PeekArt(url: mark.thumbURL, aspect: mark.pageAspect ?? (2.0 / 3.0),
                       label: "\(named), \(mark.pageLabel)")
    }

    // MARK: Pinned info panel

    private func infoPanel(_ mark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // The story leads once one is assigned, and the comic drops underneath it — same
                // ordering as the bookmark cards, so a bookmark is called the same thing wherever
                // you meet it. One line each: a story title can be long, and the panel's height is
                // fixed so the deck's pages don't jump.
                Text(mark.storyLabel ?? mark.book?.displayTitle ?? "—")
                    .font(.headline)
                    .lineLimit(1)
                // Rendered even when there's no story, so swiping from an assigned bookmark to an
                // unassigned one doesn't shift the rows below it.
                Text(mark.hasStory ? (mark.book?.displayTitle ?? "—") : " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
                        // The accent is a bright orange-yellow — white on it barely reads.
                        .foregroundStyle(.black)
                }
                .buttonStyle(.borderedProminent)

                // Only Read stretches. The Library's panel hit exactly this and recorded the fix:
                // "With four buttons abreast 'Read' was truncated down to nothing" — so everything
                // beside it keeps a fixed width instead of sharing the row equally.
                if let book = mark.book {
                    Button { onOpenComic(book) } label: {
                        Label("Comic", systemImage: "book")
                            .labelStyle(.iconOnly)
                            .frame(width: 28, height: buttonLabelHeight)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Open this comic")
                }

                Menu {
                    if let onAssignStory, let book = mark.book, !book.stories.isEmpty {
                        Button { onAssignStory(mark) } label: {
                            Label(mark.hasStory ? "Change Story…" : "Assign to Story…",
                                  systemImage: "text.book.closed")
                        }
                    }
                    if mark.hasStory {
                        Button { clearStory(mark) } label: {
                            Label("Remove from Story", systemImage: "minus.circle")
                        }
                    }
                    Divider()
                    // The deck had no delete at all — the grid and the list have carried one from
                    // the start, so a bookmark you could only reach by swiping was the one you
                    // couldn't remove. Unconfirmed, like those two: it drops one page shot, not a
                    // comic and every bookmark in it (which is why the Library deck's delete does ask).
                    Button(role: .destructive) { removeBookmark(mark) } label: {
                        Label("Remove Bookmark", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: buttonLabelHeight)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("More actions for this bookmark")
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var buttonLabelHeight: CGFloat { 24 }

    // MARK: Panel actions

    /// Removes the bookmark. If it's the centred card, move to a neighbour FIRST so the deck slides
    /// there rather than snapping back to the first card once the id stops resolving — the same
    /// reason `PeekCarouselView.deleteFromCarousel` does it.
    private func removeBookmark(_ mark: Bookmark) {
        if centeredID == mark.id {
            let ids = bookmarks.map(\.id)
            if let i = ids.firstIndex(of: mark.id) {
                centeredID = i + 1 < ids.count ? ids[i + 1] : (i > 0 ? ids[i - 1] : nil)
            }
        }
        onDelete(mark)
    }

    private func clearStory(_ mark: Bookmark) {
        mark.clearStory()
        try? context.save()
    }

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
