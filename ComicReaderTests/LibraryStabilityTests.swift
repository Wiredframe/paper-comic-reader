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
import ZIPFoundation
@testable import ComicReader

@MainActor
final class LibraryStabilityTests: XCTestCase {

    /// Temp files written into the app's Storage during a test, removed in tearDown.
    private var tempFiles: [URL] = []

    /// The removed-entries list lives in the app's defaults, which deleting a folder comic writes.
    /// Put back as it was, so a test run leaves the simulator's library as it found it.
    private var savedExcludedPaths: Set<String> = []

    override func setUpWithError() throws {
        savedExcludedPaths = LibrarySource.excludedPaths
    }

    override func tearDownWithError() throws {
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        tempFiles = []
        LibrarySource.includeAll()
        for path in savedExcludedPaths { LibrarySource.exclude(path) }
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
    /// After a device restore the downloads (left out of the backup) are gone while the entries
    /// still claim them. The launch reconcile clears the flag for those, and only for those.
    func testReconcileClearsDownloadsThatAreGone() async throws {
        let context = try makeContext()
        let (kept, _) = try makeDownloadedFolderBook(in: context, bookmarks: 1)
        let (gone, _) = try makeDownloadedFolderBook(in: context, bookmarks: 1)
        try FileManager.default.removeItem(at: gone.archiveURL)

        await Importer.reconcileDownloads(in: context)

        XCTAssertTrue(kept.hasLocalArchive)
        XCTAssertFalse(gone.hasLocalArchive)
        XCTAssertEqual(gone.bookmarks.count, 1, "reconciling must never touch a bookmark")
    }

    // MARK: Re-reading metadata

    /// An owned comic whose archive won't open (a damaged file) must keep the details it has:
    /// a failed read is not an untagged comic, and only the latter clears the fields.
    func testRefreshKeepsMetadataWhenTheArchiveWontOpen() async throws {
        let context = try makeContext()
        let book = ComicBook(id: UUID(), title: "Raw", fileName: "\(UUID().uuidString).cbz",
                             pageCount: 3, coverName: nil)
        book.series = "Topolino"
        book.issueNumber = "1900"
        context.insert(book)
        try context.save()
        FileManager.default.createFile(atPath: book.archiveURL.path, contents: Data("not a zip".utf8))
        tempFiles.append(book.archiveURL)

        let updated = await Importer.refreshMetadata(for: [book], into: context) { _, _ in }

        XCTAssertEqual(updated, 0)
        XCTAssertEqual(book.series, "Topolino")
        XCTAssertEqual(book.issueNumber, "1900")
    }

    /// The other half of the split: an archive that opens and simply carries no ComicInfo.xml is
    /// a real read, and does clear the fields.
    func testRefreshClearsMetadataOfAnUntaggedArchive() async throws {
        let context = try makeContext()
        let book = ComicBook(id: UUID(), title: "Raw", fileName: "\(UUID().uuidString).cbz",
                             pageCount: 1, coverName: nil)
        book.series = "Topolino"
        context.insert(book)
        try context.save()
        try writeArchive(to: book.archiveURL, entries: ["page1.jpg": Data("page".utf8)])

        let updated = await Importer.refreshMetadata(for: [book], into: context) { _, _ in }

        XCTAssertEqual(updated, 1)
        XCTAssertNil(book.series)
    }

    /// A small CBZ with the given entries, removed in tearDown.
    private func writeArchive(to url: URL, entries: [String: Data]) throws {
        try? FileManager.default.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create)
        for (name, data) in entries.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: name, type: .file,
                                 uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        tempFiles.append(url)
    }
    /// A bare "&" in <Summary> stops the XML parser there. The fields that closed before it are
    /// complete and must survive instead of the whole comic reading as untagged.
    func testMalformedComicInfoKeepsTheFieldsBeforeTheError() throws {
        let xml = """
        <?xml version="1.0"?>
        <ComicInfo>
          <Series>Topolino</Series>
          <Number>1900</Number>
          <Summary>Paperino & Paperoga</Summary>
          <Year>1992</Year>
        </ComicInfo>
        """
        let info = try XCTUnwrap(ComicInfoParser.parse(Data(xml.utf8)))
        XCTAssertEqual(info.series, "Topolino")
        XCTAssertEqual(info.number, "1900")
        XCTAssertNil(info.summary, "the field the error sits in is incomplete and dropped")

        XCTAssertNil(ComicInfoParser.parse(Data("&not xml at all".utf8)))
    }
    // MARK: Choose Another File

