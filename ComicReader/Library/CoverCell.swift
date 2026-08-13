//
//  CoverCell.swift
//  Comic Reader
//
//  One comic in the gallery grid: cover + title + page count + progress pie,
//  with a context menu to read, mark as read, or delete it.
//

import SwiftUI
import SwiftData

struct CoverCell: View {
    let book: ComicBook
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var isHighlighted: Bool = false
    /// Decode the cover down to roughly the on-screen cell size (covers are stored at
    /// 1200px). Keeps grid scrolling smooth and the image cache from thrashing.
    var maxPixel: CGFloat? = nil
    var onShowDetail: () -> Void = {}
    /// Asks the caller to confirm deleting this comic. Hoisted out of the cell so the grid shows
    /// one confirmation dialog instead of one per cover — the same way `onShowDetail` hands the
    /// detail sheet up. Off by default, so callers that don't delete are unaffected.
    var onDelete: (ComicBook) -> Void = { _ in }
    let onOpen: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        Button(action: tapped) {
            VStack(spacing: 7) {
                DiskImage(url: book.coverURL, contentMode: .fill, maxPixel: maxPixel)
                    .aspectRatio(LibraryGridMetrics.coverAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                                    lineWidth: isSelected ? 3 : 1)
                    )
                    // Shuffle "focus": a brief accent ring so the eye lands on the comic the
                    // random button scrolled to, without opening it.
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 3)
                            .opacity(isHighlighted ? 1 : 0)
                    )
                    .overlay(alignment: .topTrailing) { selectionBadge }
                    // Cast the shadow from the cover's rounded-rect PATH, not the decoded image's
                    // alpha channel: an alpha-derived `.shadow` forces an offscreen pass per cell
                    // on every scroll frame (the reader page avoids the same trap with an explicit
                    // shadowPath — see ReaderPageCell). The opaque cover hides the fill; only its
                    // shadow shows, so the look is unchanged but the grid scrolls without the pass.
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                            .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
                    )
                    .scaleEffect(isHighlighted ? 1.05 : 1)

                Text(book.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // The lead story. One line, always reserved once anything in the grid has a
                // subtitle — a cell that grows only for tagged comics would leave the row it
                // sits in taller than its neighbours, and the covers would drift apart.
                Text(book.displaySubtitle ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    // The favourite mark leads, then availability: what you chose about the comic
                    // comes before facts about the file, and both before how far into it you've read.
                    if book.isFavorite { FavoriteHeart() }
                    AvailabilityIndicator(book: book)
                    Text(book.pageCountLabel)
                    if book.progress > 0 { ProgressPie(progress: book.progress) }
                    // "Read" is independent of progress (browsing never overwrites it),
                    // so it gets its own indicator next to the pie.
                    if book.isRead { ReadCheck() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectionMode && isSelected ? .isSelected : [])
        // No per-item context menu while selecting — the toolbar carries the batch actions.
        .contextMenu { if !selectionMode { menu } }
    }

    /// While this comic is being fetched, the tap stops the fetch, which is what the x in the
    /// ring on the cell is saying and the only cancel target here big enough to hit. Otherwise
    /// it opens the comic, as always.
    private func tapped() {
        if downloads.isDownloading(book.id) {
            downloads.cancel(book.id)
        } else {
            onOpen()
        }
    }

    /// The corner check shown in selection mode — filled accent when picked, a hollow ring
    /// otherwise (standard iOS multi-select affordance).
    @ViewBuilder private var selectionBadge: some View {
        if selectionMode {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .padding(8)
                .accessibilityHidden(true)   // state is announced via the cell's .isSelected trait
        }
    }

    @ViewBuilder private var menu: some View {
        Button(action: onOpen) { Label("Read", systemImage: "book") }
        Button(action: onShowDetail) { Label("Details", systemImage: "info.circle") }
        Button {
            book.isFavorite.toggle()
            try? context.save()
        } label: {
            Label(book.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: book.isFavorite ? "heart.slash" : "heart")
        }
        Button {
            book.isRead.toggle()
            try? context.save()
        } label: {
            Label(book.isRead ? "Mark as Unread" : "Mark as Read",
                  systemImage: book.isRead ? "circle" : "checkmark.circle")
        }
        // Only offered once there is something to forget: on a never-opened comic the row would
        // be permanently greyed-out furniture in a menu that is already long.
        if book.openCount > 0 {
            Button {
                book.resetOpenCount()
                try? context.save()
            } label: {
                Label("Reset Open Count", systemImage: "arrow.counterclockwise")
            }
        }
        // Folder-backed comics can be fetched, stopped or freed here. An owned copy has none of
        // those choices: its archive is simply always local.
        DownloadMenuItems(book: book)
        Divider()
        Button(role: .destructive) { onDelete(book) } label: {
            Label(book.isFolderBacked ? "Delete Entry" : "Delete", systemImage: "trash")
        }
    }
}
