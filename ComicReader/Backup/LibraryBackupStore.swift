//
//  LibraryBackupStore.swift
//  Comic Reader
//
//  Reading a backup out of the library, and writing one back into it. Main-actor throughout,
//  because that is where SwiftData models live; everything slow (zipping, unzipping, copying
//  archives) happens on either side of this, never inside it.
//

import Foundation
import SwiftData

@MainActor
enum LibraryBackupStore {

    // MARK: Capture

    /// The library as a backup document.
    ///
    /// An owned copy's archive is only marked as included when the file is genuinely on disk. That
    /// is a real case rather than paranoia: a comic can outlive its archive (a failed import, a
    /// restore where the bytes never travelled), and claiming to carry a file that isn't there
    /// would make the import report a missing archive as corruption.
    static func capture(from books: [ComicBook], at date: Date = .now) -> LibraryBackup {
        LibraryBackup(createdAt: date,
                      deviceName: BackupDevice.name,
                      comics: books.map(comic(for:)))
    }

    private static func comic(for book: ComicBook) -> LibraryBackup.Comic {
        let carriesArchive = !book.isFolderBacked
            && Storage.fm.fileExists(atPath: book.archiveURL.path)
        return LibraryBackup.Comic(
            fileName: book.fileName,
            sourceRelativePath: book.sourceRelativePath,
            archiveIncluded: carriesArchive,
            title: book.title,
            pageCount: book.pageCount,
            dateAdded: book.dateAdded,
            coverName: book.coverName,
            coverAspect: book.coverAspect,
            lastReadPage: book.lastReadPage,
            dateOpened: book.dateOpened,
            openCount: book.openCount,
            isRead: book.isRead,
            isFavorite: book.isFavorite,
            metadataScanned: book.metadataScanned,
            series: book.series,
            issueNumber: book.issueNumber,
            issueTitle: book.issueTitle,
            summary: book.summary,
            publisher: book.publisher,
            year: book.year,
            month: book.month,
            day: book.day,
            writers: book.writers,
            pencillers: book.pencillers,
            inkers: book.inkers,
            characters: book.characters,
            languageISO: book.languageISO,
            webURL: book.webURL,
            notes: book.notes,
            stories: book.stories,
            bookmarks: book.bookmarks
                .sorted { $0.pageIndex < $1.pageIndex }
                .map { bookmark in
                    LibraryBackup.Bookmark(pageIndex: bookmark.pageIndex,
                                           dateAdded: bookmark.dateAdded,
                                           pageAspect: bookmark.pageAspect,
                                           thumbName: bookmark.thumbName,
                                           storyTitle: bookmark.storyTitle,
                                           storyIndex: bookmark.storyIndex,
                                           storyCode: bookmark.storyCode)
                })
    }

    // MARK: Restore

    struct Report: Equatable {
        var comicsAdded = 0
        var comicsUpdated = 0
        var bookmarksAdded = 0
        /// Entries that came back without their bytes and have no comic folder to fetch from, so
        /// they can't be opened yet. Counted rather than hidden: this is the one thing a restore
        /// can't fix on its own, and the reader needs to know to re-import those files.
        var comicsWithoutArchive = 0

        var isEmpty: Bool { comicsAdded == 0 && comicsUpdated == 0 && bookmarksAdded == 0 }
    }

    /// Copies every file the backup carries into local storage.
    ///
    /// Split out of `restore` and deliberately NOT main-actor. `restore` writes SwiftData models, so
    /// it has to run on the main actor; copying archives does not, and a backup carrying a few
    /// hundred megabytes of comics would freeze the app for the length of the copy if the two were
    /// one step. So the bytes move first, off-main, and then the models are written in a pass that
    /// only ever checks whether a file arrived.
    ///
    /// Nothing is overwritten. Every name here is UUID-based, so a file already at that path IS the
    /// same file, and re-copying it would only cost time.
    nonisolated static func installFiles(from unpacked: LibraryBackupArchive.Unpacked) {
        for comic in unpacked.backup.comics {
            if let cover = comic.coverName {
                copy(unpacked.coverURL(cover), to: Storage.coverURL(cover))
            }
            for bookmark in comic.bookmarks {
                guard let thumb = bookmark.thumbName else { continue }
                copy(unpacked.thumbURL(thumb), to: Storage.bookmarkThumbURL(thumb))
            }
            if comic.archiveIncluded {
                copy(unpacked.archiveURL(comic.fileName), to: Storage.comicURL(comic.fileName))
            }
        }
    }

