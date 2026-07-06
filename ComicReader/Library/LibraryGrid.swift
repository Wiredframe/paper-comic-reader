//
//  LibraryGrid.swift
//  Comic Reader
//
//  Reusable cover grid / list of comics. No ScrollView of its own so callers can
//  compose it with folder sections in a single scroll view.
//

import SwiftUI

struct LibraryGrid: View {
    let books: [ComicBook]
    var folders: [Folder] = []
    var columns: Int = 2
    var listMode: Bool = false
    var inRecents: Bool = false
    let onOpen: (ComicBook) -> Void

    var body: some View {
        if listMode {
            LazyVStack(spacing: 0) {
                ForEach(books) { book in
                    LibraryRow(book: book) { onOpen(book) }
                    Divider().padding(.leading, 76)
                }
            }
        } else {
            LazyVGrid(columns: gridColumns, spacing: 26) {
                ForEach(books) { book in
                    CoverCell(book: book, folders: folders, inRecents: inRecents) { onOpen(book) }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 18), count: max(1, columns))
    }
}

extension View {
    /// The reference app's grouped look: content on a subtly elevated, rounded
    /// card so the cover grid reads as a panel with clear gaps instead of floating
    /// on the black background.
    func libraryCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct LibraryRow: View {
    let book: ComicBook
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                DiskImage(url: book.coverURL, contentMode: .fill)
                    .frame(width: 44, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title).font(.body).foregroundStyle(.primary).lineLimit(2)
                    HStack(spacing: 5) {
                        Text("\(book.pageCount) pages")
                        if book.progress > 0 { ProgressPie(progress: book.progress, size: 13) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
