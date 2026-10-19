//
//  LibraryBackupArchive.swift
//  Comic Reader
//
//  Packing a library into one .zip and reading it back.
//
//  Layout inside the file:
//
//      library.json          the document (see LibraryBackup)
//      covers/<name>.jpg     cover thumbnails
//      thumbs/<name>.jpg     bookmark page shots
//      comics/<name>.cbz     archives of owned copies only
//
//  A plain .zip and no custom document type on purpose: the point of this file is to be movable
//  by whatever the reader already uses — AirDrop, Mail, Files, a cable, a NAS — and a bespoke UTI
//  would only narrow that. It is validated by looking inside, not by its extension.
//
//  Nothing is staged. Covers, thumbnails and archives are added to the zip straight from their
//  place in Storage, because staging would mean a second copy of every comic on a device that may
//  not have room for the first one twice.
//

import Foundation
import ZIPFoundation

enum LibraryBackupArchive {

    enum BackupError: LocalizedError {
        case notABackup
        case unreadable
        case fromNewerVersion
        case writeFailed
        case notEnoughSpace

        var errorDescription: String? {
            switch self {
            case .notABackup:       return String(localized: "That file isn't a Paper Comic library backup.")
            case .unreadable:       return String(localized: "The backup couldn't be read. It may be incomplete.")
            case .fromNewerVersion: return String(localized: "That backup was made by a newer version of the app.")
            case .writeFailed:      return String(localized: "The backup couldn't be written.")
            case .notEnoughSpace:   return String(localized: "There isn't enough free space on this device for the backup. Free up some space and try again.")
            }
        }
    }

    private static let documentName = "library.json"
    private static let coversFolder = "covers"
    private static let thumbsFolder = "thumbs"
    private static let comicsFolder = "comics"

    // MARK: Export

    /// Writes the backup and returns the file to hand to the share sheet.
    ///
    /// `onProgress` is called with completed/total file counts, so the UI can be determinate: an
    /// export carrying a few hundred megabytes of archives is not something to show a spinner for.
    /// Reported at most once per percent (and always on the last file), because a library of a few
    /// thousand files would otherwise ask the main actor to redraw a bar that moved by a pixel a few
    /// thousand times. Runs off the main actor — every line of it is disk work.
    static func write(_ backup: LibraryBackup,
                      onProgress: @Sendable (_ done: Int, _ total: Int) -> Void) throws -> URL {
        // Each export gets its own directory, and older ones are swept as this one starts. Not one
        // shared directory: the share sheet holds the file open for as long as it needs it, so an
        // export can't clean up after itself on the way out — and a single directory would mean
        // exporting again while a share sheet was still open deleted the file underneath it.
        let base = Storage.fm.temporaryDirectory.appendingPathComponent("LibraryBackup",
                                                                       isDirectory: true)
        let workspace = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try Storage.fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        } catch {
            throw BackupError.writeFailed
        }
        sweepOldExports(in: base, keeping: workspace)

        // What goes in, worked out up front so the progress total is honest rather than a guess
        // that grows as it runs.
        var payload: [(path: String, file: URL)] = []
        for comic in backup.comics {
            if let cover = comic.coverName {
                payload.append(("\(coversFolder)/\(cover)", Storage.coverURL(cover)))
            }
            for bookmark in comic.bookmarks {
                if let thumb = bookmark.thumbName {
                    payload.append(("\(thumbsFolder)/\(thumb)", Storage.bookmarkThumbURL(thumb)))
                }
            }
            if comic.archiveIncluded {
                payload.append(("\(comicsFolder)/\(comic.fileName)", Storage.comicURL(comic.fileName)))
            }
        }

