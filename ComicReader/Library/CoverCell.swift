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

    var body: some View {
        Button(action: onOpen) {
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
                    // Availability leads the row: whether the comic is on the device at all comes
                    // before how far into it you've read.
                    if book.isRemote { AvailabilityBadge() }
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
            book.isRead.toggle()
            try? context.save()
        } label: {
            Label(book.isRead ? "Mark as Unread" : "Mark as Read",
                  systemImage: book.isRead ? "circle" : "checkmark.circle")
        }
        // Folder-backed comics can be pre-fetched or freed here — an owned copy has neither
        // choice (its archive is simply always local).
        if book.isRemote {
            Button { Importer.prefetch(book, in: context) } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        } else if book.isFolderBacked {
            Button { Importer.evictDownload(book, from: context) } label: {
                Label("Remove Download", systemImage: "arrow.down.circle.dotted")
            }
        }
        Divider()
        Button(role: .destructive) { onDelete(book) } label: {
            Label(book.isFolderBacked ? "Delete Entry" : "Delete", systemImage: "trash")
        }
    }
}
