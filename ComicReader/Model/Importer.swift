//
//  Importer.swift
//  Comic Reader
//
//  Turns a picked / shared archive URL into a library entry: copies the file
//  into app storage, reads it, renders a cover, and inserts a ComicBook.
//

import Foundation
import SwiftData
import UIKit

enum Importer {

    /// Longest side (device pixels) of the stored cover thumbnail. Shared with the
    /// bookmark page shots so both stay crisp at the same full-width card size.
    static let coverMaxPixel: CGFloat = ImageDownsampler.libraryCardPixel

    enum ImportError: Error { case unsupported, copyFailed, empty }

    /// Everything a new library entry needs, computed off the archive — no SwiftData,
    /// so it can be produced on a background thread (see `prepare`).
    struct Prepared {
        let id: UUID
        let title: String
        let fileName: String
        let format: ComicFormat
        let pageCount: Int
        let coverName: String?
        let coverAspect: Double?
    }

    /// The heavy half of an import — copy the file into storage, read the archive and
    /// render its cover. Deliberately NOT main-actor: it does all the slow work off the
    /// main thread so the UI stays responsive (and can show progress) during a batch
    /// import. Throws on unsupported / copy failure / empty archive.
    static func prepare(from sourceURL: URL) throws -> Prepared {
        // Files from the picker / share sheet are security-scoped.
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let format = ComicArchiveFactory.format(of: sourceURL) else {
            throw ImportError.unsupported
        }

        let id = UUID()
        let ext = sourceURL.pathExtension.isEmpty
            ? (format == .zip ? "cbz" : "cbr")
            : sourceURL.pathExtension.lowercased()
        let fileName = "\(id.uuidString).\(ext)"
        let destURL = Storage.comicURL(fileName)

        do {
            if Storage.fm.fileExists(atPath: destURL.path) {
                try Storage.fm.removeItem(at: destURL)
            }
            try Storage.fm.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw ImportError.copyFailed
        }

        guard let archive = try? ComicArchiveFactory.open(url: destURL), archive.pageCount > 0 else {
            try? Storage.fm.removeItem(at: destURL)
            throw ImportError.empty
        }

        // Cover from the first page. Its aspect is captured here — the image is already in
        // hand, so it costs nothing, and Discover needs it to size an uncropped card.
        var coverName: String?
        var coverAspect: Double?
        if let data = archive.pageData(at: 0),
           let cover = ImageDownsampler.downsample(data, maxPixel: coverMaxPixel) {
            let name = "\(id.uuidString).jpg"
            if ImageDownsampler.writeJPEG(cover, to: Storage.coverURL(name)) {
                coverName = name
                if cover.size.height > 0 { coverAspect = cover.size.width / cover.size.height }
            }
        }

        let title = sourceURL.deletingPathExtension().lastPathComponent
        return Prepared(id: id, title: title, fileName: fileName,
                        format: format, pageCount: archive.pageCount,
                        coverName: coverName, coverAspect: coverAspect)
    }

    /// The light half — insert a prepared import into the store. Main-actor: SwiftData's
    /// `ModelContext` is bound to the thread that owns it (the view's main context).
    @MainActor @discardableResult
    static func commit(_ prepared: Prepared, into context: ModelContext) -> ComicBook {
        let book = ComicBook(id: prepared.id, title: prepared.title, fileName: prepared.fileName,
                             format: prepared.format, pageCount: prepared.pageCount,
                             coverName: prepared.coverName, coverAspect: prepared.coverAspect)
        context.insert(book)
        try? context.save()
        return book
    }

    /// Imports the archive at `sourceURL` into `context` synchronously. Kept for the
    /// single-file paths (a comic opened from Files / "Open With", DEBUG seeding); the
    /// batch picker import runs `prepare` off-main and `commit` on-main itself so it can
    /// report progress (see LibraryView).
    @MainActor @discardableResult
    static func importComic(from sourceURL: URL,
                            into context: ModelContext) throws -> ComicBook {
        commit(try prepare(from: sourceURL), into: context)
    }

    /// Removes a book and its on-disk files.
    @MainActor static func delete(_ book: ComicBook, from context: ModelContext) {
        try? Storage.fm.removeItem(at: book.archiveURL)
        if let cover = book.coverURL { try? Storage.fm.removeItem(at: cover) }
        for bookmark in book.bookmarks {
            try? Storage.fm.removeItem(at: bookmark.thumbURL)
        }
        try? Storage.fm.removeItem(at: Storage.pageThumbs(for: book.id))
        context.delete(book)
        try? context.save()
    }
}