    /// Applies an unpacked backup to the library.
    ///
    /// Expects `installFiles` to have run first: this pass never copies anything, it only asks
    /// whether a file made it, so it stays quick enough for the main actor.
    ///
    /// Deliberately simple and predictable, because importing a backup is a deliberate act and the
    /// reader should be able to say in one sentence what it did:
    ///
    ///  - a comic the library doesn't have is **created**, with everything the backup knows;
    ///  - a comic it already has has its reading state **overwritten** from the backup. The file
    ///    wins. That is the whole point of restoring one, and it is what makes the outcome
    ///    predictable rather than depending on which side happens to be newer;
    ///  - bookmarks are **unioned, never removed**. This is the one exception to "the file wins",
    ///    and it is deliberate: a bookmark is set by hand one at a time, and the library's
    ///    stability tests already guard that nothing incidental can take one away. Restoring an
    ///    old backup must not be the thing that finally does.
    @discardableResult
    static func restore(_ unpacked: LibraryBackupArchive.Unpacked,
                        into context: ModelContext) -> Report {
        var report = Report()

        var byKey: [BackupComicKey: [ComicBook]] = [:]
        for book in fetchBooks(in: context) {
            byKey[BackupComicKey.key(for: book), default: []].append(book)
        }

        for comic in unpacked.backup.comics {
            let key = BackupComicKey.key(for: comic)
            // A key held by more than one local comic is left alone entirely. Two owned copies that
            // share a file name and page count can't be told apart by anything here, and writing
            // one comic's progress and bookmarks onto both would be a quiet, permanent mix-up —
            // much worse than those two not restoring until one is renamed.
            let matches = byKey[key] ?? []
            guard matches.count <= 1 else { continue }

            if let existing = matches.first {
                let added = update(existing, from: comic, in: context)
                report.comicsUpdated += 1
                report.bookmarksAdded += added
                if existing.isRemote == false, existing.hasLocalArchive == false {
                    report.comicsWithoutArchive += 1
                }
            } else {
                let book = create(comic, from: unpacked, in: context)
                byKey[key] = [book]
                report.comicsAdded += 1
                report.bookmarksAdded += book.bookmarks.count
                if !book.isFolderBacked && !book.hasLocalArchive {
                    report.comicsWithoutArchive += 1
                }
            }
        }
        try? context.save()
        return report
    }

    nonisolated private static func copy(_ source: URL, to destination: URL) {
        guard !Storage.fm.fileExists(atPath: destination.path),
              Storage.fm.fileExists(atPath: source.path) else { return }
        try? Storage.fm.copyItem(at: source, to: destination)
    }

    /// Creates a comic that isn't in the library yet. `unpacked` is only consulted for what arrived,
    /// never copied from — `installFiles` did that already.
    private static func create(_ comic: LibraryBackup.Comic,
                               from unpacked: LibraryBackupArchive.Unpacked,
                               in context: ModelContext) -> ComicBook {
        let book = ComicBook(title: comic.title,
                             fileName: comic.fileName,
                             pageCount: comic.pageCount,
                             // Only claim a cover that actually arrived, so a restored grid shows
                             // its placeholder rather than an empty frame.
                             coverName: comic.coverName.flatMap {
                                 Storage.fm.fileExists(atPath: Storage.coverURL($0).path) ? $0 : nil
                             },
                             coverAspect: comic.coverAspect)
        book.dateAdded = comic.dateAdded
        book.sourceRelativePath = comic.sourceRelativePath
        context.insert(book)

        // Whether the archive actually landed. A folder-backed comic restores without one on
        // purpose: not being downloaded is a normal state for it, and it fetches on open. For an
        // owned copy this is the difference between a comic and an entry that can't be opened, so
        // it is read off the file system rather than trusted from the document.
        book.hasLocalArchive = comic.archiveIncluded
            && Storage.fm.fileExists(atPath: Storage.comicURL(comic.fileName).path)

        apply(comic, to: book)
        applyMetadata(comic, to: book)
        addBookmarks(comic.bookmarks, to: book, in: context)
        return book
    }

