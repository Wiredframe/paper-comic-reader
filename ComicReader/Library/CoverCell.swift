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
    let onOpen: () -> Void

    @Environment(\.modelContext) private var context
    @State private var confirmingDelete = false

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 7) {
                DiskImage(url: book.coverURL, contentMode: .fill, maxPixel: maxPixel)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                                    lineWidth: isSelected ? 3 : 1)
                    )
                    .overlay(alignment: .topTrailing) { selectionBadge }
                    .shadow(color: .black.opacity(0.4), radius: 5, y: 3)

                Text(book.displayTitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // The lead story. One line, always reserved once anything in the grid has a
                // subtitle — a cell that grows only for tagged comics would leave the row it
                // sits in taller than its neighbours, and the covers would drift apart.
                if let subtitle = book.displaySubtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 5) {
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
        .confirmationDialog("Delete “\(book.displayTitle)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Importer.delete(book, from: context) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the comic and its bookmarks from your library.")
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
            book.isRead.toggle()
            try? context.save()
        } label: {
            Label(book.isRead ? "Mark as Unread" : "Mark as Read",
                  systemImage: book.isRead ? "circle" : "checkmark.circle")
        }
        Divider()
        Button(role: .destructive) { confirmingDelete = true } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
