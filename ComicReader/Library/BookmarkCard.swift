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
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 7) {
                DiskImage(url: bookmark.thumbURL, contentMode: .fill, maxPixel: maxPixel)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.1)))
                    .shadow(color: .black.opacity(0.4), radius: 5, y: 3)

                VStack(spacing: 2) {
                    if showsTitle {
                        Text(bookmark.book?.displayTitle ?? "—")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text("Page \(bookmark.pageIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
