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
    // Multi-select: when on, a tap toggles selection (via onToggleSelect) rather than
    // opening the comic. Off by default, so Recents / other callers are unaffected.
    var selectionMode: Bool = false
    var selectedIDs: Set<UUID> = []
    var onToggleSelect: (ComicBook) -> Void = { _ in }
    /// Asks the caller to show the comic's details. Both layouts offer it from the context
    /// menu; the caller owns the sheet, so there's one of it per screen rather than one per
    /// cell — the same way `onOpen` hands the reader up.
    var onShowDetail: (ComicBook) -> Void = { _ in }
    let onOpen: (ComicBook) -> Void

    var body: some View {
        if listMode {
            LazyVStack(spacing: 0) {
                ForEach(books) { book in
                    LibraryRow(book: book, selectionMode: selectionMode,
                               isSelected: selectedIDs.contains(book.id),
                               onShowDetail: { onShowDetail(book) }) { tap(book) }
                    Divider().padding(.leading, 76)
                }
            }
        } else {
            LazyVGrid(columns: gridColumns, spacing: LibraryGridMetrics.spacing) {
                ForEach(books) { book in
                    CoverCell(book: book, selectionMode: selectionMode,
                              isSelected: selectedIDs.contains(book.id), maxPixel: coverMaxPixel,
                              onShowDetail: { onShowDetail(book) }) { tap(book) }
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
    var onShowDetail: () -> Void = {}
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
                    Text(book.displayTitle).font(.body).foregroundStyle(.primary).lineLimit(2)
                    // The list has the width for it, so a tagged comic names its lead story
                    // here — the one thing "Topolino 1900" doesn't tell you.
                    if let subtitle = book.displaySubtitle {
                        Text(subtitle)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 5) {
                        Text(book.pageCountLabel)
                        if let stories = book.storyCountLabel {
                            Text("·")
                            Text(stories)
                        }
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
        // No context menu while selecting — the toolbar carries the batch actions, same as
        // the cover cell.
        .contextMenu {
            if !selectionMode {
                Button(action: onOpen) { Label("Read", systemImage: "book") }
                Button(action: onShowDetail) { Label("Details", systemImage: "info.circle") }
            }
        }
    }
}
