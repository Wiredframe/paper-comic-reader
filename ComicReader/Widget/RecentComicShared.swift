//
//  RecentComicShared.swift
//  Comic Reader
//
//  What the app and the Recent Comic widget agree on: the App Group they share, the snapshot
//  the app leaves there, and the link a tap on the widget opens. Compiled into both targets,
//  the same way the thumbnail extension borrows ComicArchive, so the two sides can't drift.
//
//  The widget never touches the SwiftData store. It only reads this snapshot: one small JSON
//  file and a copy of the cover, rewritten by the app whenever the top of Recents changes.
//

import Foundation

enum RecentComicShared {

    static let appGroup = "group.de.wiredframe.comicreader"
    static let widgetKind = "RecentComic"

    /// What the widget shows and opens. The link carries only the id: the reader resolves the
    /// resume page itself at open time. The page fields are for the Extra Large tile's progress,
    /// written when the reader saves progress, not on every turn.
    ///
    /// Add any new field as an OPTIONAL: an app update meets the old JSON before it rewrites it,
    /// and a snapshot that no longer decodes leaves the widget blank until the app is opened.
    struct Snapshot: Codable, Equatable {
        var bookID: UUID
        var title: String
        var subtitle: String?
        var year: Int?
        var publisher: String?
        var pageCount: Int
        /// 0-based, like `ComicBook.lastReadPage`.
        var lastReadPage: Int
        var isRead: Bool
        /// The app-side cover file this snapshot's copy was made from, so the app can tell a
        /// changed cover from an unchanged one without comparing image bytes.
        var coverSource: String?
    }

    static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("RecentComic", isDirectory: true)
    }

    static var snapshotURL: URL? { directory?.appendingPathComponent("snapshot.json") }
    static var coverURL: URL? { directory?.appendingPathComponent("cover.jpg") }

    static func readSnapshot() -> Snapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    // MARK: Link

    /// `papercomic://open?book=<uuid>`, handed to the app by the widget tap.
    static let urlScheme = "papercomic"

    static func openURL(for bookID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "book", value: bookID.uuidString)]
        return components.url!
    }

    /// The comic a widget link asks for, or nil when `url` isn't one.
    static func bookID(from url: URL) -> UUID? {
        guard url.scheme == urlScheme, url.host == "open",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "book" })?.value else { return nil }
        return UUID(uuidString: value)
    }
}
