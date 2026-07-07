//
//  ScreenshotSupport.swift
//  Comic Reader
//
//  DEBUG-only helpers that place the app in a known state for App Store screenshots,
//  driven purely by launch-environment variables (see AppStore/screenshots.sh). The
//  whole file is behind `#if DEBUG`, so it is empty in Release builds and can never
//  affect the shipping app. In a normal Debug run (no env vars set) it is inert.
//

#if DEBUG
import Foundation
import SwiftData

enum ScreenshotSupport {

    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Seed the library (only if empty), then, when SCREENSHOT_OPEN_PAGE is set, point
    /// the first comic's resume page there so the reader opens on that page. Two seed
    /// modes: SEED_LIBRARY_DIR imports every .cbz in a folder (a full grid for the
    /// Library shot); SEED_COMIC_PATH imports one comic (for the reader shots). Both
    /// are host paths — simulator apps can read them.
    @MainActor static func seedIfRequested(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ComicBook>())) ?? []
        if existing.isEmpty {
            if let dir = env["SEED_LIBRARY_DIR"], !dir.isEmpty {
                let urls = ((try? FileManager.default.contentsOfDirectory(
                    at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.pathExtension.lowercased() == "cbz" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                for url in urls { _ = try? Importer.importComic(from: url, into: context) }
            } else if let path = env["SEED_COMIC_PATH"], !path.isEmpty {
                _ = try? Importer.importComic(from: URL(fileURLWithPath: path), into: context)
            }
        }
        if let page = openPage,
           let book = (try? context.fetch(FetchDescriptor<ComicBook>()))?.first {
            book.lastReadPage = max(0, min(page, book.pageCount - 1))
            try? context.save()
        }
    }

    /// Initial tab (SCREENSHOT_TAB = recents | library | bookmarks | settings).
    static var initialTab: String? { env["SCREENSHOT_TAB"] }

    /// When SCREENSHOT_OPEN_PAGE is set, LibraryView auto-opens the first comic.
    static var shouldOpenReader: Bool { openPage != nil }

    static var openPage: Int? { env["SCREENSHOT_OPEN_PAGE"].flatMap(Int.init) }

    /// When set, RootTabView shows the Tip Jar sheet on launch (for the IAP review
    /// screenshot); TipJarView renders a representative row so it doesn't need a live
    /// StoreKit session.
    static var showTips: Bool { env["SCREENSHOT_TIPS"] != nil }
}
#endif
