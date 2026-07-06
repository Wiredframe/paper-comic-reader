//
//  RarComicArchive.swift
//  Comic Reader
//
//  CBR backend (RAR) built on the vendored UnrarKit (see the bridging header and
//  Vendor/UnrarKit). Filenames are listed once; page bytes are extracted on
//  demand.
//

import Foundation

final class RarComicArchive: ComicArchive {

    private let archive: URKArchive
    private let pageNames: [String]   // image entry names, in reading order

    init(url: URL) throws {
        do {
            let archive = try URKArchive(url: url)
            self.archive = archive
            let all = try archive.listFilenames()
            self.pageNames = ComicArchiveFactory.sortedImageNames(all)
        } catch {
            throw ComicArchiveError.unreadable
        }
    }

    var pageCount: Int { pageNames.count }

    func pageData(at index: Int) -> Data? {
        guard pageNames.indices.contains(index) else { return nil }
        return try? archive.extractData(fromFile: pageNames[index])
    }
}
