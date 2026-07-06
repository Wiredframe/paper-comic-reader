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

    init(id: UUID = UUID(), pageIndex: Int, thumbName: String, book: ComicBook? = nil) {
        self.id = id
        self.pageIndex = pageIndex
        self.thumbName = thumbName
        self.dateAdded = .now
        self.book = book
    }

    var thumbURL: URL { Storage.bookmarkThumbURL(thumbName) }
}