        // The zip is a full second copy of every owned archive, so a device without room for that
        // finds out now, not as a backup that looks finished and is missing comics.
        let needed = payload.reduce(Int64(0)) { sum, item in
            sum + Int64((try? item.file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        if let free = freeSpace(at: workspace), free < needed + 10 * 1024 * 1024 {
            try? Storage.fm.removeItem(at: workspace)
            throw BackupError.notEnoughSpace
        }

        let destination = workspace.appendingPathComponent(fileName(at: backup.createdAt))
        let archive: Archive
        do {
            archive = try Archive(url: destination, accessMode: .create)
        } catch {
            try? Storage.fm.removeItem(at: workspace)
            throw BackupError.writeFailed
        }

        let total = payload.count + 1
        let step = max(total / 100, 1)
        func report(_ done: Int) {
            guard done % step == 0 || done == total else { return }
            onProgress(done, total)
        }
        onProgress(0, total)

        do {
            let data = try LibraryBackupCodec.encode(backup)
            try archive.addEntry(with: documentName, type: .file,
                                 uncompressedSize: Int64(data.count),
                                 compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        } catch {
            throw writeFailure(error, discarding: workspace)
        }
        report(1)

        for (index, item) in payload.enumerated() {
            // A file that has gone missing since the document was built is skipped rather than
            // fatal. The entry still restores; it just comes back without that one picture, which
            // is a far better outcome than refusing to back up the library at all.
            //
            // A file that is there and still won't go in is fatal. The document already says the
            // backup carries it, and for an owned copy that may be the only copy there is.
            if Storage.fm.fileExists(atPath: item.file.path) {
                do {
                    // `.none`: JPEGs and CBZs are already compressed, so deflating them again
                    // spends real time on a library of any size and saves close to nothing.
                    try archive.addEntry(with: item.path, fileURL: item.file, compressionMethod: .none)
                } catch {
                    throw writeFailure(error, discarding: workspace)
                }
            }
            report(index + 2)
        }
        return destination
    }

    /// Bins a half-written export and says why it failed, telling a full disk apart from the rest.
    private static func writeFailure(_ error: Error, discarding workspace: URL) -> BackupError {
        try? Storage.fm.removeItem(at: workspace)
        if isOutOfSpace(error) { return .notEnoughSpace }
        if let free = freeSpace(at: workspace.deletingLastPathComponent()), free < 10 * 1024 * 1024 {
            return .notEnoughSpace
        }
        return .writeFailed
    }

    /// Removes previous exports, so they don't sit in temp for the life of the install. Best effort:
    /// a directory that won't go (a share sheet still reading it) is left for the next sweep.
    private static func sweepOldExports(in base: URL, keeping current: URL) {
        guard let existing = try? Storage.fm.contentsOfDirectory(at: base,
                                                                includingPropertiesForKeys: nil) else { return }
        for directory in existing where directory.lastPathComponent != current.lastPathComponent {
            try? Storage.fm.removeItem(at: directory)
        }
    }

    /// "Paper Comic Library 2026-07-30.zip" — dated, because the natural thing to do with these is
    /// to keep the last few. Fixed locale so the name doesn't depend on the device's region.
    private static func fileName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Paper Comic Library \(formatter.string(from: date)).zip"
    }

    // MARK: Import

    /// An unpacked backup, and where its files are sitting while they're read.
    ///
    /// A handle rather than a plain value, because the files are in a temp directory that has to
    /// outlive the read and then be cleaned up: the caller applies the document to the store,
    /// pulling the files it needs, and calls `discard()` when it's done.
    struct Unpacked {
        let backup: LibraryBackup
        let root: URL

        func coverURL(_ name: String) -> URL {
            root.appendingPathComponent(coversFolder).appendingPathComponent(name)
        }

        func thumbURL(_ name: String) -> URL {
            root.appendingPathComponent(thumbsFolder).appendingPathComponent(name)
        }

        func archiveURL(_ fileName: String) -> URL {
            root.appendingPathComponent(comicsFolder).appendingPathComponent(fileName)
        }

        func discard() {
            try? Storage.fm.removeItem(at: root)
        }
    }

    /// Unpacks the backup at `url`. The caller must `discard()` the result.
    ///
    /// `url` comes from the file picker and is security-scoped. Off the main actor.
    static func read(at url: URL) throws -> Unpacked {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Looked into before anything is unpacked. Anything that isn't a zip, or is a zip with no
        // document in it (most likely a CBZ, the other kind of zip this reader has to hand), is
        // the wrong file rather than a corrupt backup, so say the useful thing, and say it before
        // a CBZ of a few hundred megabytes has been unpacked for nothing.
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw BackupError.notABackup
        }
        guard archive[documentName] != nil else { throw BackupError.notABackup }
        let root = Storage.fm.temporaryDirectory
            .appendingPathComponent("LibraryRestore-\(UUID().uuidString)", isDirectory: true)
        // From here on it IS a backup, so a failure is never "the wrong file": telling someone
        // that about their genuine backup could get it deleted.
        let needed = archive.reduce(Int64(0)) { $0 + Int64(clamping: $1.uncompressedSize) }
        if let free = freeSpace(at: Storage.fm.temporaryDirectory), free < needed + 10 * 1024 * 1024 {
            throw BackupError.notEnoughSpace
        }
        do {
            try Storage.fm.createDirectory(at: root, withIntermediateDirectories: true)
            try Storage.fm.unzipItem(at: url, to: root)
        } catch {
            try? Storage.fm.removeItem(at: root)
            throw isOutOfSpace(error) ? BackupError.notEnoughSpace : BackupError.unreadable
        }

        let documentURL = root.appendingPathComponent(documentName)
        guard let data = try? Data(contentsOf: documentURL),
              let backup = try? LibraryBackupCodec.decode(data) else {
            try? Storage.fm.removeItem(at: root)
            throw BackupError.unreadable
        }
        guard backup.version <= LibraryBackup.currentVersion else {
            try? Storage.fm.removeItem(at: root)
            throw BackupError.fromNewerVersion
        }
        guard backup.comics.allSatisfy(hasPlainFileNames) else {
            try? Storage.fm.removeItem(at: root)
            throw BackupError.unreadable
        }
        return Unpacked(backup: backup, root: root)
    }

    /// The document's file names end up as paths in Storage, and deleting a comic later removes
    /// whatever they point at. A name that reaches outside its folder ("../default.store") can
    /// only come from a tampered file, so the whole backup is refused.
    private static func hasPlainFileNames(_ comic: LibraryBackup.Comic) -> Bool {
        let names = [comic.fileName, comic.coverName].compactMap { $0 }
            + comic.bookmarks.compactMap(\.thumbName)
        return names.allSatisfy(isPlainFileName)
    }

    static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\0")
            && (name as NSString).lastPathComponent == name
    }
}

// MARK: - Free space

extension LibraryBackupArchive {

    /// Bytes free on the volume holding `url`, or nil when the system won't say.
    static func freeSpace(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                       .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 {
            return important
        }
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    static func isOutOfSpace(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileWriteOutOfSpaceError { return true }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOSPC) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            return isOutOfSpace(underlying)
        }
        return false
    }
}

// MARK: - Codec

enum LibraryBackupCodec {

    /// ISO-8601 dates and sorted keys. The document is small next to the archives beside it, it is
    /// read by future versions of this app, and it should stay legible to a human working out why
    /// a restore did what it did.
    static func encode(_ backup: LibraryBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> LibraryBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryBackup.self, from: data)
    }
}
