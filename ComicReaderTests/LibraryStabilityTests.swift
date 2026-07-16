//
//  LibraryStabilityTests.swift
//  ComicReaderTests
//
//  Guards the invariants the folder-backed library rests on — above all that a bookmark, which
//  the user sets by hand, can NEVER be lost by removing a download. Only a full, confirmed delete
//  clears bookmarks; eviction keeps every one, thumbnail and all. These tests exist so a future
//  change to Importer.evictDownload/delete that broke that promise fails loudly here.
//

import XCTest
import SwiftData
@testable import ComicReader

@MainActor
final class LibraryStabilityTests: XCTestCase {

    /// Temp files written into the app's Storage during a test, removed in tearDown.
    private var tempFiles: [URL] = []

    override func tearDownWithError() throws {
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        tempFiles = []
    }

    /// A fresh in-memory store per test — no disk, no bleed between tests.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ComicBook.self, Bookmark.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// A folder-backed, downloaded comic with `n` bookmarks whose thumbnail files really exist on
    /// disk, plus a real archive file — so a test can assert what eviction removes and what it must
    /// not touch.
    @discardableResult
    private func makeDownloadedFolderBook(in context: ModelContext, bookmarks n: Int)
        throws -> (book: ComicBook, thumbs: [URL]) {
        let book = ComicBook(id: UUID(), title: "Test",
                             fileName: "\(UUID().uuidString).cbz", pageCount: 20, coverName: nil)
        book.sourceRelativePath = "Series/Test.cbz"
        book.hasLocalArchive = true
        context.insert(book)

        let archive = book.archiveURL
        FileManager.default.createFile(atPath: archive.path, contents: Data([0x50, 0x4B]))
        tempFiles.append(archive)

        var thumbs: [URL] = []
        for i in 0..<n {
            let thumbName = "\(UUID().uuidString).jpg"
            context.insert(Bookmark(pageIndex: i, thumbName: thumbName, book: book))
            let thumb = Storage.bookmarkThumbURL(thumbName)
            FileManager.default.createFile(atPath: thumb.path, contents: Data([0xFF, 0xD8]))
            tempFiles.append(thumb)
            thumbs.append(thumb)
        }
        try context.save()
        return (book, thumbs)
    }

    // MARK: The core promise — eviction never loses a bookmark

    func testEvictDownloadKeepsBookmarksAndThumbnails() throws {
        let context = try makeContext()
        let (book, thumbs) = try makeDownloadedFolderBook(in: context, bookmarks: 3)
        XCTAssertEqual(book.bookmarks.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: book.archiveURL.path))

        Importer.evictDownload(book, from: context)

        // The bytes are gone and the flags reflect it…
        XCTAssertFalse(FileManager.default.fileExists(atPath: book.archiveURL.path))
        XCTAssertFalse(book.hasLocalArchive)
        XCTAssertTrue(book.isRemote)

