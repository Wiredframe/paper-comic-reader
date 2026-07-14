//
//  CoverCell.swift
//  Comic Reader
//
//  One comic in the gallery grid: cover + title + page count + progress pie,
//  with a context menu to read, remove from Recents, or delete it.
//

import SwiftUI
import SwiftData

struct CoverCell: View {
    let book: ComicBook
    var inRecents: Bool = false
    let onOpen: () -> Void

    @Environment(\.modelContext) private var context
    @State private var confirmingDelete = false

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 7) {
                DiskImage(url: book.coverURL, contentMode: .fill)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.08))
                    )
                    .shadow(color: .black.opacity(0.4), radius: 5, y: 3)

                Text(book.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    Text("\(book.pageCount) pages")
                    if book.progress > 0 { ProgressPie(progress: book.progress) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
        .confirmationDialog("Delete “\(book.title)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Importer.delete(book, from: context) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the comic and its bookmarks from your library.")
        }
    }

    @ViewBuilder private var menu: some View {
        Button(action: onOpen) { Label("Read", systemImage: "book") }
        Button {
            book.isRead.toggle()
            try? context.save()
        } label: {
            Label(book.isRead ? "Mark as Unread" : "Mark as Read",
                  systemImage: book.isRead ? "circle" : "checkmark.circle")
        }
        if inRecents {
            Button { removeFromRecents() } label: {
                Label("Remove from Recents", systemImage: "clock.badge.xmark")
            }
        }
        Divider()
        Button(role: .destructive) { confirmingDelete = true } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Drops the comic from the Recents tab without touching the library or its
    /// bookmarks — just forgets when it was last opened.
    private func removeFromRecents() {
        book.dateOpened = nil
        try? context.save()
    }
}
