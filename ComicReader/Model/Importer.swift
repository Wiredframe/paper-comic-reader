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
        let pageCount: Int
        let coverName: String?
        let coverAspect: Double?
        /// Parsed from the archive's ComicInfo.xml, when it has one.
        let info: ComicInfoData?
        /// Set for a folder-scanned entry — the file's path relative to the library folder, which
        /// the entry stores so its bytes can be fetched on demand. Nil for an owned copy (the
        /// archive was copied straight in). See `prepareFolderEntry` and `ComicBook.sourceRelativePath`.
        var sourceRelativePath: String? = nil
    }

    /// The heavy half of an import — copy the file into storage, read the archive and
    /// render its cover. Deliberately NOT main-actor: it does all the slow work off the
    /// main thread so the UI stays responsive (and can show progress) during a batch
    /// import. Throws on unsupported / copy failure / empty archive.
    static func prepare(from sourceURL: URL) throws -> Prepared {
        // Files from the picker / share sheet are security-scoped.
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        guard ComicArchive.looksLikeComic(at: sourceURL) else {
            throw ImportError.unsupported
        }

        let id = UUID()
        let ext = sourceURL.pathExtension.isEmpty ? "cbz" : sourceURL.pathExtension.lowercased()
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

        guard let archive = try? ComicArchive(url: destURL), archive.pageCount > 0 else {
            try? Storage.fm.removeItem(at: destURL)
            throw ImportError.empty
        }

        let (coverName, coverAspect, info) = coverAndInfo(from: archive, id: id)
        let title = sourceURL.deletingPathExtension().lastPathComponent
        return Prepared(id: id, title: title, fileName: fileName,
                        pageCount: archive.pageCount,
                        coverName: coverName, coverAspect: coverAspect, info: info)
    }

    /// Prepares a library entry from a comic in the configured library folder WITHOUT copying its
    /// bytes in: only the cover (one page) and ComicInfo.xml are read, so a folder scan pulls a
    /// fraction of each file over the network rather than the whole archive. `fileName` is the
    /// name the bytes will take in local storage once the comic is actually downloaded (see
    /// `downloadArchive`); `relativePath` is the file's path under the folder, stored as the
    /// entry's stable source identity. Deliberately NOT main-actor — the read is slow I/O.
    ///
    /// `sourceURL` must be reachable when this runs: either a child of a folder whose security
    /// scope the caller already holds (the scan — see `LibrarySource.withFolderAccess`), or a
    /// picker URL that scopes itself (the reader's "choose another file" relink).
    static func prepareFolderEntry(from sourceURL: URL, relativePath: String) throws -> Prepared {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        guard ComicArchive.looksLikeComic(at: sourceURL) else { throw ImportError.unsupported }

        let id = UUID()
        let ext = sourceURL.pathExtension.isEmpty ? "cbz" : sourceURL.pathExtension.lowercased()
        let fileName = "\(id.uuidString).\(ext)"

        guard let archive = try? ComicArchive(url: sourceURL), archive.pageCount > 0 else {
            throw ImportError.empty
        }
        let (coverName, coverAspect, info) = coverAndInfo(from: archive, id: id)
        let title = sourceURL.deletingPathExtension().lastPathComponent
        return Prepared(id: id, title: title, fileName: fileName,
                        pageCount: archive.pageCount,
                        coverName: coverName, coverAspect: coverAspect, info: info,
                        sourceRelativePath: relativePath)
    }

    /// The cover thumbnail (written to Storage.covers, its aspect captured) and parsed ComicInfo
    /// for a prepared import. Shared by the copy-in import and the folder scan so both render an
    /// entry identically — the only difference between them is whether the archive was copied.
    private static func coverAndInfo(from archive: ComicArchive, id: UUID)
        -> (coverName: String?, coverAspect: Double?, info: ComicInfoData?) {
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
        return (coverName, coverAspect, archive.metadataXML().flatMap(ComicInfoParser.parse))
    }

    /// The light half — insert a prepared import into the store. Main-actor: SwiftData's
    /// `ModelContext` is bound to the thread that owns it (the view's main context).
    @MainActor @discardableResult
    static func commit(_ prepared: Prepared, into context: ModelContext) -> ComicBook {
        let book = ComicBook(id: prepared.id, title: prepared.title, fileName: prepared.fileName,
                             pageCount: prepared.pageCount,
                             coverName: prepared.coverName, coverAspect: prepared.coverAspect)
        book.sourceRelativePath = prepared.sourceRelativePath
        // A folder entry lands un-downloaded (only cover + metadata are in yet); an owned copy has
        // its archive already, so it stays local.
        book.hasLocalArchive = prepared.sourceRelativePath == nil
        book.apply(prepared.info)
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

    // MARK: Folder-backed availability (download / evict / relink)

    /// Fetches a folder-backed comic's bytes into local storage, reporting 0…1 progress. Resolves
    /// the source (folder bookmark + the entry's relative path) and copies it to `dest` (the
    /// comic's `archiveURL`) via a temp file, so a failed or cancelled fetch never leaves a
    /// half-written archive that would read as present. Takes value types, not the `ComicBook`, so
    /// nothing main-actor-bound crosses into the background — same discipline as `PageImageStore.open`.
    /// NOT main-actor and not detached: it's awaited straight from the reader's `.task`, so it runs
    /// off-main AND inherits that task's cancellation (closing the reader mid-fetch cancels it).
    /// Throws `LibrarySource.SourceError` on any failure.
    static func downloadArchive(relativePath: String, into dest: URL,
                                onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let folder = try LibrarySource.resolveFolder()
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let source = folder.appendingPathComponent(relativePath)
        guard Storage.fm.fileExists(atPath: source.path) else {
            throw LibrarySource.SourceError.fileMissing
        }

        let temp = dest.appendingPathExtension("part")
        try? Storage.fm.removeItem(at: temp)
        do {
            try copyWithProgress(from: source, to: temp, onProgress: onProgress)
        } catch is CancellationError {
            try? Storage.fm.removeItem(at: temp)
            throw LibrarySource.SourceError.cancelled
        } catch {
            try? Storage.fm.removeItem(at: temp)
            throw LibrarySource.SourceError.copyFailed
        }
        if Storage.fm.fileExists(atPath: dest.path) { try? Storage.fm.removeItem(at: dest) }
        do {
            try Storage.fm.moveItem(at: temp, to: dest)
        } catch {
            try? Storage.fm.removeItem(at: temp)
            throw LibrarySource.SourceError.copyFailed
        }
    }

    /// Chunked file copy that reports progress and honours task cancellation — `FileManager`'s own
    /// copy offers neither, and a big comic over a slow share needs both. One 1 MB buffer, so the
    /// copy costs the same whether the archive is 5 MB or 500.
    private static func copyWithProgress(from source: URL, to dest: URL,
                                         onProgress: (Double) -> Void) throws {
        let total = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard let reader = try? FileHandle(forReadingFrom: source) else {
            throw LibrarySource.SourceError.copyFailed
        }
        defer { try? reader.close() }
        Storage.fm.createFile(atPath: dest.path, contents: nil)
        guard let writer = try? FileHandle(forWritingTo: dest) else {
            throw LibrarySource.SourceError.copyFailed
        }
        defer { try? writer.close() }

        let chunk = 1 << 20   // 1 MB
        var written: Int64 = 0
        while true {
            try Task.checkCancellation()
            let data = (try? reader.read(upToCount: chunk)) ?? Data()
            if data.isEmpty { break }
            do { try writer.write(contentsOf: data) }
            catch { throw LibrarySource.SourceError.copyFailed }
            written += Int64(data.count)
            if total > 0 { onProgress(min(1, Double(written) / Double(total))) }
        }
        onProgress(1)
    }

    /// Drops a folder-backed comic's downloaded bytes, keeping the entry, cover and metadata so it
    /// stays in the library marked "not downloaded". The page-grid thumbnails go too (regenerable,
    /// and stale for a re-download); bookmarks stay — their shots live in Storage.bookmarkThumbs,
    /// independent of the archive.
    @MainActor static func evictDownload(_ book: ComicBook, from context: ModelContext) {
        try? Storage.fm.removeItem(at: book.archiveURL)
        try? Storage.fm.removeItem(at: Storage.pageThumbs(for: book.id))
        book.hasLocalArchive = false
        try? context.save()
    }

    /// Best-effort background pre-fetch of a folder-backed comic, for the library's "Download"
    /// menu item. Fire-and-forget: it flips the badge when the bytes land and stays quiet on
    /// failure — progress and errors belong to opening the comic, which shows both. A no-op for
    /// an owned copy or one already local, so callers can wire it without pre-checking.
    @MainActor static func prefetch(_ book: ComicBook, in context: ModelContext) {
        guard let rel = book.sourceRelativePath, book.isRemote else { return }
        let dest = book.archiveURL
        Task {
            do {
                try await downloadArchive(relativePath: rel, into: dest) { _ in }
                book.hasLocalArchive = true
                try? context.save()
            } catch {
                // Left "not downloaded" — opening it surfaces the reason.
            }
        }
    }

    /// Copies a user-picked replacement archive into `destURL` (a comic's `archiveURL`) so a
    /// comic whose source went missing opens right away. Returns the pick's path relative to the
    /// library folder when it sits inside it — the caller stores that as the entry's new permanent
    /// source — or nil when the pick was a one-off rescue from elsewhere and the old source stands.
    /// Off-main (copy I/O); throws `LibrarySource.SourceError` on failure.
    static func relink(from pickedURL: URL, into destURL: URL) throws -> String? {
        let scoped = pickedURL.startAccessingSecurityScopedResource()
        defer { if scoped { pickedURL.stopAccessingSecurityScopedResource() } }
        guard ComicArchive.looksLikeComic(at: pickedURL) else {
            throw LibrarySource.SourceError.copyFailed
        }

        let temp = destURL.appendingPathExtension("part")
        try? Storage.fm.removeItem(at: temp)
        do { try Storage.fm.copyItem(at: pickedURL, to: temp) }
        catch { try? Storage.fm.removeItem(at: temp); throw LibrarySource.SourceError.copyFailed }
        if Storage.fm.fileExists(atPath: destURL.path) { try? Storage.fm.removeItem(at: destURL) }
        do { try Storage.fm.moveItem(at: temp, to: destURL) }
        catch { try? Storage.fm.removeItem(at: temp); throw LibrarySource.SourceError.copyFailed }

        if let folder = try? LibrarySource.resolveFolder() {
            let f = folder.startAccessingSecurityScopedResource()
            defer { if f { folder.stopAccessingSecurityScopedResource() } }
            if LibrarySource.contains(pickedURL, in: folder) {
                return LibrarySource.relativePath(of: pickedURL, in: folder)
            }
        }
        return nil
    }

    // MARK: Folder scan

    /// Scans the configured library folder and imports every comic not already an entry (matched
    /// by relative path), creating a folder-backed entry — cover + metadata, no archive copy — for
    /// each. Reports "done of total" as it goes; comics appear in the grid as each one lands.
    ///
    /// `existing` is the set of relative paths already imported, snapshotted on the main actor
    /// (SwiftData models can't leave it). The walk and each per-file read run off-main, each inside
    /// its own `withFolderAccess` so the folder's security scope is never held across an actor hop;
    /// the inserts hop back here. A file that won't read (offline mid-scan, not a real archive) is
    /// skipped, not fatal. Returns how many entries were added.
    @MainActor @discardableResult
    static func scanFolder(existing: Set<String>, into context: ModelContext,
                           onProgress: @MainActor (_ done: Int, _ total: Int) -> Void) async throws -> Int {
        let paths: [String] = try await Task.detached(priority: .userInitiated) {
            try LibrarySource.withFolderAccess { folder in
                LibrarySource.comicFiles(in: folder).map(\.relativePath)
            }
        }.value

        let newPaths = paths.filter { !existing.contains($0) }
        onProgress(0, newPaths.count)
        guard !newPaths.isEmpty else { return 0 }

        var added = 0
        for (index, relativePath) in newPaths.enumerated() {
            let prepared = try? await Task.detached(priority: .userInitiated) {
                try LibrarySource.withFolderAccess { folder in
                    try prepareFolderEntry(from: folder.appendingPathComponent(relativePath),
                                           relativePath: relativePath)
                }
            }.value
            if let prepared {
                commit(prepared, into: context)
                added += 1
            }
            onProgress(index + 1, newPaths.count)
        }
        return added
    }

    // MARK: Metadata backfill

    /// One archive's ComicInfo.xml, read. Carries the result across the actor hop: the
    /// SwiftData models it came from belong to the main actor and can't make the trip.
    private struct ScannedMetadata: Sendable {
        let id: UUID
        let info: ComicInfoData?   // nil = untagged, or the archive wouldn't open
    }

    /// Reads ComicInfo.xml for every comic that hasn't been looked at — comics imported before
    /// metadata existed, on the first launch after the update.
    ///
    /// Opens each archive off the main actor (a ZIP central-directory walk apiece, which is
    /// exactly the work that used to freeze the app when it ran on-main — see `PageImageStore.open`),
    /// then applies the whole batch with a SINGLE save: a per-book save would republish the
    /// @Query once per comic and stutter the grid while it ran.
    @MainActor
    static func backfillMetadata(for books: [ComicBook], into context: ModelContext) async {
        let pending: [(id: UUID, url: URL)] = books
            .filter { !$0.metadataScanned }
            .map { ($0.id, $0.archiveURL) }
        guard !pending.isEmpty else { return }

        let scanned: [ScannedMetadata] = await Task.detached(priority: .utility) {
            pending.map { book in
                ScannedMetadata(id: book.id,
                                info: (try? ComicArchive(url: book.url))?
                                    .metadataXML()
                                    .flatMap(ComicInfoParser.parse))
            }
        }.value

        let byID = Dictionary(scanned.map { ($0.id, $0.info) }, uniquingKeysWith: { first, _ in first })
        for book in books where !book.metadataScanned {
            // `apply` marks the book scanned either way, including for an archive that wouldn't
            // open: that comic can't be read at all, and retrying it on every launch would only
            // pay the open cost forever to learn the same thing.
            guard let info = byID[book.id] else { continue }
            book.apply(info)
        }
        try? context.save()
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
