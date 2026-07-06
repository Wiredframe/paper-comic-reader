//
//  Folder.swift
//  Comic Reader
//
//  SwiftData model for a collection folder. Flat (no nesting) for now.
//

import Foundation
import SwiftData

@Model
final class Folder {

    @Attribute(.unique) var id: UUID
    var name: String
    var dateCreated: Date

    @Relationship(deleteRule: .nullify, inverse: \ComicBook.folder)
    var books: [ComicBook] = []

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.dateCreated = .now
    }
}
