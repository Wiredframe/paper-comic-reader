//
//  LibraryRecoveryTests.swift
//  ComicReaderTests
//
//  The safety net under a store that won't open: the store is moved aside rather than deleted, the
//  rolling snapshot can't destroy itself, and a snapshot rebuilds the library from files that
//  never moved.
//

import XCTest
import SwiftData
@testable import ComicReader

@MainActor
final class LibraryRecoveryTests: XCTestCase {

    private var written: [URL] = []
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        written.append(scratch)
    }

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

    private func write(_ text: String, to url: URL) {
        try? Data(text.utf8).write(to: url)
        written.append(url)
    }

    private func insertOwned(_ context: ModelContext, title: String = "Topolino 1900") -> ComicBook {
        let id = UUID()
        let fileName = "\(id.uuidString).cbz"
        let coverName = "\(id.uuidString).jpg"
        write("archive", to: Storage.comicURL(fileName))
        write("cover", to: Storage.coverURL(coverName))
        let book = ComicBook(id: id, title: title, fileName: fileName,
                             pageCount: 30, coverName: coverName, coverAspect: 0.66)
        context.insert(book)
        return book
    }

    private var snapshotURL: URL { scratch.appendingPathComponent("Safety/library.json") }

    // MARK: Snapshot guards

    func testSnapshotIsNotWrittenWhileAResetIsPending() throws {
        let context = try makeContext()
        let book = insertOwned(context)
        XCTAssertEqual(LibrarySnapshot.save([book], to: snapshotURL, resetPending: true),
                       .skippedResetPending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    }

    func testEmptyLibraryNeverReplacesAFullSnapshot() throws {
        let context = try makeContext()
        let book = insertOwned(context)
        XCTAssertEqual(LibrarySnapshot.save([book], to: snapshotURL, resetPending: false), .written)
        XCTAssertEqual(LibrarySnapshot.save([], to: snapshotURL, resetPending: false), .skippedWouldEmpty)
        XCTAssertEqual(LibrarySnapshot.load(from: snapshotURL)?.comics.count, 1)
    }

    func testEmptyLibraryMayWriteTheFirstSnapshot() throws {
        XCTAssertEqual(LibrarySnapshot.save([], to: snapshotURL, resetPending: false), .written)
        XCTAssertEqual(LibrarySnapshot.load(from: snapshotURL)?.comics.count, 0)
    }

    func testSnapshotIsProtectedUntilFirstUnlock() throws {
        let context = try makeContext()
        LibrarySnapshot.save([insertOwned(context)], to: snapshotURL, resetPending: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
        // The simulator doesn't apply data protection, so only check what it reports when it does.
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
        }
    }

    // MARK: Restore

    /// After a reset the files are all still in Storage; only the rows are gone. The snapshot puts
    /// them back, archives and covers found in place, a folder comic's download included.
    func testSnapshotRebuildsTheLibraryFromFilesInPlace() throws {
        let source = try makeContext()
        let owned = insertOwned(source)
        owned.lastReadPage = 12
        owned.isFavorite = true
        let thumb = "\(UUID().uuidString).jpg"
        write("thumb", to: Storage.bookmarkThumbURL(thumb))
        source.insert(Bookmark(pageIndex: 7, thumbName: thumb, pageAspect: 0.7, book: owned))

        let folder = ComicBook(title: "Topolino 1901", fileName: "\(UUID().uuidString).cbz",
                               pageCount: 40, coverName: nil)
        folder.sourceRelativePath = "Topolino/1901.cbz"
        folder.hasLocalArchive = true
        write("downloaded", to: folder.archiveURL)
        source.insert(folder)

        LibrarySnapshot.save([owned, folder], to: snapshotURL, resetPending: false)
        let snapshot = try XCTUnwrap(LibrarySnapshot.load(from: snapshotURL))

        let target = try makeContext()
        let report = LibrarySnapshot.restore(snapshot, into: target)
        XCTAssertEqual(report.comicsAdded, 2)
        XCTAssertEqual(report.comicsWithoutArchive, 0)

        let books = try target.fetch(FetchDescriptor<ComicBook>())
        let restoredOwned = try XCTUnwrap(books.first { $0.fileName == owned.fileName })
        XCTAssertTrue(restoredOwned.hasLocalArchive)
        XCTAssertEqual(restoredOwned.coverName, owned.coverName)
        XCTAssertEqual(restoredOwned.lastReadPage, 12)
        XCTAssertTrue(restoredOwned.isFavorite)
        XCTAssertEqual(restoredOwned.bookmarks.map(\.pageIndex), [7])
        XCTAssertEqual(restoredOwned.bookmarks.first?.thumbName, thumb)

        let restoredFolder = try XCTUnwrap(books.first { $0.isFolderBacked })
        XCTAssertEqual(restoredFolder.fileName, folder.fileName)
        XCTAssertTrue(restoredFolder.hasLocalArchive, "its download is still on disk")
    }

    // MARK: Moving the store aside

    func testStoreIsMovedAsideNotDeleted() throws {
        let store = scratch.appendingPathComponent("default.store")
        for suffix in ["", "-wal", "-shm"] { write("db", to: URL(fileURLWithPath: store.path + suffix)) }
        let backups = scratch.appendingPathComponent("StoreBackups", isDirectory: true)

        let folder = try XCTUnwrap(LibraryStore.moveAside(storeAt: store, into: backups))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
        }
    }

    func testOnlyTheNewestFiveBackupsAreKept() throws {
        let backups = scratch.appendingPathComponent("StoreBackups", isDirectory: true)
        let store = scratch.appendingPathComponent("default.store")
        for day in 1...7 {
            write("db", to: store)
            let date = try XCTUnwrap(Calendar(identifier: .gregorian)
                .date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12)))
            XCTAssertNotNil(LibraryStore.moveAside(storeAt: store, into: backups, now: date))
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: backups.path).sorted()
        XCTAssertEqual(names.count, 5)
        XCTAssertTrue(names.first?.hasPrefix("2026-10-03") == true)
        XCTAssertTrue(names.last?.hasPrefix("2026-10-07") == true)
    }
}
