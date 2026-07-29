//
//  LibraryBackupTests.swift
//  ComicReaderTests
//
//  Exercises the real thing: a library is captured, zipped, unzipped and restored into a fresh
//  store, with actual files on disk. The packaging is where a backup quietly goes wrong — a cover
//  that didn't travel, an archive claimed but not carried, a bookmark dropped on restore — and none
//  of that shows up in a test that stops at the document.
//
//  Also pins the two restore rules that were chosen over plausible alternatives: the backup wins on
//  reading progress (that is what restoring means), and it can never remove a bookmark.
//

import XCTest
import SwiftData
import ZIPFoundation
@testable import ComicReader

@MainActor
final class LibraryBackupTests: XCTestCase {

    /// Everything written into the app's real Storage during a test, removed afterwards.
    private var written: [URL] = []

    override func tearDownWithError() throws {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
    }

    // MARK: Fixtures

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ComicBook.self, Bookmark.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// An owned copy with a real archive and cover on disk, as a manual import leaves it.
    private func insertOwned(_ context: ModelContext,
                             title: String = "Topolino 1900",
                             pageCount: Int = 30) -> ComicBook {
        let id = UUID()
        let fileName = "\(id.uuidString).cbz"
        let coverName = "\(id.uuidString).jpg"
        write(Data("archive bytes".utf8), to: Storage.comicURL(fileName))
        write(Data("cover bytes".utf8), to: Storage.coverURL(coverName))

        let book = ComicBook(id: id, title: title, fileName: fileName,
                             pageCount: pageCount, coverName: coverName, coverAspect: 0.66)
        context.insert(book)
        return book
    }

    /// A folder-backed comic that was listed by a scan and never downloaded.
    private func insertFolderComic(_ context: ModelContext,
                                   relativePath: String = "Topolino/1901.cbz",
                                   title: String = "Topolino 1901",
                                   pageCount: Int = 40) -> ComicBook {
        let book = ComicBook(title: title, fileName: "\(UUID().uuidString).cbz",
                             pageCount: pageCount, coverName: nil)
        book.sourceRelativePath = relativePath
        book.hasLocalArchive = false
        context.insert(book)
        return book
    }

    @discardableResult
    private func addBookmark(_ context: ModelContext, to book: ComicBook,
                             page: Int, story: String? = nil) -> Bookmark {
        let thumbName = "\(UUID().uuidString).jpg"
        write(Data("thumb bytes".utf8), to: Storage.bookmarkThumbURL(thumbName))
        let bookmark = Bookmark(pageIndex: page, thumbName: thumbName, pageAspect: 0.7, book: book)
        bookmark.storyTitle = story
        context.insert(bookmark)
        return bookmark
    }

    private func write(_ data: Data, to url: URL) {
        try? data.write(to: url)
        written.append(url)
    }

    /// Captures, packages, unpacks. The temp package is registered for cleanup along with
    /// everything else the test wrote.
    private func roundTrip(_ books: [ComicBook]) throws -> LibraryBackupArchive.Unpacked {
        let backup = LibraryBackupStore.capture(from: books)
        let file = try LibraryBackupArchive.write(backup) { _, _ in }
        written.append(file.deletingLastPathComponent())
        let unpacked = try LibraryBackupArchive.read(at: file)
        written.append(unpacked.root)
        return unpacked
    }

    // MARK: Round trip

