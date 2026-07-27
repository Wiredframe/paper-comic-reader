//
//  BookmarkCard.swift
//  Comic Reader
//
//  One bookmarked page as a card: the page screenshot with a compact caption. Shared by the
//  Bookmarks tab (every comic, mixed) and the Library carousel's per-comic section.
//

import SwiftUI

struct BookmarkCard: View {
    let bookmark: Bookmark
    /// The Bookmarks tab mixes every comic together, so each card has to name its own. A
    /// per-comic section already says which comic it is — there the title is just noise.
    var showsTitle: Bool = true
    var maxPixel: CGFloat? = nil
    /// Keep a line free for the story title even when this bookmark has none. Set by a caller whose
    /// grid holds at least one bookmark WITH a story: a card that grew only for the assigned ones
    /// would leave its row taller than its neighbours and the pages would drift apart — the same
    /// reason CoverCell always reserves its subtitle line. Off by default, so a library where no
    /// story has been assigned keeps the compact card.
    var reservesStoryLine: Bool = false
    let onOpen: () -> Void
    let onDelete: () -> Void
    /// Asks the caller to present the story picker for this bookmark. Optional because the SCREEN
    /// owns that sheet (one per screen, not one per card) — a caller that doesn't present it leaves
    /// the menu item out entirely. Same shape as PeekCarouselView's `onRemoveFromRecents`.
    var onAssignStory: (() -> Void)? = nil

    @Environment(\.modelContext) private var context

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 7) {
                DiskImage(url: bookmark.thumbURL, contentMode: .fill, maxPixel: maxPixel)
                    .aspectRatio(LibraryGridMetrics.coverAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.1)))
                    // Path-based shadow behind the opaque thumbnail — same reasoning as CoverCell:
                    // avoids the per-cell offscreen alpha pass that made the bookmarks grid scroll
                    // heavier than it needed to. Visually identical.
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                            .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
                    )

                VStack(spacing: 2) {
                    // The story leads once one is assigned, and the comic drops to the line under
                    // it: a bookmark that names its story is FOR that story, and the issue it sits
                    // in is then context rather than identity. Both are capped at one line — a
                    // story title can be long, and a card that grew for it would break the grid.
                    if showsTitle || bookmark.hasStory || reservesStoryLine {
                        Text(leadLabel)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    if showsTitle, bookmark.hasStory || reservesStoryLine {
                        Text(bookmark.hasStory ? (bookmark.book?.displayTitle ?? "—") : " ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    // `pageLabel`, not a second copy of the same string: the model already names a
                    // page for the row and the panel, and this card had drifted into spelling it out.
                    Text(bookmark.pageLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
    }

    /// What the card is called: its story, else the comic (where this grid names comics at all).
    /// A blank when there's neither but a neighbouring card has a story — the line is held open so
    /// the rows of the grid stay even, the same trick `CoverCell` uses for its subtitle.
    private var leadLabel: String {
        if let story = bookmark.storyLabel { return story }
        return showsTitle ? (bookmark.book?.displayTitle ?? "—") : " "
    }

    @ViewBuilder private var menu: some View {
        // Hidden, not disabled, when the comic carries no story index: there is nothing to assign,
        // and this app hides controls that can't act (the Series sort, "Only Downloaded", the
        // carousel's "more below" button) rather than greying them out.
        if let onAssignStory, !(bookmark.book?.stories.isEmpty ?? true) {
            Button(action: onAssignStory) {
                Label(bookmark.hasStory ? "Change Story…" : "Assign to Story…",
                      systemImage: "text.book.closed")
            }
        }
        if bookmark.hasStory {
            Button {
                bookmark.clearStory()
                try? context.save()
            } label: {
                Label("Remove from Story", systemImage: "minus.circle")
            }
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }
}
