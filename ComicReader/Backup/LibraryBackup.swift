//
//  LibraryBackup.swift
//  Comic Reader
//
//  The backup document: everything the library knows, as one JSON file.
//
//  What travels and what doesn't, and why:
//
//   - Every entry, with its ComicInfo metadata, reading progress, flags, open count and
//     bookmarks. All of it, because the point of a backup is that nothing has to be rebuilt
//     by hand afterwards.
//   - Covers and bookmark thumbnails, as files alongside. They are small, and a restored
//     library without them is a grid of grey rectangles.
//   - The CBZ archives of OWNED copies only: comics imported straight in, which have no other
//     source anywhere. A folder-backed comic keeps its relative path instead and fetches its
//     own bytes from the comic folder, exactly as it always did, so a library of a thousand
//     folder comics still exports as a small file.
//

import Foundation

/// A whole library, at one moment.
struct LibraryBackup: Codable, Sendable {

    /// Bumped only for a change an older build couldn't read correctly. An import refuses a
    /// version from the future rather than half-understanding it.
    static let currentVersion = 1

    var version: Int = currentVersion
    var createdAt: Date
    /// "Ulf's iPad" — shown when confirming an import, so it is clear which library is about to
    /// be merged in. Never matched on.
    var deviceName: String
    var comics: [Comic]

    struct Comic: Codable, Sendable, Equatable {

        // MARK: Identity and files

        /// The file name the archive takes in local storage. Reused verbatim on import when the
        /// archive travelled with the backup, so the entry and its bytes stay in step.
        var fileName: String
        /// The comic's path inside the library folder, or nil for an owned copy. Both the identity
        /// an import matches on and the instruction "fetch this yourself".
        var sourceRelativePath: String?
        /// Whether `comics/<fileName>` is in the package. False for every folder-backed comic, and
        /// for an owned copy whose archive had gone missing before the export ran.
        var archiveIncluded: Bool

        var title: String
        var pageCount: Int
        var dateAdded: Date
        var coverName: String?
        var coverAspect: Double?

        // MARK: Reading state

        var lastReadPage: Int
        var dateOpened: Date?
        var openCount: Int
        var isRead: Bool
        var isFavorite: Bool

        // MARK: ComicInfo
        //
        // Carried rather than re-read from the archive, because on import the archive may not be
        // there to read: a folder-backed comic restores as an entry long before its bytes arrive,
        // and a bare file name is a poor thing to show in the meantime. `metadataScanned` travels
        // too, so a comic that was checked and found untagged isn't re-opened on every launch to
        // learn the same thing again.

        var metadataScanned: Bool
        var series: String?
        var issueNumber: String?
        var issueTitle: String?
        var summary: String?
        var publisher: String?
        var year: Int?
        var month: Int?
        var day: Int?
        var writers: String?
        var pencillers: String?
        var inkers: String?
        var characters: String?
        var languageISO: String?
        var webURL: String?
        var notes: String?
        var stories: [ComicStory]

        var bookmarks: [Bookmark]
    }

    /// One bookmarked page. Identified by `pageIndex` alone: a bookmark IS "this page of this
    /// comic", so an import can tell whether the target library already has it without needing
    /// any id to have survived the trip.
    struct Bookmark: Codable, Sendable, Equatable {
        var pageIndex: Int
        var dateAdded: Date
        var pageAspect: Double?
        var thumbName: String?

        // The story assignment, denormalised exactly as `Bookmark` stores it. See the long note
        // there for why all three fields travel together rather than one reference.
        var storyTitle: String?
        var storyIndex: Int?
        var storyCode: String?
    }
}

// MARK: - Matching an existing library

/// How a backup entry is recognised as a comic the target library already has.
///
/// There is no shared id to lean on: `ComicBook.id` is minted locally at import, so the same file
/// imported on two devices carries two different ones, and reusing the backup's id would collide
/// with a real entry on a library that grew independently. So identity comes from what the two
/// libraries genuinely share:
///
///  - a folder-backed comic has `sourceRelativePath`, the path inside the comic folder both
///    devices point at;
///  - an owned copy has only its file name and page count. That matches the ordinary case, and it
///    fails safe: a wrong match would need two different comics to agree on both.
enum BackupComicKey: Hashable {
    case folder(String)
    case owned(title: String, pageCount: Int)

    static func key(sourceRelativePath: String?, title: String, pageCount: Int) -> BackupComicKey {
        if let path = sourceRelativePath?.nonEmpty { return .folder(path) }
        // Folded, because the same file reached the two libraries by different routes and only the
        // reader thinks of them as one name.
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
        return .owned(title: folded, pageCount: pageCount)
    }

    static func key(for comic: LibraryBackup.Comic) -> BackupComicKey {
        key(sourceRelativePath: comic.sourceRelativePath,
            title: comic.title, pageCount: comic.pageCount)
    }

    @MainActor static func key(for book: ComicBook) -> BackupComicKey {
        key(sourceRelativePath: book.sourceRelativePath,
            title: book.title, pageCount: book.pageCount)
    }
}
