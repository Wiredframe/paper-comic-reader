//
//  Storage.swift
//  Comic Reader
//
//  On-disk locations for imported archives and generated images. SwiftData only
//  stores metadata + file names; the bytes live here. Covers/archives are
//  permanent (Application Support); page-grid thumbnails are regenerable (Caches).
//

import Foundation

enum Storage {

    static let fm = FileManager.default

    // MARK: Permanent (Application Support)

    static var comics: URL { supportDir("Comics") }
    static var covers: URL { supportDir("Covers") }
    static var bookmarkThumbs: URL { supportDir("Bookmarks") }

    // MARK: Regenerable (Caches)

    static func pageThumbs(for bookID: UUID) -> URL {
        cacheDir("PageThumbs/\(bookID.uuidString)")
    }

    /// Deletes half-finished downloads. A download that is cancelled or fails removes its own
    /// temp file; what this is for is the run that never got the chance, because the app was
    /// killed or crashed mid-copy. Nothing ever reads these again, and each is as big as the
    /// comic got, so they would otherwise sit in Application Support for good.
    ///
    /// Called at launch, which is also the only moment it is unconditionally safe: no download
    /// can be in flight yet, so there is no live temp file to mistake for an abandoned one.
    static func clearPartialDownloads() {
        let urls = (try? fm.contentsOfDirectory(at: comics, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "part" {
            try? fm.removeItem(at: url)
        }
    }

    /// Deletes regenerable caches (page-grid thumbnails). Safe — they rebuild on demand.
    static func clearCaches() {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? fm.removeItem(at: base.appendingPathComponent("PageThumbs", isDirectory: true))
    }

    // MARK: Convenience

    static func comicURL(_ fileName: String) -> URL { comics.appendingPathComponent(fileName) }
    static func coverURL(_ fileName: String) -> URL { covers.appendingPathComponent(fileName) }
    static func bookmarkThumbURL(_ fileName: String) -> URL { bookmarkThumbs.appendingPathComponent(fileName) }

    // MARK: Helpers

    private static var appSupport: URL {
        let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func supportDir(_ name: String) -> URL {
        ensured(appSupport.appendingPathComponent(name, isDirectory: true))
    }

    private static func cacheDir(_ name: String) -> URL {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ensured(base.appendingPathComponent(name, isDirectory: true))
    }

    @discardableResult
    private static func ensured(_ url: URL) -> URL {
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
