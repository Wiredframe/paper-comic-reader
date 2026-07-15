//
//  ComicBook.swift
//  Comic Reader
//
//  SwiftData model for one imported comic. Only metadata lives here; the archive
//  bytes and images are files on disk (see Storage).
//

import Foundation
import SwiftData

@Model
final class ComicBook {

    @Attribute(.unique) var id: UUID
    var title: String
    var fileName: String        // archive file in Storage.comics
    var formatRaw: String       // "zip" (CBZ) / "rar" (CBR)
    var pageCount: Int
    var dateAdded: Date
    var dateOpened: Date?       // last time it was opened — drives the Recents tab
    var lastReadPage: Int       // 0-based, for resume
    var coverName: String?      // cover file in Storage.covers
    var isRead: Bool = false     // user-set "read" flag; independent of bookmarks. Set
                                 // manually from the cover menu, or automatically once
                                 // the reader reaches the last page. Default via the
                                 // property initializer keeps SwiftData migration additive.
    var openCount: Int = 0       // how often the comic was opened — read as "popularity"
                                 // by the library sort and the Discover modes. Monotonic:
                                 // deliberately NOT cleared by Recents' "Clear", which only
                                 // forgets `dateOpened`. Defaulted, so migration stays additive.
    var coverAspect: Double?     // cover width / height, captured at import. Stored because
                                 // DiskImage fills whatever frame it's given and can't report
                                 // the artwork's shape — Discover needs it to size a card that
                                 // doesn't crop. Optional, so migration stays additive.

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark] = []

    init(id: UUID = UUID(),
         title: String,
         fileName: String,
         format: ComicFormat,
         pageCount: Int,
         coverName: String?,
         coverAspect: Double? = nil) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.formatRaw = (format == .zip) ? "zip" : "rar"
        self.pageCount = pageCount
        self.dateAdded = .now
        self.dateOpened = nil
        self.lastReadPage = 0
        self.coverName = coverName
        self.coverAspect = coverAspect
    }

    var format: ComicFormat { formatRaw == "rar" ? .rar : .zip }
    var archiveURL: URL { Storage.comicURL(fileName) }
    var coverURL: URL? { coverName.map(Storage.coverURL) }

    /// 0…1 read progress for the cover pie.
    var progress: Double {
        guard pageCount > 1 else { return lastReadPage > 0 ? 1 : 0 }
        return min(1, max(0, Double(lastReadPage) / Double(pageCount - 1)))
    }

    /// "12 pages" / "1 page" — inflected for the cover and list captions.
    var pageCountLabel: String { "\(pageCount) page\(pageCount == 1 ? "" : "s")" }

    /// "Opened 7 times" / "Opened once" / "Never opened" — for the Discover info panel.
    var openCountLabel: String {
        switch openCount {
        case 0:  return "Never opened"
        case 1:  return "Opened once"
        default: return "Opened \(openCount) times"
        }
    }
}
