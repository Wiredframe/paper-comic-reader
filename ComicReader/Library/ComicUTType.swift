//
//  ComicUTType.swift
//  Comic Reader
//
//  The document types the importer / share sheet accept.
//

import UniformTypeIdentifiers

enum ComicUTType {
    /// CBZ (+ plain zip). cbz resolves to our exported type, which is enough for the
    /// picker to match by extension.
    static let all: [UTType] = {
        var types: [UTType] = [.zip]
        if let cbz = UTType(filenameExtension: "cbz") { types.append(cbz) }
        return types
    }()
}
