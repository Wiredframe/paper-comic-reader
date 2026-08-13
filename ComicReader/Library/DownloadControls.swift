//
//  DownloadControls.swift
//  Comic Reader
//
//  The controls a listing offers for a folder-backed comic's bytes: the menu block the
//  grid, the list and Discover all share, and Discover's own Read / Download / Cancel
//  button. The matching badge lives with the other status marks in ProgressPie.
//
//  Both are leaves that look their download up in the environment themselves. That is
//  deliberate: progress arrives megabyte by megabyte, and a value passed down from a grid
//  or a carousel would re-render that grid or carousel on every tick (see the header of
//  PeekCarouselView, and the memoised derivation in LibraryView).
//

import SwiftUI
import SwiftData

/// Download / Cancel Download / Remove Download, in that order of relevance to the comic in
/// front of you. Nothing at all for an owned copy, which is simply always local.
struct DownloadMenuItems: View {
    let book: ComicBook

    @Environment(\.modelContext) private var context
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        if downloads.isDownloading(book.id) {
            Button { downloads.cancel(book.id) } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        } else if book.isRemote {
            Button { downloads.start(book, in: context) } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        } else if book.isFolderBacked {
            Button { Importer.evictDownload(book, from: context) } label: {
                Label("Remove Download", systemImage: "arrow.down.circle.dotted")
            }
        }
    }
}

/// Discover's main button. One button, three jobs, because there is only ever one thing worth
/// doing with the comic in front of you: read it, fetch it, or stop fetching it. It doesn't open
/// the comic when the download lands: you asked for the bytes, not for the reader.
struct ReadOrDownloadButton: View {
    let book: ComicBook
    /// Discover's button shares a fixed-height row with two others and takes the space left over;
    /// the detail sheet's sits on its own and is as wide as its label.
    var fillsWidth: Bool = false
    var minHeight: CGFloat = 0
    let onRead: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        Button(action: act) {
            label
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: minHeight)
                // The accent is a bright orange-yellow, and white on it barely reads.
                .foregroundStyle(.black)
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder private var label: some View {
        if let ticket = downloads.ticket(for: book.id) {
            // The ring replaces the icon in place, so the button doesn't change shape as it
            // changes job: the panel's height is fixed and the covers above it must not move.
            Label {
                Text("Cancel")
            } icon: {
                // Black like the label: the button's own fill is the accent colour, so an
                // accent ring on it would be a ring you can't see.
                DownloadRing(progress: ticket.progress, size: 16, tint: .black)
            }
        } else if book.isRemote {
            Label("Download", systemImage: "arrow.down.circle")
        } else {
            Label("Read", systemImage: "book")
        }
    }

    private func act() {
        if downloads.isDownloading(book.id) {
            downloads.cancel(book.id)
        } else if book.isRemote {
            downloads.start(book, in: context)
        } else {
            onRead()
        }
    }
}
