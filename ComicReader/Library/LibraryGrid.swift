//
//  LibraryGrid.swift
//  Comic Reader
//
//  Reusable cover grid / list of comics. No ScrollView of its own so callers can
//  drop it into their own scroll view.
//

import SwiftUI
import SwiftData
import UIKit

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
    /// Asks the caller to confirm deleting a comic — owned by the caller so there's one
    /// confirmation dialog per screen, not one per cover. Only the gallery cells offer it.
    var onDelete: (ComicBook) -> Void = { _ in }
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
                              onShowDetail: { onShowDetail(book) },
                              onDelete: onDelete) { tap(book) }
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

extension View {
    /// The comic search field, shown only in the browse layouts (grid / list). The carousel decks
    /// — Library's Discover, Recents, the Bookmarks carousel — are for browsing by swipe, where a
    /// lookup field reads as the wrong tool, so search is dropped there. Callers clear the bound
    /// text when leaving a searchable layout, so no hidden query keeps filtering behind the deck.
    @ViewBuilder
    func comicSearchable(active: Bool, text: Binding<String>) -> some View {
        if active {
            searchable(text: text, prompt: "Comics, stories, issue #")
        } else {
            self
        }
    }
}

/// Shared cover-grid metrics so Recents / Library / Bookmarks (and the reader's page grid)
/// lay their covers out identically — same proportion, same even spacing.
enum LibraryGridMetrics {
    /// The proportion (width ÷ height) every cover / page slot is shaped to, so the grid stays
    /// an even lattice whatever a comic's real trim is. Sized for the common album / digest —
    /// a European comic is ~14 × 18.5 cm ≈ 0.72–0.76, and a Topolino is ~0.72 — rather than the
    /// old US 2:3 (0.667), which is narrower and cropped a wider cover down its sides (the demo
    /// comics are authored at exactly 2:3, so they hid it — a real library shows it at once).
    /// Covers still fill the slot, so the look stays edge-to-edge and the rows stay even; an
    /// off-ratio cover loses only a sliver rather than a strip.
    static let coverAspect: CGFloat = 0.72

    /// One value for the column gap, the row gap AND the grid's outer margin, so the covers sit
    /// in a uniform rhythm with matching space between them and to the screen edge. The margin
    /// used to be narrower than the gap (16 vs 30), which read as lopsided and cramped at the
    /// edges — now they match.
    static let spacing: CGFloat = 20

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

    /// The default column count for a fresh install, by device — a tablet has the width for more
    /// than the phone's two, and defaulting every device to two turned an iPad into two oversized
    /// covers with hairline margins. One-shot: a count the user has already chosen (or an earlier
    /// launch wrote) is left alone, so this only ever seeds the very first launch.
    static func migrateColumnsDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "library.columns") == nil else { return }
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        defaults.set(isPad ? 4 : 2, forKey: "library.columns")
    }
}

private struct LibraryRow: View {
    let book: ComicBook
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var onShowDetail: () -> Void = {}
    let onOpen: () -> Void

    @Environment(\.modelContext) private var context

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
                        if book.isRemote { AvailabilityBadge(size: 13) }
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
                if book.isRemote {
                    Button { Importer.prefetch(book, in: context) } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                } else if book.isFolderBacked {
                    Button { Importer.evictDownload(book, from: context) } label: {
                        Label("Remove Download", systemImage: "arrow.down.circle.dotted")
                    }
                }
            }
        }
    }
}
