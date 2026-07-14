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

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark] = []

    init(id: UUID = UUID(),
         title: String,
         fileName: String,
         format: ComicFormat,
         pageCount: Int,
         coverName: String?) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.formatRaw = (format == .zip) ? "zip" : "rar"
        self.pageCount = pageCount
        self.dateAdded = .now
        self.dateOpened = nil
        self.lastReadPage = 0
        self.coverName = coverName
    }

    var format: ComicFormat { formatRaw == "rar" ? .rar : .zip }
    var archiveURL: URL { Storage.comicURL(fileName) }
    var coverURL: URL? { coverName.map(Storage.coverURL) }

    /// 0…1 read progress for the cover pie.
    var progress: Double {
        guard pageCount > 1 else { return lastReadPage > 0 ? 1 : 0 }
        return min(1, max(0, Double(lastReadPage) / Double(pageCount - 1)))
    }
}
