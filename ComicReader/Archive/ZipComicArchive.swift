//
//  ZipComicArchive.swift
//  Comic Reader
//
//  CBZ backend (ZIP) built on ZIPFoundation. Entries are read on demand so we
//  never hold the whole archive in memory.
//

import Foundation
import ZIPFoundation

final class ZipComicArchive: ComicArchive {

    private let archive: Archive
    private let pages: [Entry]   // image entries, in reading order

    init(url: URL) throws {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw ComicArchiveError.unreadable
        }
        self.archive = archive

        // Map path → entry for the regular files, then filter/sort by path.
        var byPath: [String: Entry] = [:]
        for entry in archive where entry.type == .file {
            byPath[entry.path] = entry
        }
        self.pages = ComicArchiveFactory
            .sortedImageNames(Array(byPath.keys))
            .compactMap { byPath[$0] }
    }

    var pageCount: Int { pages.count }

    func pageData(at index: Int) -> Data? {
        guard pages.indices.contains(index) else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(pages[index]) { data.append($0) }
        } catch {
            return nil
        }
        return data.isEmpty ? nil : data
    }
}
