//
//  ComicArchive.swift
//  Comic Reader
//
//  Read-only, on-demand access to the image pages of a CBZ (ZIP, via ZIPFoundation).
//  Pages are the image entries, filtered and naturally sorted so that "2.jpg" comes
//  before "10.jpg". Entries are read on demand so we never hold the whole archive in
//  memory.
//
//  One backend, one type: this used to be a protocol over CBZ and CBR (RAR, via a
//  vendored UnrarKit). CBR is gone, and with it the abstraction it existed for.
//

import Foundation
import ZIPFoundation

enum ComicArchiveError: Error {
    case unsupportedFormat
    case unreadable
}

final class ComicArchive {

    /// Extensions we treat as comic pages.
    static let imageExtensions: Set<String> =
        ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]

    private let archive: Archive
    private let pages: [Entry]           // image entries, in reading order
    private let metadata: Entry?         // ComicInfo.xml, if this comic is tagged

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
        self.pages = Self.sortedImageNames(Array(byPath.keys)).compactMap { byPath[$0] }
        self.metadata = Self.metadataName(among: byPath.keys).flatMap { byPath[$0] }
    }

    /// Number of image pages in reading order.
    var pageCount: Int { pages.count }

    /// The raw ComicInfo.xml bytes, or nil for an untagged comic. Read on demand — the
    /// importer wants it once and the reader never does.
    func metadataXML() -> Data? { metadata.flatMap(data(of:)) }

    /// Finds the archive's ComicInfo.xml. The convention is a root-level file of exactly that
    /// name; a nested one is accepted as a fallback because some taggers write the comic into
    /// a subfolder. Sorted, not just `first`: dictionary order is unspecified, and picking a
    /// different file on each import would be a maddening bug.
    private static func metadataName(among names: some Collection<String>) -> String? {
        let matches = names
            .filter { ($0 as NSString).lastPathComponent.caseInsensitiveCompare("ComicInfo.xml") == .orderedSame }
            .sorted()
        return matches.first { !$0.contains("/") } ?? matches.first
    }

    /// Raw, still-encoded image bytes for a page, or nil if it can't be read.
    func pageData(at index: Int) -> Data? {
        guard pages.indices.contains(index) else { return nil }
        return data(of: pages[index])
    }

    private func data(of entry: Entry) -> Data? {
        var data = Data()
        do {
            _ = try archive.extract(entry) { data.append($0) }
        } catch {
            return nil
        }
        return data.isEmpty ? nil : data
    }

    // MARK: Format check

    /// Whether `url` is worth trying to open — by extension, falling back to the file's
    /// magic bytes. Cheap: the importer rejects non-comics with this *before* copying the
    /// file into storage.
    static func looksLikeComic(at url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "cbz", "zip": return true
        default:           return isZip(at: url)
        }
    }

    /// ZIP files start with "PK".
    private static func isZip(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let sig = try? handle.read(upToCount: 2), sig.count >= 2 else { return false }
        let b = [UInt8](sig)
        return b[0] == 0x50 && b[1] == 0x4B
    }

    // MARK: Page filtering

    /// Filters the archive's entry names down to image pages and sorts them the way a
    /// human numbers pages.
    private static func sortedImageNames(_ names: [String]) -> [String] {
        names
            .filter(isPage)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func isPage(_ path: String) -> Bool {
        let lower = path.lowercased()
        guard !lower.hasPrefix("__macosx/"), !lower.contains("/__macosx/") else { return false }
        let name = (path as NSString).lastPathComponent
        guard !name.hasPrefix(".") else { return false }               // ._foo, .DS_Store
        return imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }
}
