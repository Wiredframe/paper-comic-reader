//
//  PageImageStoreTests.swift
//  ComicReaderTests
//
//  A page that won't decode must still come back as a picture (the placeholder) rather than
//  nothing, both for the reader and for the page grid / bookmarks, while good pages are untouched.
//

import XCTest
import UIKit
import ZIPFoundation
@testable import ComicReader

@MainActor
final class PageImageStoreTests: XCTestCase {

    private var archiveURL: URL!

    override func setUpWithError() throws {
        archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).cbz")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let good = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60), format: format)
            .jpegData(withCompressionQuality: 0.8) { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
            }
        let entries = ["1.jpg": good, "2.jpg": Data("not a jpeg".utf8)]
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for (name, data) in entries.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: name, type: .file,
                                 uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: archiveURL)
    }

    private func image(at index: Int, in store: PageImageStore) async -> UIImage? {
        await withCheckedContinuation { continuation in
            store.requestImage(at: index) { _, image in continuation.resume(returning: image) }
        }
    }

    func testUndecodablePageGetsThePlaceholder() async throws {
        let store = await PageImageStore.open(bookID: UUID(), url: archiveURL,
                                              paperEnabled: false, paperParams: PaperParams())
        XCTAssertEqual(store.pageCount, 2)

        let good = await image(at: 0, in: store)
        XCTAssertNotNil(good)
        XCTAssertFalse(good === PageImageStore.unreadablePage)

        let broken = await image(at: 1, in: store)
        XCTAssertTrue(broken === PageImageStore.unreadablePage)

        // A large thumbnail (never written to disk) for a bookmark on the broken page.
        let thumb = await store.thumbnail(at: 1, maxPixel: 1000)
        XCTAssertTrue(thumb === PageImageStore.unreadablePage)
    }
}
