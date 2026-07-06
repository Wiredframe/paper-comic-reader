//
//  Importer.swift
//  Comic Reader
//
//  Turns a picked / shared archive URL into a library entry: copies the file
//  into app storage, reads it, renders a cover, and inserts a ComicBook.
//

import Foundation
import SwiftData
import UIKit

@MainActor
enum Importer {

    /// Longest side (device pixels) of the stored cover thumbnail.
    static let coverMaxPixel: CGFloat = 700

    enum ImportError: Error { case unsupported, copyFailed, empty }

    /// Imports the archive at `sourceURL` into `context`. Returns the new book.
    @discardableResult
    static func importComic(from sourceURL: URL,
                            into context: ModelContext,
                            folder: Folder? = nil) throws -> ComicBook {
        // Files from the picker / share sheet are security-scoped.
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let format = ComicArchiveFactory.format(of: sourceURL) else {
            throw ImportError.unsupported
        }

        let id = UUID()
        let ext = sourceURL.pathExtension.isEmpty
            ? (format == .zip ? "cbz" : "cbr")
            : sourceURL.pathExtension.lowercased()
        let fileName = "\(id.uuidString).\(ext)"
        let destURL = Storage.comicURL(fileName)

        do {
            if Storage.fm.fileExists(atPath: destURL.path) {
                try Storage.fm.removeItem(at: destURL)
            }
            try Storage.fm.copyItem(at: sourceURL, to: destURL)
        } catch {
            throw ImportError.copyFailed
        }

        guard let archive = try? ComicArchiveFactory.open(url: destURL), archive.pageCount > 0 else {
            try? Storage.fm.removeItem(at: destURL)
            throw ImportError.empty
        }

        // Cover from the first page.
        var coverName: String?
        if let data = archive.pageData(at: 0),
           let cover = ImageDownsampler.downsample(data, maxPixel: coverMaxPixel) {
            let name = "\(id.uuidString).jpg"
            if ImageDownsampler.writeJPEG(cover, to: Storage.coverURL(name)) {
                coverName = name
            }
        }

        let title = sourceURL.deletingPathExtension().lastPathComponent
        let book = ComicBook(id: id, title: title, fileName: fileName,
                             format: format, pageCount: archive.pageCount, coverName: coverName)
        book.folder = folder
        context.insert(book)
        try? context.save()
        return book
    }

    /// Removes a book and its on-disk files.
    static func delete(_ book: ComicBook, from context: ModelContext) {
        try? Storage.fm.removeItem(at: book.archiveURL)
        if let cover = book.coverURL { try? Storage.fm.removeItem(at: cover) }
        for bookmark in book.bookmarks {
            try? Storage.fm.removeItem(at: bookmark.thumbURL)
        }
        try? Storage.fm.removeItem(at: Storage.pageThumbs(for: book.id))
        context.delete(book)
        try? context.save()
    }
}