    /// A replacement pick reports its own page count, so the entry can follow a file that isn't
    /// page for page the one it replaces; a pick that won't open as a comic is refused.
    func testRelinkReportsTheReplacementsPageCount() throws {
        let picked = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).cbz")
        try writeArchive(to: picked, entries: ["1.jpg": Data("a".utf8), "2.jpg": Data("b".utf8)])
        let dest = Storage.comicURL("\(UUID().uuidString).cbz")
        tempFiles.append(dest)

        let relinked = try Importer.relink(from: picked, into: dest)
        XCTAssertEqual(relinked.pageCount, 2)
        XCTAssertNil(relinked.relativePath, "a pick outside the library folder keeps the old source")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))

        let garbage = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).cbz")
        FileManager.default.createFile(atPath: garbage.path, contents: Data("not a zip".utf8))
        tempFiles.append(garbage)
        XCTAssertThrowsError(try Importer.relink(from: garbage, into: dest))
    }
    // MARK: Removed folder entries

    /// Deleting a folder comic notes its path, so a rescan doesn't bring the entry straight back,
    /// and a hand import of that file lets it in again. An owned copy has no path to note.
    func testDeletingAFolderEntryKeepsItOutOfTheScan() throws {
        let context = try makeContext()
        let (book, _) = try makeDownloadedFolderBook(in: context, bookmarks: 0)
        let path = try XCTUnwrap(book.sourceRelativePath)
        LibrarySource.include(path)

        Importer.delete(book, from: context)
        XCTAssertTrue(LibrarySource.excludedPaths.contains(path))

        let before = LibrarySource.excludedPaths
        let owned = ComicBook(id: UUID(), title: "Owned", fileName: "\(UUID().uuidString).cbz",
                              pageCount: 1, coverName: nil)
        context.insert(owned)
        Importer.delete(owned, from: context)
        XCTAssertEqual(LibrarySource.excludedPaths, before)

        let prepared = Importer.Prepared(id: UUID(), title: "Test", fileName: "\(UUID().uuidString).cbz",
                                         pageCount: 20, coverName: nil, coverAspect: nil, info: nil)
        let back = Importer.commitReturning(prepared, relativePath: path, into: context)
        XCTAssertFalse(LibrarySource.excludedPaths.contains(path))
        XCTAssertEqual(back.sourceRelativePath, path)
        XCTAssertTrue(back.hasLocalArchive, "the hand import brought its bytes along")
    }

    // MARK: Bookmark stories: the picker's suggestion and hand-named stories

    /// A comic with an index of three stories and a bookmark on each of `pages`.
    private func makeStoryBook(in context: ModelContext, pages: [Int]) -> (ComicBook, [Int: Bookmark]) {
        let book = ComicBook(id: UUID(), title: "Topolino", fileName: "t.cbz", pageCount: 100, coverName: nil)
        book.stories = ["Alpha", "Beta", "Gamma"].enumerated().map {
            ComicStory(number: $0.offset + 1, kind: "Storia", title: $0.element, code: nil, credits: [])
        }
        context.insert(book)
        var marks: [Int: Bookmark] = [:]
        for page in pages {
            let mark = Bookmark(pageIndex: page, thumbName: "\(UUID().uuidString).jpg", book: book)
            context.insert(mark)
            marks[page] = mark
        }
        return (book, marks)
    }

    func testSuggestionIsStrongWhenBothNeighboursAgree() throws {
        let context = try makeContext()
        let (_, marks) = makeStoryBook(in: context, pages: [2, 5, 9, 20])
        marks[2]?.assignStory(at: 1)
        marks[9]?.assignStory(at: 1)
        marks[20]?.assignStory(at: 2)

        let suggestion = try XCTUnwrap(marks[5]?.suggestedStory())
        XCTAssertEqual(suggestion.title, "Beta")
        XCTAssertEqual(suggestion.storyIndex, 1)
        XCTAssertEqual(suggestion.page, 2)
        XCTAssertEqual(suggestion.otherPage, 9)
        XCTAssertTrue(suggestion.isStrong)
    }

    func testSuggestionFallsBackToTheNearestMarkBelowThenAbove() throws {
        let context = try makeContext()
        let (_, marks) = makeStoryBook(in: context, pages: [1, 4, 8, 12, 30])
        marks[4]?.assignStory(at: 0)
        marks[12]?.assignStory(at: 2)

        // Between two different stories: the one that was running.
        let between = try XCTUnwrap(marks[8]?.suggestedStory())
        XCTAssertEqual(between.title, "Alpha")
        XCTAssertEqual(between.page, 4)
        XCTAssertFalse(between.isStrong)

        // Before the first assigned mark: the nearest one above.
        XCTAssertEqual(marks[1]?.suggestedStory()?.title, "Alpha")
        // After the last one: still the nearest below, however far.
        XCTAssertEqual(marks[30]?.suggestedStory()?.title, "Gamma")
    }

    func testNoSuggestionWithoutAssignedNeighboursOrWhenAlreadyAssigned() throws {
        let context = try makeContext()
        let (_, marks) = makeStoryBook(in: context, pages: [3, 6, 9])
        XCTAssertNil(marks[6]?.suggestedStory(), "nobody has a story yet")

        marks[3]?.assignStory(at: 0)
        marks[9]?.assignStory(at: 0)
        marks[6]?.assignStory(at: 0)
        XCTAssertNil(marks[6]?.suggestedStory(), "the guess is already this page's story")
    }

    func testCustomStoriesAreSuggestedByTitleAndListedOnce() throws {
        let context = try makeContext()
        let book = ComicBook(id: UUID(), title: "Collected", fileName: "c.cbz", pageCount: 200, coverName: nil)
        context.insert(book)
        let marks = [10, 15, 40, 60].map { page in
            let mark = Bookmark(pageIndex: page, thumbName: "\(UUID().uuidString).jpg", book: book)
            context.insert(mark)
            return mark
        }
        marks[0].assignCustomStory("  Chapter One ")
        marks[2].assignCustomStory("Chapter One")
        marks[3].assignCustomStory("Chapter Two")

        XCTAssertEqual(marks[0].storyLabel, "Chapter One", "trimmed")
        XCTAssertNil(marks[0].storyIndex)
        XCTAssertNil(marks[0].resolvedStoryIndex(), "no index to resolve against")

        let suggestion = try XCTUnwrap(marks[1].suggestedStory())
        XCTAssertEqual(suggestion.title, "Chapter One")
        XCTAssertNil(suggestion.storyIndex)
        XCTAssertTrue(suggestion.isStrong, "both sides carry the same hand-typed name")

        marks[1].assign(suggestion)
        XCTAssertEqual(marks[1].storyLabel, "Chapter One")
        XCTAssertEqual(book.customStoryTitles, ["Chapter One", "Chapter Two"])

        // A blank name clears rather than storing whitespace.
        marks[3].assignCustomStory("   ")
        XCTAssertFalse(marks[3].hasStory)
    }

    func testBookmarkSearchMatchesItsOwnStoryNotTheWholeIndex() throws {
        let context = try makeContext()
        let (book, marks) = makeStoryBook(in: context, pages: [1, 2])
        book.series = "Topolino"
        book.issueNumber = "1900"
        marks[1]?.assignStory(at: 1)

        XCTAssertTrue(marks[1]?.matches(searchQuery: "beta") ?? false, "its own story")
        XCTAssertFalse(marks[2]?.matches(searchQuery: "beta") ?? true,
                       "a story of the same issue that isn't this page's")
        XCTAssertFalse(marks[1]?.matches(searchQuery: "gamma") ?? true, "only the index lists it")
        XCTAssertTrue(marks[2]?.matches(searchQuery: "topolino") ?? false, "the comic's name")
        XCTAssertTrue(marks[2]?.matches(searchQuery: "1900") ?? false, "the issue number")
        XCTAssertTrue(marks[2]?.matches(searchQuery: "  ") ?? false, "a blank query matches all")

        // The comic-level search still reaches the index.
        XCTAssertTrue(book.matches(searchQuery: "gamma"))
    }

    func testStoryRunsFollowThePages() throws {
        let context = try makeContext()
        let (_, marks) = makeStoryBook(in: context, pages: [1, 2, 3, 4, 5, 6])
        marks[2]?.assignStory(at: 0)
        marks[3]?.assignStory(at: 0)
        marks[4]?.assignStory(at: 1)
        marks[6]?.assignStory(at: 0)
        let ordered = [1, 2, 3, 4, 5, 6].compactMap { marks[$0] }

        let runs = Bookmark.storyRuns(ordered)
        XCTAssertEqual(runs.map(\.title), [nil, "Alpha", "Beta", nil, "Alpha"])
        XCTAssertEqual(runs.map { $0.marks.map(\.pageIndex) }, [[1], [2, 3], [4], [5], [6]])
        XCTAssertTrue(Bookmark.storyRuns([]).isEmpty)
    }
}
