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

        var errorDescription: String? {
            switch self {
            case .notABackup:       return "That file isn't a Paper Comic library backup."
            case .unreadable:       return "The backup couldn't be read. It may be incomplete."
            case .fromNewerVersion: return "That backup was made by a newer version of the app."
            case .writeFailed:      return "The backup couldn't be written."
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

        let destination = workspace.appendingPathComponent(fileName(at: backup.createdAt))
        guard let archive = try? Archive(url: destination, accessMode: .create) else {
            throw BackupError.writeFailed
        }

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
            throw BackupError.writeFailed
        }
        report(1)

        for (index, item) in payload.enumerated() {
            // A file that has gone missing since the document was built is skipped rather than
            // fatal. The entry still restores; it just comes back without that one picture, which
            // is a far better outcome than refusing to back up the library at all.
            if Storage.fm.fileExists(atPath: item.file.path) {
                // `.none`: JPEGs and CBZs are already compressed, so deflating them again spends
                // real time on a library of any size and saves close to nothing.
                try? archive.addEntry(with: item.path, fileURL: item.file, compressionMethod: .none)
            }
            report(index + 2)
        }
        return destination
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

        let root = Storage.fm.temporaryDirectory
            .appendingPathComponent("LibraryRestore-\(UUID().uuidString)", isDirectory: true)
        do {
            try Storage.fm.createDirectory(at: root, withIntermediateDirectories: true)
            try Storage.fm.unzipItem(at: url, to: root)
        } catch {
            try? Storage.fm.removeItem(at: root)
            // Anything that isn't a zip lands here. Far more likely the wrong file was picked than
            // that a real backup is corrupt, so say the useful thing.
            throw BackupError.notABackup
        }

        let documentURL = root.appendingPathComponent(documentName)
        guard Storage.fm.fileExists(atPath: documentURL.path) else {
            try? Storage.fm.removeItem(at: root)
            // A valid zip with no document in it. Most likely a CBZ, since those are zips too and
            // are the other kind of file this reader has to hand.
            throw BackupError.notABackup
        }
        guard let data = try? Data(contentsOf: documentURL),
              let backup = try? LibraryBackupCodec.decode(data) else {
            try? Storage.fm.removeItem(at: root)
            throw BackupError.unreadable
        }
        guard backup.version <= LibraryBackup.currentVersion else {
            try? Storage.fm.removeItem(at: root)
            throw BackupError.fromNewerVersion
        }
        return Unpacked(backup: backup, root: root)
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
