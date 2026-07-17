//
//  SampleLibrary.swift
//  Comic Reader
//
//  First-launch sample content. Imports the four bundled demo comics into an empty
//  library exactly once, so a fresh install — and the App Review — opens on a
//  populated shelf instead of an empty state. A few of them get a recent open date, a
//  resume page and a bookmark, so Recents, the progress pies and the Bookmarks tab all
//  have something real to show. The comics are ordinary library entries: the user can
//  delete any or all of them, and they never come back (the seed is one-shot).
//
//  NOT gated on DEBUG — this ships. It reuses `Importer.importComic` (main-actor,
//  synchronous), which is fine here for the same reason it's fine for screenshot
//  seeding: four tiny archives, once, at launch.
//

import Foundation
import SwiftData
import UIKit

enum SampleLibrary {

    /// Set once the seed has run (even if it found nothing), so cleared demos never return.
    /// Bump the suffix if the bundled demo set ever changes.
    private static let seededKey = "didSeedSampleLibraryV1"

    /// One bundled comic and the lived-in state to give it. Page numbers are 0-based archive
    /// indices; `openedHoursAgo` becomes `dateOpened` (nil = never opened → not in Recents).
    private struct Sample {
        let resource: String        // .cbz base name in the app bundle
        let lastReadPage: Int       // resume point + progress pie
        let openedHoursAgo: Double? // dateOpened, for Recents ordering
        let openCount: Int          // Discover "opened N times"
        let bookmarks: [Int]        // pages to pre-bookmark
    }

    private static let samples: [Sample] = [
        Sample(resource: "SolarFlare",   lastReadPage: 6,  openedHoursAgo: 2,   openCount: 5, bookmarks: [4, 9]),
        Sample(resource: "DeepBlue",     lastReadPage: 11, openedHoursAgo: 26,  openCount: 3, bookmarks: [7]),
        Sample(resource: "CrimsonAlley", lastReadPage: 3,  openedHoursAgo: 74,  openCount: 2, bookmarks: [3]),
        Sample(resource: "JadeCircuit",  lastReadPage: 0,  openedHoursAgo: nil, openCount: 0, bookmarks: []),
    ]

    @MainActor
    static func seedIfNeeded(into context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededKey) else { return }
        // Only ever seed an empty library — never displace the user's own comics (or a store
        // that just survived a migration). Mark seeded regardless, so it stays one-shot.
        let existing = (try? context.fetch(FetchDescriptor<ComicBook>())) ?? []
        guard existing.isEmpty else { defaults.set(true, forKey: seededKey); return }

        for sample in samples {
            guard let url = Bundle.main.url(forResource: sample.resource, withExtension: "cbz"),
                  let book = try? Importer.importComic(from: url, into: context) else { continue }

            book.lastReadPage = min(max(0, sample.lastReadPage), max(0, book.pageCount - 1))
            book.openCount = sample.openCount
            book.dateOpened = sample.openedHoursAgo.map { Date(timeIntervalSinceNow: -$0 * 3600) }
            for page in sample.bookmarks where page < book.pageCount {
                addBookmark(to: book, pageIndex: page, in: context)
            }
        }
        try? context.save()
        defaults.set(true, forKey: seededKey)
    }

    /// Mirrors the reader's own bookmark add (`ReaderView.toggleBookmark`): decode the page at
    /// cover resolution, write its thumbnail to Storage.bookmarkThumbs, and insert the record
    /// with the captured page aspect. Decoding straight from the archive is what
    /// `PageImageStore.thumbnail` does under the hood — the reader isn't running here to ask.
    @MainActor
    private static func addBookmark(to book: ComicBook, pageIndex: Int, in context: ModelContext) {
        guard let data = (try? ComicArchive(url: book.archiveURL))?.pageData(at: pageIndex),
              let image = ImageDownsampler.downsample(data, maxPixel: ImageDownsampler.libraryCardPixel)
        else { return }
        let name = "\(UUID().uuidString).jpg"
        ImageDownsampler.writeJPEG(image, to: Storage.bookmarkThumbURL(name))
        let aspect: Double? = image.size.height > 0 ? Double(image.size.width / image.size.height) : nil
        context.insert(Bookmark(pageIndex: pageIndex, thumbName: name, pageAspect: aspect, book: book))
    }
}
