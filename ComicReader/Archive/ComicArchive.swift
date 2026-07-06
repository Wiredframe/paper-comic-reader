//
//  ComicArchive.swift
//  Comic Reader
//
//  Read-only, on-demand access to the image pages of a comic archive. Two
//  backends: CBZ (ZIP, via ZIPFoundation) and CBR (RAR, via vendored UnrarKit).
//  Pages are the image entries, filtered and naturally sorted so that
//  "2.jpg" comes before "10.jpg".
//

import Foundation

/// A comic archive exposing its image pages by index (0-based).
protocol ComicArchive {
    /// Number of image pages in reading order.
    var pageCount: Int { get }
    /// Raw, still-encoded image bytes for a page, or nil if it can't be read.
    func pageData(at index: Int) -> Data?
}

enum ComicFormat {
    case zip   // CBZ
    case rar   // CBR
}

enum ComicArchiveError: Error {
    case unsupportedFormat
    case unreadable
}

enum ComicArchiveFactory {

    /// Extensions we treat as comic pages.
    static let imageExtensions: Set<String> =
        ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]

    /// Opens the archive at `url`, choosing the backend by extension (falling
    /// back to the file's magic bytes).
    static func open(url: URL) throws -> ComicArchive {
        switch format(of: url) {
        case .zip: return try ZipComicArchive(url: url)
        case .rar: return try RarComicArchive(url: url)
        case nil:  throw ComicArchiveError.unsupportedFormat
        }
    }

    /// Detects the format from the extension, then from magic bytes.
    static func format(of url: URL) -> ComicFormat? {
        switch url.pathExtension.lowercased() {
        case "cbz", "zip": return .zip
        case "cbr", "rar": return .rar
        default:           return magicFormat(of: url)
        }
    }

    /// ZIP files start with "PK", RAR with "Rar!".
    static func magicFormat(of url: URL) -> ComicFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let sig = try? handle.read(upToCount: 4), sig.count >= 4 else { return nil }
        let b = [UInt8](sig)
        if b[0] == 0x50, b[1] == 0x4B { return .zip }                            // PK
        if b[0] == 0x52, b[1] == 0x61, b[2] == 0x72, b[3] == 0x21 { return .rar } // Rar!
        return nil
    }

    /// Filters an archive's entry names down to image pages and sorts them the
    /// way a human numbers pages. Shared by both backends.
    static func sortedImageNames(_ names: [String]) -> [String] {
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
