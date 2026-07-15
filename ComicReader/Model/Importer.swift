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

    /// Imports the archive at `sourceURL` into `context` synchronously — `prepare` and
    /// `commit` back to back, all on the main actor.
    ///
    /// Only for DEBUG screenshot seeding, where blocking is fine and the archives are
    /// known-small. Everything user-facing (the picker, and comics opened from Files /
    /// "Open With") goes through `prepare` off-main + `commit` on-main so the UI stays
    /// responsive and can report progress — see `LibraryView.runImport`.
    @MainActor @discardableResult
    static func importComic(from sourceURL: URL,
                            into context: ModelContext) throws -> ComicBook {
        commit(try prepare(from: sourceURL), into: context)
    }

    /// One archive already in the library, as plain data. The duplicate scan reads files and
    /// so runs off the main actor, where the SwiftData models it came from can't go — this
    /// carries the two things the scan needs across.
    struct ExistingArchive: Sendable {
        let id: UUID
        let path: String
    }

    /// The book in `existing` whose archive is byte-for-byte the file at `sourceURL`, or nil
    /// if this comic is new.
    ///
    /// Size first, bytes only on a match: importing a genuinely new comic costs one `stat`
    /// per library entry and reads nothing. Content rather than file name on purpose — a
    /// renamed copy is still the same comic, and two unrelated comics can share a name.
    static func duplicate(of sourceURL: URL, among existing: [ExistingArchive]) -> UUID? {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let size = fileSize(sourceURL) else { return nil }
        for candidate in existing {
            let url = URL(fileURLWithPath: candidate.path)
            guard fileSize(url) == size, sameContents(sourceURL, url) else { continue }
            return candidate.id
        }
        return nil
    }

    private static func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    /// Chunked, so comparing two 1 GB archives costs one buffer rather than two gigabytes
    /// of RAM. Callers have already established that the lengths match.
    private static func sameContents(_ a: URL, _ b: URL) -> Bool {
        guard let handleA = try? FileHandle(forReadingFrom: a),
              let handleB = try? FileHandle(forReadingFrom: b) else { return false }
        defer { try? handleA.close(); try? handleB.close() }

        let chunk = 1 << 20   // 1 MB
        while true {
            let dataA = (try? handleA.read(upToCount: chunk)) ?? Data()
            let dataB = (try? handleB.read(upToCount: chunk)) ?? Data()
            if dataA != dataB { return false }
            if dataA.isEmpty { return true }   // both ran out together — identical
        }
    }

    /// When another app opens a file "into" us, iOS drops a copy in Documents/Inbox.
    /// Once `prepare` has copied the archive into permanent storage that leftover is
    /// dead weight, so delete it. A no-op for anything outside Inbox — in-place opens
    /// (from Files) and picker URLs live elsewhere and must not be touched.
    static func discardInboxCopy(at url: URL) {
        // Resolve symlinks on both sides so a /private/var… URL still matches the
        // /var… Documents base (the two forms otherwise never share a prefix).
        let inbox = URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
            .resolvingSymlinksInPath().path
        guard url.resolvingSymlinksInPath().path.hasPrefix(inbox) else { return }
        try? Storage.fm.removeItem(at: url)
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