    /// The whole point, end to end: a library goes out through the zip and comes back into an empty
    /// store with its progress, flags, metadata, bookmarks and files intact.
    func testOwnedComicSurvivesAFullRoundTrip() throws {
        let source = try makeContext()
        let book = insertOwned(source)
        book.lastReadPage = 17
        book.openCount = 4
        book.isFavorite = true
        book.isRead = true
        book.series = "Topolino"
        book.issueNumber = "1900"
        book.metadataScanned = true
        addBookmark(source, to: book, page: 12, story: "Zio Paperone")

        let unpacked = try roundTrip([book])
        let target = try makeContext()
        let report = LibraryBackupStore.restore(unpacked, into: target)

        XCTAssertEqual(report.comicsAdded, 1)
        XCTAssertEqual(report.bookmarksAdded, 1)
        XCTAssertEqual(report.comicsWithoutArchive, 0)

        let restored = try XCTUnwrap(target.fetch(FetchDescriptor<ComicBook>()).first)
        XCTAssertEqual(restored.title, "Topolino 1900")
        XCTAssertEqual(restored.lastReadPage, 17)
        XCTAssertEqual(restored.openCount, 4)
        XCTAssertTrue(restored.isFavorite)
        XCTAssertTrue(restored.isRead)
        XCTAssertEqual(restored.series, "Topolino")
        XCTAssertEqual(restored.issueNumber, "1900")
        XCTAssertTrue(restored.metadataScanned)
        XCTAssertEqual(restored.bookmarks.map(\.pageIndex), [12])
        XCTAssertEqual(restored.bookmarks.first?.storyTitle, "Zio Paperone")

        // The archive is the part only a backup can carry for an owned copy.
        XCTAssertTrue(restored.hasLocalArchive)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.archiveURL.path))
        XCTAssertNotNil(restored.coverURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(restored.coverURL).path))
    }

    /// A folder comic travels as a reference. Its bytes stay in the comic folder, which is what
    /// keeps a backup of a thousand folder comics small — and it comes back un-downloaded, which is
    /// a normal state for one rather than a loss.
    func testFolderComicTravelsAsAReference() throws {
        let source = try makeContext()
        let book = insertFolderComic(source)
        book.lastReadPage = 9

        let backup = LibraryBackupStore.capture(from: [book])
        XCTAssertEqual(backup.comics.count, 1)
        XCTAssertFalse(backup.comics[0].archiveIncluded, "a folder comic must not carry its bytes")
        XCTAssertEqual(backup.comics[0].sourceRelativePath, "Topolino/1901.cbz")

        let unpacked = try roundTrip([book])
        let target = try makeContext()
        LibraryBackupStore.restore(unpacked, into: target)

        let restored = try XCTUnwrap(target.fetch(FetchDescriptor<ComicBook>()).first)
        XCTAssertEqual(restored.sourceRelativePath, "Topolino/1901.cbz")
        XCTAssertEqual(restored.lastReadPage, 9)
        XCTAssertFalse(restored.hasLocalArchive)
        XCTAssertTrue(restored.isRemote, "it should be re-fetchable, not broken")
    }

    /// An owned copy whose archive went missing before the export is reported honestly rather than
    /// claimed and then found absent on the far side.
    func testMissingArchiveIsNotClaimed() throws {
        let source = try makeContext()
        let book = insertOwned(source)
        try FileManager.default.removeItem(at: book.archiveURL)

        let backup = LibraryBackupStore.capture(from: [book])
        XCTAssertFalse(backup.comics[0].archiveIncluded)

        let unpacked = try roundTrip([book])
        let target = try makeContext()
        let report = LibraryBackupStore.restore(unpacked, into: target)
        XCTAssertEqual(report.comicsWithoutArchive, 1)
        XCTAssertFalse(try XCTUnwrap(target.fetch(FetchDescriptor<ComicBook>()).first).hasLocalArchive)
    }

    // MARK: Restoring onto a library that already has things

    /// The backup wins on reading progress. That is what restoring one means, and it is why the
    /// outcome is predictable instead of depending on which side happens to look newer.
    func testRestoreOverwritesProgressOnAnExistingComic() throws {
        let source = try makeContext()
        let original = insertOwned(source)
        original.lastReadPage = 25
        original.isRead = true
        let unpacked = try roundTrip([original])

        // A library where the same comic sits at a different page.
        let target = try makeContext()
        let mine = ComicBook(title: original.title, fileName: "other.cbz",
                             pageCount: original.pageCount, coverName: nil)
        mine.lastReadPage = 3
        target.insert(mine)

        let report = LibraryBackupStore.restore(unpacked, into: target)
        XCTAssertEqual(report.comicsAdded, 0, "same file name and page count is the same comic")
        XCTAssertEqual(report.comicsUpdated, 1)
        XCTAssertEqual(mine.lastReadPage, 25)
        XCTAssertTrue(mine.isRead)
    }

    /// The one exception to "the backup wins": bookmarks are added, never removed. A bookmark is set
    /// by hand one at a time, and restoring an old backup must not be the thing that takes one away.
    func testRestoreNeverRemovesABookmark() throws {
        let source = try makeContext()
        let original = insertOwned(source)
        addBookmark(source, to: original, page: 5)
        let unpacked = try roundTrip([original])

        let target = try makeContext()
        let mine = ComicBook(title: original.title, fileName: "other.cbz",
                             pageCount: original.pageCount, coverName: nil)
        target.insert(mine)
        addBookmark(target, to: mine, page: 20)   // not in the backup

        LibraryBackupStore.restore(unpacked, into: target)
        XCTAssertEqual(mine.bookmarks.map(\.pageIndex).sorted(), [5, 20])
    }

    /// A story picked here is not overwritten by the backup's, but an empty one is filled in.
    func testStoryAssignmentFillsInButNeverOverwrites() throws {
        let source = try makeContext()
        let original = insertOwned(source)
        addBookmark(source, to: original, page: 5, story: "From the backup")
        let unpacked = try roundTrip([original])

        let target = try makeContext()
        let mine = ComicBook(title: original.title, fileName: "other.cbz",
                             pageCount: original.pageCount, coverName: nil)
        target.insert(mine)
        addBookmark(target, to: mine, page: 5, story: "Mine")
        addBookmark(target, to: mine, page: 6)

        LibraryBackupStore.restore(unpacked, into: target)
        XCTAssertEqual(mine.bookmarks.first { $0.pageIndex == 5 }?.storyTitle, "Mine")
    }

    /// Restoring the same backup twice must change nothing the second time.
    func testRestoreIsIdempotent() throws {
        let source = try makeContext()
        let original = insertOwned(source)
        original.lastReadPage = 11
        addBookmark(source, to: original, page: 4)
        let unpacked = try roundTrip([original])

        let target = try makeContext()
        let first = LibraryBackupStore.restore(unpacked, into: target)
        let second = LibraryBackupStore.restore(unpacked, into: target)

        XCTAssertEqual(first.comicsAdded, 1)
        XCTAssertEqual(second.comicsAdded, 0)
        XCTAssertEqual(second.bookmarksAdded, 0)
        XCTAssertEqual(try target.fetch(FetchDescriptor<ComicBook>()).count, 1)
        let restored = try XCTUnwrap(target.fetch(FetchDescriptor<ComicBook>()).first)
        XCTAssertEqual(restored.bookmarks.count, 1)
        XCTAssertEqual(restored.lastReadPage, 11)
    }

    /// Two local comics sharing an identity are left alone entirely. Writing one comic's progress
    /// and bookmarks onto both would be a quiet, permanent mix-up; not restoring them is not.
    func testAmbiguousIdentityIsSkipped() throws {
        let source = try makeContext()
        let original = insertOwned(source, title: "Annual", pageCount: 30)
        original.lastReadPage = 25
        let unpacked = try roundTrip([original])

        let target = try makeContext()
        let a = ComicBook(title: "Annual", fileName: "a.cbz", pageCount: 30, coverName: nil)
        let b = ComicBook(title: "Annual", fileName: "b.cbz", pageCount: 30, coverName: nil)
        target.insert(a)
        target.insert(b)

        let report = LibraryBackupStore.restore(unpacked, into: target)
        XCTAssertEqual(report.comicsUpdated, 0)
        XCTAssertEqual(report.comicsAdded, 0)
        XCTAssertEqual(a.lastReadPage, 0)
        XCTAssertEqual(b.lastReadPage, 0)
    }

    /// The backup can describe a LONGER copy of the same comic than this device has, and the page it
    /// remembers must be clamped to the pages that actually exist here.
    ///
    /// A folder comic is the case where this really happens: it is identified by its path inside the
    /// comic folder, so re-tagging the archive with the ads cut out leaves it the same comic while
    /// making it shorter. An owned copy can't reach this state, because its page count is part of its
    /// identity and a changed count simply reads as a different comic.
    func testProgressBeyondThisCopysEndIsClamped() throws {
        let source = try makeContext()
        let original = insertFolderComic(source, relativePath: "Topolino/1901.cbz", pageCount: 40)
        original.lastReadPage = 39
        addBookmark(source, to: original, page: 38)
        let unpacked = try roundTrip([original])

        // The same folder path, but this device's copy has been re-tagged down to 10 pages.
        let target = try makeContext()
        let mine = insertFolderComic(target, relativePath: "Topolino/1901.cbz", pageCount: 10)

        let report = LibraryBackupStore.restore(unpacked, into: target)
        XCTAssertEqual(report.comicsUpdated, 1, "the folder path is the identity, so this is a match")
        XCTAssertEqual(mine.lastReadPage, 9, "clamped to this copy's last page, not the backup's")
        XCTAssertTrue(mine.bookmarks.isEmpty, "a page this copy doesn't have can't be bookmarked")
    }

    // MARK: Rejecting the wrong file

    func testACbzIsNotABackup() throws {
        // A CBZ is a zip too, and it is the other kind of file this reader has to hand.
        let notABackup = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        let archive = try Archive(url: notABackup, accessMode: .create)
        let page = Data("page".utf8)
        try archive.addEntry(with: "page1.jpg", type: .file,
                            uncompressedSize: Int64(page.count)) { position, size in
            page.subdata(in: Int(position)..<Int(position) + size)
        }
        written.append(notABackup)

        XCTAssertThrowsError(try LibraryBackupArchive.read(at: notABackup)) { error in
            XCTAssertEqual(error as? LibraryBackupArchive.BackupError, .notABackup)
        }
    }

    func testAFutureVersionIsRefused() throws {
        let source = try makeContext()
        var backup = LibraryBackupStore.capture(from: [insertOwned(source)])
        backup.version = LibraryBackup.currentVersion + 1
        let file = try LibraryBackupArchive.write(backup) { _, _ in }
        written.append(file.deletingLastPathComponent())

        XCTAssertThrowsError(try LibraryBackupArchive.read(at: file)) { error in
            XCTAssertEqual(error as? LibraryBackupArchive.BackupError, .fromNewerVersion)
        }
    }
}
