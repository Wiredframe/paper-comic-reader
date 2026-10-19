//
//  LibrarySnapshot.swift
//  Comic Reader
//
//  A rolling safety copy of the library, written each time the app goes to the background, so a
//  store that can't be opened (see `LibraryStore`) doesn't take the library with it.
//
//  It is the backup document and nothing more: `LibraryBackupStore.capture`, encoded by
//  `LibraryBackupCodec`, at `Application Support/Safety/library.json`. No files travel with it,
//  because the covers, thumbnails and archives never move; what goes with a broken store is only
//  the knowledge of which `<uuid>.cbz` is which comic, and that is exactly what this keeps.
//
//  Two guards, both against the snapshot destroying itself:
//   - nothing is written while a reset is pending, or backgrounding the freshly emptied library
//     would overwrite the one copy that can bring it back;
//   - an empty library never replaces a snapshot that has comics in it.
//

import Foundation
import SwiftData

@MainActor
enum LibrarySnapshot {

    nonisolated static var defaultURL: URL {
        Storage.appSupport
            .appendingPathComponent("Safety", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    enum SaveOutcome: Equatable {
        case written
        case skippedResetPending
        case skippedWouldEmpty
        case failed
    }

    /// Writes the snapshot, unless one of the guards above says no.
    @discardableResult
    static func save(_ books: [ComicBook],
                     to url: URL = defaultURL,
                     resetPending: Bool = LibraryReset.isPending) -> SaveOutcome {
        guard !resetPending else { return .skippedResetPending }
        // Only an empty library pays for reading the old snapshot back.
        if books.isEmpty, let existing = load(from: url), !existing.comics.isEmpty {
            return .skippedWouldEmpty
        }
        do {
            let data = try LibraryBackupCodec.encode(LibraryBackupStore.capture(from: books))
            try Storage.fm.createDirectory(at: url.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
            // Readable from the first unlock on, like the store itself, so a launch in the
            // background can still offer the restore.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return .written
        } catch {
            return .failed
        }
    }

    static func load(from url: URL = defaultURL) -> LibraryBackup? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? LibraryBackupCodec.decode(data)
    }

    /// Rebuilds the library from a snapshot, through the same rules as importing a backup.
    ///
    /// The "unpacked" root is Application Support itself, because that is where the files already
    /// are. `installFiles` must never run on it: it reads `covers/` and `thumbs/` while Storage
    /// writes `Covers/` and `Bookmarks/`, and it is not needed, since `restore` only checks that
    /// each file exists in Storage.
    @discardableResult
    static func restore(_ snapshot: LibraryBackup,
                        into context: ModelContext) -> LibraryBackupStore.Report {
        let unpacked = LibraryBackupArchive.Unpacked(backup: snapshot, root: Storage.appSupport)
        let report = LibraryBackupStore.restore(unpacked, into: context)
        // A folder comic restores as not downloaded, which is right for a backup from another
        // device. Here its download is very likely still sitting on disk under the same name.
        let books = (try? context.fetch(FetchDescriptor<ComicBook>())) ?? []
        for book in books where book.isFolderBacked && !book.hasLocalArchive {
            if Storage.fm.fileExists(atPath: book.archiveURL.path) { book.hasLocalArchive = true }
        }
        try? context.save()
        return report
    }
}