    /// Overwrites an existing comic's reading state from the backup, and returns how many bookmarks
    /// were added. Metadata is written too, but the archive is NOT: a comic already in this library
    /// has its own bytes (or its own folder to fetch them from), and replacing them from a backup
    /// would risk swapping a good archive for a stale one.
    private static func update(_ book: ComicBook, from comic: LibraryBackup.Comic,
                               in context: ModelContext) -> Int {
        apply(comic, to: book)
        applyMetadata(comic, to: book)
        // Fill in a cover only where there wasn't one, for the same reason: what's here already is
        // at least as good as what the backup carries.
        if book.coverName == nil, let cover = comic.coverName,
           Storage.fm.fileExists(atPath: Storage.coverURL(cover).path) {
            book.coverName = cover
            book.coverAspect = comic.coverAspect
        }
        return addBookmarks(comic.bookmarks, to: book, in: context)
    }

    private static func apply(_ comic: LibraryBackup.Comic, to book: ComicBook) {
        // Clamped against the pages THIS copy has, not the pages the backup thinks it has. The two
        // can differ: a folder-backed comic is identified by its path, so a re-tagged archive with
        // the ads cut out is still the same comic while being shorter than the backup remembers.
        // Clamping against the backup's own count would then write a page past this copy's end and
        // open the reader on nothing.
        book.lastReadPage = min(max(comic.lastReadPage, 0), max(book.pageCount - 1, 0))
        book.dateOpened = comic.dateOpened
        book.openCount = comic.openCount
        book.isRead = comic.isRead
        book.isFavorite = comic.isFavorite
    }

    private static func applyMetadata(_ comic: LibraryBackup.Comic, to book: ComicBook) {
        book.metadataScanned = comic.metadataScanned
        book.series = comic.series
        book.issueNumber = comic.issueNumber
        book.issueTitle = comic.issueTitle
        book.summary = comic.summary
        book.publisher = comic.publisher
        book.year = comic.year
        book.month = comic.month
        book.day = comic.day
        book.writers = comic.writers
        book.pencillers = comic.pencillers
        book.inkers = comic.inkers
        book.characters = comic.characters
        book.languageISO = comic.languageISO
        book.webURL = comic.webURL
        book.notes = comic.notes
        book.stories = comic.stories
    }

    /// Adds the bookmarks this comic doesn't have, by page. Returns how many were added. Never
    /// removes one, and never overwrites the story assignment on one that's already here.
    @discardableResult
    private static func addBookmarks(_ entries: [LibraryBackup.Bookmark],
                                     to book: ComicBook,
                                     in context: ModelContext) -> Int {
        var byPage = Dictionary(book.bookmarks.map { ($0.pageIndex, $0) },
                                uniquingKeysWith: { first, _ in first })
        var added = 0
        for entry in entries {
            // Same clamp as the resume page, for the same reason: a page this copy doesn't have
            // can't be bookmarked, so it's dropped rather than pointed at nothing.
            guard entry.pageIndex >= 0, entry.pageIndex < book.pageCount else { continue }

            guard let existing = byPage[entry.pageIndex] else {
                let bookmark = Bookmark(
                    pageIndex: entry.pageIndex,
                    // A name that points at nothing is fine: the card renders its placeholder, and
                    // a bookmark without its picture is still the page the reader marked, which is
                    // the part worth keeping.
                    thumbName: entry.thumbName ?? "\(UUID().uuidString).jpg",
                    pageAspect: entry.pageAspect,
                    book: book)
                bookmark.dateAdded = entry.dateAdded
                bookmark.storyTitle = entry.storyTitle
                bookmark.storyIndex = entry.storyIndex
                bookmark.storyCode = entry.storyCode
                context.insert(bookmark)
                byPage[entry.pageIndex] = bookmark
                added += 1
                continue
            }
            if existing.storyTitle?.nonEmpty == nil, entry.storyTitle?.nonEmpty != nil {
                existing.storyTitle = entry.storyTitle
                existing.storyIndex = entry.storyIndex
                existing.storyCode = entry.storyCode
            }
        }
        return added
    }

    private static func fetchBooks(in context: ModelContext) -> [ComicBook] {
        (try? context.fetch(FetchDescriptor<ComicBook>())) ?? []
    }
}

// MARK: - Device name

/// The device's own name, for the backup document.
enum BackupDevice {

    private static let key = "backup.deviceName"

    /// Read from a cache rather than from `UIDevice`, because the document is built on the main
    /// actor but could be captured from anywhere, and `UIDevice.name` is main-actor bound.
    /// `refreshName()` fills the cache at launch.
    static var name: String {
        UserDefaults.standard.string(forKey: key) ?? "This device"
    }

    @MainActor static func refreshName() {
        #if canImport(UIKit)
        let device = UIDevice.current
        UserDefaults.standard.set(device.name.isEmpty ? device.model : device.name, forKey: key)
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
