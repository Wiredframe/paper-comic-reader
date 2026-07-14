//
//  LibraryGrid.swift
//  Comic Reader
//
//  Reusable cover grid / list of comics. No ScrollView of its own so callers can
//  drop it into their own scroll view.
//

import SwiftUI

struct LibraryGrid: View {
    let books: [ComicBook]
    var columns: Int = 2
    var listMode: Bool = false
    var inRecents: Bool = false
    // Multi-select: when on, a tap toggles selection (via onToggleSelect) rather than
    // opening the comic. Off by default, so Recents / other callers are unaffected.
    var selectionMode: Bool = false
    var selectedIDs: Set<UUID> = []
    var onToggleSelect: (ComicBook) -> Void = { _ in }
    let onOpen: (ComicBook) -> Void

    var body: some View {
        if listMode {
            LazyVStack(spacing: 0) {
                ForEach(books) { book in
                    LibraryRow(book: book, selectionMode: selectionMode,
                               isSelected: selectedIDs.contains(book.id)) { tap(book) }
                    Divider().padding(.leading, 76)
                }
            }
        } else {
            LazyVGrid(columns: gridColumns, spacing: LibraryGridMetrics.spacing) {
                ForEach(books) { book in
                    CoverCell(book: book, inRecents: inRecents, selectionMode: selectionMode,
                              isSelected: selectedIDs.contains(book.id), maxPixel: coverMaxPixel) { tap(book) }
                }
            }
        }
    }

    private func tap(_ book: ComicBook) {
        if selectionMode { onToggleSelect(book) } else { onOpen(book) }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: LibraryGridMetrics.spacing),
              count: max(1, columns))
    }

    private var coverMaxPixel: CGFloat { LibraryGridMetrics.coverMaxPixel(columns: columns) }
}

/// Shared cover-grid spacing so Recents / Library / Bookmarks stay identical and
/// the gap between columns is clearly visible (equal horizontally and vertically).
enum LibraryGridMetrics {
    static let spacing: CGFloat = 30

    /// Cover decode target for the current zoom level — covers and bookmark shots are
    /// stored at 1200px, but a grid cell only needs roughly its on-screen size. Shared by
    /// the library grid and the bookmarks grid so both downsample identically (off-main,
    /// and small enough that many stay resident in the shared image cache while scrolling).
    static func coverMaxPixel(columns: Int) -> CGFloat {
        switch columns {
        case 1:  return 1000
        case 2:  return 680
        case 3:  return 460
        default: return 360
        }
    }
}

private struct LibraryRow: View {
    let book: ComicBook
    var selectionMode: Bool = false
    var isSelected: Bool = false
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                if selectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isSelected ? .white : Color.secondary,
                                         isSelected ? Color.accentColor : .clear)
                }
                DiskImage(url: book.coverURL, contentMode: .fill, maxPixel: 260)
                    .frame(width: 44, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title).font(.body).foregroundStyle(.primary).lineLimit(2)
                    HStack(spacing: 5) {
                        Text(book.pageCountLabel)
                        if book.progress > 0 { ProgressPie(progress: book.progress, size: 13) }
                        if book.isRead { ReadCheck(size: 13) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectionMode && isSelected ? .isSelected : [])
    }
}
