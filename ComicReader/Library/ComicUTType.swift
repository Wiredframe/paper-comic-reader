//
//  ComicUTType.swift
//  Comic Reader
//
//  The document types the importer / share sheet accept.
//

import UniformTypeIdentifiers

enum ComicUTType {
    /// CBZ/CBR (+ plain zip/rar). cbz/cbr resolve to dynamic types, which is
    /// enough for the picker to match by extension.
    static let all: [UTType] = {
        var types: [UTType] = [.zip]
        for ext in ["cbz", "cbr", "rar"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }()
}
