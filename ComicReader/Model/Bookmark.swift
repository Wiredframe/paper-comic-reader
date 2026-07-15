//
//  Bookmark.swift
//  Comic Reader
//
//  SwiftData model for a bookmarked page. The thumbnail (a screenshot of that
//  exact page) is a file on disk in Storage.bookmarkThumbs.
//

import Foundation
import SwiftData

@Model
final class Bookmark {

    @Attribute(.unique) var id: UUID
    var pageIndex: Int          // 0-based
    var thumbName: String       // thumbnail file in Storage.bookmarkThumbs
    var dateAdded: Date
    var book: ComicBook?
    var pageAspect: Double?     // page width / height, captured when the bookmark is made.
                                // Stored for the same reason as ComicBook.coverAspect: the
                                // carousel has to size an uncropped card up front, and
                                // DiskImage fills whatever frame it's given rather than
                                // reporting the shape. Comic pages vary far more than covers
                                // do — a double-page spread is wider than it is tall.
                                // Optional, so migration stays additive.

    init(id: UUID = UUID(), pageIndex: Int, thumbName: String,
         pageAspect: Double? = nil, book: ComicBook? = nil) {
        self.id = id
        self.pageIndex = pageIndex
        self.thumbName = thumbName
        self.dateAdded = .now
        self.pageAspect = pageAspect
        self.book = book
    }

    var thumbURL: URL { Storage.bookmarkThumbURL(thumbName) }

    /// "Page 12" — the caption on every bookmark card, row and panel.
    var pageLabel: String { "Page \(pageIndex + 1)" }
}