        // …but every bookmark survives, in memory AND after a fresh fetch from the store…
        XCTAssertEqual(book.bookmarks.count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Bookmark>()).count, 3)

        // …and so does every bookmark thumbnail on disk.
        for thumb in thumbs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: thumb.path),
                          "eviction must not delete bookmark thumbnails")
        }
    }

    func testEvictThenReDownloadKeepsSameBookmarks() throws {
        let context = try makeContext()
        let (book, _) = try makeDownloadedFolderBook(in: context, bookmarks: 2)
        let ids = Set(book.bookmarks.map(\.id))
        let pages = Set(book.bookmarks.map(\.pageIndex))

        Importer.evictDownload(book, from: context)
        XCTAssertTrue(book.isRemote)
        XCTAssertEqual(book.bookmarks.count, 2)

        // A re-download lands the bytes back at the same archive URL (same id/fileName).
        FileManager.default.createFile(atPath: book.archiveURL.path, contents: Data([0x50, 0x4B]))
        tempFiles.append(book.archiveURL)
        book.hasLocalArchive = true
        try context.save()

        XCTAssertFalse(book.isRemote)
        XCTAssertEqual(Set(book.bookmarks.map(\.id)), ids, "same bookmarks after re-download")
        XCTAssertEqual(Set(book.bookmarks.map(\.pageIndex)), pages)
    }

    // MARK: A full delete DOES clear them (the deliberate, confirmed path)

    func testDeleteCascadesBookmarksAndRemovesThumbnails() throws {
        let context = try makeContext()
        let (book, thumbs) = try makeDownloadedFolderBook(in: context, bookmarks: 2)

        Importer.delete(book, from: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<ComicBook>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Bookmark>()).isEmpty,
                      "a full delete cascades bookmarks")
        for thumb in thumbs {
            XCTAssertFalse(FileManager.default.fileExists(atPath: thumb.path),
                           "a full delete removes bookmark thumbnails")
        }
    }

    // MARK: Availability state

    func testAvailabilityFlags() throws {
        let context = try makeContext()

        let owned = ComicBook(id: UUID(), title: "Owned", fileName: "a.cbz", pageCount: 1, coverName: nil)
        context.insert(owned)
        XCTAssertFalse(owned.isFolderBacked)
        XCTAssertFalse(owned.isRemote, "an owned copy is never remote")

        let remote = ComicBook(id: UUID(), title: "Remote", fileName: "b.cbz", pageCount: 1, coverName: nil)
        remote.sourceRelativePath = "b.cbz"
        remote.hasLocalArchive = false
        context.insert(remote)
        XCTAssertTrue(remote.isFolderBacked)
        XCTAssertTrue(remote.isRemote)

        remote.hasLocalArchive = true
        XCTAssertFalse(remote.isRemote, "downloaded folder comic is no longer remote")
    }

    func testCommitSetsSourceFlags() throws {
        let context = try makeContext()

        let folderBook = Importer.commit(
            Importer.Prepared(id: UUID(), title: "F", fileName: "f.cbz", pageCount: 3,
                              coverName: nil, coverAspect: nil, info: nil,
                              sourceRelativePath: "Dir/F.cbz"),
            into: context)
        XCTAssertEqual(folderBook.sourceRelativePath, "Dir/F.cbz")
        XCTAssertTrue(folderBook.isFolderBacked)
        XCTAssertFalse(folderBook.hasLocalArchive, "a folder entry lands not-downloaded")
        XCTAssertTrue(folderBook.isRemote)

        let ownedBook = Importer.commit(
            Importer.Prepared(id: UUID(), title: "O", fileName: "o.cbz", pageCount: 3,
                              coverName: nil, coverAspect: nil, info: nil),
            into: context)
        XCTAssertNil(ownedBook.sourceRelativePath)
        XCTAssertFalse(ownedBook.isFolderBacked)
        XCTAssertTrue(ownedBook.hasLocalArchive, "an owned copy is local")
    }

    // MARK: Identity — the relative path a folder entry re-resolves by

    func testRelativePathAndContains() {
        let folder = URL(fileURLWithPath: "/srv/Comics", isDirectory: true)

        XCTAssertEqual(LibrarySource.relativePath(of: URL(fileURLWithPath: "/srv/Comics/1900.cbz"), in: folder),
                       "1900.cbz")
        XCTAssertEqual(LibrarySource.relativePath(of: URL(fileURLWithPath: "/srv/Comics/Topolino/1900.cbz"), in: folder),
                       "Topolino/1900.cbz")

        // A sibling folder that merely shares a name prefix is not mistaken for a descendant.
        XCTAssertEqual(LibrarySource.relativePath(of: URL(fileURLWithPath: "/srv/ComicsExtra/x.cbz"), in: folder),
                       "x.cbz")
        XCTAssertFalse(LibrarySource.contains(URL(fileURLWithPath: "/srv/ComicsExtra/x.cbz"), in: folder))
        XCTAssertTrue(LibrarySource.contains(URL(fileURLWithPath: "/srv/Comics/Topolino/1900.cbz"), in: folder))

        // The round-trip the whole feature hangs on — including spaces and accents.
        for path in ["/srv/Comics/1900.cbz", "/srv/Comics/Topolino/Annual 2.cbz", "/srv/Comics/Un Été/Astérix.cbz"] {
            let child = URL(fileURLWithPath: path)
            let rel = LibrarySource.relativePath(of: child, in: folder)
            XCTAssertEqual(folder.appendingPathComponent(rel).standardizedFileURL.path,
                           child.standardizedFileURL.path)
        }
    }

    // MARK: Search — the fields a query reaches, and the accent-insensitive compare

    func testSearchMatchesTitleStoryAndIssue() throws {
        let context = try makeContext()
        let book = ComicBook(id: UUID(), title: "raw-file-name.cbz",
                             fileName: "x.cbz", pageCount: 10, coverName: nil)
        book.series = "Astérix"
        book.issueNumber = "1900"
        book.issueTitle = "The Golden Sickle"
        book.stories = [ComicStory(number: 1, kind: "Story", title: "The Mansions of the Gods",
                                   code: nil, credits: [])]
        context.insert(book)

        // Display title (series + issue), matched case- AND diacritic-insensitively.
        XCTAssertTrue(book.matches(searchQuery: "asterix"), "accent-folded series")
        XCTAssertTrue(book.matches(searchQuery: "ASTÉRIX"))
        XCTAssertTrue(book.matches(searchQuery: "1900"), "issue number")
        XCTAssertTrue(book.matches(searchQuery: "golden"), "issue title")
        XCTAssertTrue(book.matches(searchQuery: "mansions"), "story title")
        XCTAssertTrue(book.matches(searchQuery: "raw-file"), "falls back to the file name")

        // A blank query is total — matches everything, so it can bind straight to a search field.
        XCTAssertTrue(book.matches(searchQuery: ""))
        XCTAssertTrue(book.matches(searchQuery: "   "))

        XCTAssertFalse(book.matches(searchQuery: "obelix"), "nothing in this comic says that")
    }
}
