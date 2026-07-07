//
//  CoverCell.swift
//  Comic Reader
//
//  One comic in the gallery grid: cover + title + page count + progress pie,
//  with a context menu to move it between folders or delete it.
//

import SwiftUI
import SwiftData

struct CoverCell: View {
    let book: ComicBook
    var folders: [Folder] = []
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
        if inRecents {
            Button { removeFromRecents() } label: {
                Label("Remove from Recents", systemImage: "clock.badge.xmark")
            }
        }
        if !folders.isEmpty {
            Menu {
                Button { move(to: nil) } label: {
                    Label("None", systemImage: book.folder == nil ? "checkmark" : "tray")
                }
                ForEach(folders) { folder in
                    Button { move(to: folder) } label: {
                        Label(folder.name, systemImage: book.folder?.id == folder.id ? "checkmark" : "folder")
                    }
                }
            } label: { Label("Move to Collection", systemImage: "folder") }
        }
        Divider()
        Button(role: .destructive) { confirmingDelete = true } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func move(to folder: Folder?) {
        book.folder = folder
        try? context.save()
    }

    /// Drops the comic from the Recents tab without touching the library or its
    /// bookmarks — just forgets when it was last opened.
    private func removeFromRecents() {
        book.dateOpened = nil
        try? context.save()
    }
}
