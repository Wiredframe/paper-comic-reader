//
//  ComicBook.swift
//  Comic Reader
//
//  SwiftData model for one imported comic. Only metadata lives here; the archive
//  bytes and images are files on disk (see Storage).
//

import Foundation
import SwiftData

@Model
final class ComicBook {

    @Attribute(.unique) var id: UUID
    var title: String
    var fileName: String        // archive file in Storage.comics
    var pageCount: Int
    var dateAdded: Date
    var dateOpened: Date?       // last time it was opened — drives the Recents tab
    var lastReadPage: Int       // 0-based, for resume
    var coverName: String?      // cover file in Storage.covers
    var isRead: Bool = false     // user-set "read" flag; independent of bookmarks. Set
                                 // manually from the cover menu, or automatically once
                                 // the reader reaches the last page. Default via the
                                 // property initializer keeps SwiftData migration additive.
    var openCount: Int = 0       // how often the comic was opened — read as "popularity"
                                 // by the library sort and the Discover modes. Monotonic:
                                 // deliberately NOT cleared by Recents' "Clear", which only
                                 // forgets `dateOpened`. Defaulted, so migration stays additive.
    var coverAspect: Double?     // cover width / height, captured at import. Stored because
                                 // DiskImage fills whatever frame it's given and can't report
                                 // the artwork's shape — Discover needs it to size a card that
                                 // doesn't crop. Optional, so migration stays additive.

    // MARK: ComicInfo.xml
    //
    // Read from the archive at import (see ComicInfoParser) and stored here so no view has to
    // touch the archive to describe a comic — that's what lets the grid, the list, Discover and
    // the detail sheet all render metadata at their own level of detail. Every field is
    // optional and `stories` defaults, so a store written before this existed migrates without
    // a mapping model. Comics imported earlier are filled in by `Importer.backfillMetadata`.

    var series: String?          // "Topolino"
    var issueNumber: String?     // "1900" — a String, not an Int: issues are numbered "1900",
                                 // but also "Annual 2", "3.5" and "½".
    var issueTitle: String?      // <Title> — usually the lead story, NOT the file name
    var summary: String?         // <Summary> raw. Kept even when `stories` parsed out of it:
                                 // it's the fallback whenever the index format doesn't match.
    var publisher: String?
    var year: Int?
    var month: Int?
    var day: Int?
    var writers: String?         // <Writer>/<Penciller>/<Inker>: already comma-joined by the
    var pencillers: String?      // tagger. Shown only when there's no story list — with one,
    var inkers: String?          // the per-story credits say the same thing, but attributed.
    var characters: String?
    var languageISO: String?
    var webURL: String?
    var notes: String?           // provenance, e.g. "Metadati da I.N.D.U.C.K.S. …"

    /// The issue's index — the stories, covers and text pieces inside it. A Codable value
    /// type rather than a related @Model: nothing queries a story on its own, and keeping it
    /// an attribute means adding metadata doesn't add an entity to the schema.
    var stories: [ComicStory] = []

    /// Whether the archive's ComicInfo.xml has been looked for. Distinguishes "untagged" from
    /// "not read yet", which no combination of the fields above can: both look like all-nil.
    /// Defaults false, so comics imported before this feature get read exactly once, on the
    /// next launch (see `Importer.backfillMetadata`) — and an untagged comic isn't reopened on
    /// every launch to find nothing again. Defaulted, so migration stays additive.
    var metadataScanned: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark] = []

    init(id: UUID = UUID(),
         title: String,
         fileName: String,
         pageCount: Int,
         coverName: String?,
         coverAspect: Double? = nil) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.pageCount = pageCount
        self.dateAdded = .now
        self.dateOpened = nil
        self.lastReadPage = 0
        self.coverName = coverName
        self.coverAspect = coverAspect
    }

    var archiveURL: URL { Storage.comicURL(fileName) }
    var coverURL: URL? { coverName.map(Storage.coverURL) }

    /// Copies parsed ComicInfo.xml values onto the book. A nil `info` (untagged comic, or one
    /// whose XML holds nothing useful) clears the fields rather than leaving stale ones behind,
    /// so re-reading an archive whose metadata was stripped does the right thing.
    func apply(_ info: ComicInfoData?) {
        metadataScanned = true
        series = info?.series
        issueNumber = info?.number
        issueTitle = info?.title
        summary = info?.summary
        publisher = info?.publisher
        year = info?.year
        month = info?.month
        day = info?.day
        writers = info?.writer
        pencillers = info?.penciller
        inkers = info?.inker
        characters = info?.characters
        languageISO = info?.languageISO
        webURL = info?.web
        notes = info?.notes
        stories = info?.stories ?? []
    }

    // MARK: Display
    //
    // Every view names a comic through these rather than through `title`, so metadata reaches
    // the grid, the list, Discover and the reader without any of them knowing about ComicInfo.
    // `title` stays the imported file name: it's the archive's identity, it's what the user
    // sees in Files, and it's all a comic without metadata has.

    /// What to call this comic: "Topolino 1900" once it carries metadata, the file name
    /// otherwise.
    var displayTitle: String {
        guard let series = series?.nonEmpty else { return title }
        guard let issueNumber = issueNumber?.nonEmpty else { return series }
        return "\(series) \(issueNumber)"
    }

    /// The line under the title — the issue's own title. Nil when there's nothing to add:
    /// no metadata, or it would only repeat what `displayTitle` already says.
    var displaySubtitle: String? {
        guard let issueTitle = issueTitle?.nonEmpty, issueTitle != displayTitle else { return nil }
        return issueTitle
    }

    /// Whether this comic has anything to fill a detail view with.
    var hasMetadata: Bool {
        !stories.isEmpty || summary?.nonEmpty != nil || series?.nonEmpty != nil
            || publisher?.nonEmpty != nil || characters?.nonEmpty != nil || year != nil
    }

    /// "26 April 1992" / "April 1992" / "1992" — as much of the cover date as the tagger gave
    /// us, in the reader's locale. Out-of-range values are treated as absent rather than
    /// trusted: the date is decoration, and a tagger's "Month 13" shouldn't render as garbage.
    var dateLabel: String? {
        guard let year, (1...9999).contains(year) else { return nil }
        guard let month, (1...12).contains(month) else { return String(year) }
        var components = DateComponents(year: year, month: month)
        if let day, (1...31).contains(day) { components.day = day }
        guard let date = Calendar.current.date(from: components) else { return String(year) }
        return components.day == nil
            ? date.formatted(.dateTime.month(.wide).year())
            : date.formatted(.dateTime.day().month(.wide).year())
    }

    /// "6 stories" — how many entries the index holds, ignoring covers and other non-story
    /// pieces where the tagger labelled them. Nil when there's no index.
    var storyCountLabel: String? {
        guard !stories.isEmpty else { return nil }
        let n = stories.count
        return "\(n) \(n == 1 ? "story" : "stories")"
    }

    /// Series first, then issue number the way a human reads it ("Topolino 2" before
    /// "Topolino 10"). Comics without a series sort by file name, after the ones with.
    func sortsBefore(_ other: ComicBook) -> Bool {
        let lhs = series?.nonEmpty, rhs = other.series?.nonEmpty
        switch (lhs, rhs) {
        case let (l?, r?) where l.localizedStandardCompare(r) != .orderedSame:
            return l.localizedStandardCompare(r) == .orderedAscending
        case (nil, _?): return false      // unfiled comics go last
        case (_?, nil): return true
        default: break                    // same series, or both unfiled
        }
        let lhsNumber = issueNumber?.nonEmpty ?? title
        let rhsNumber = other.issueNumber?.nonEmpty ?? other.title
        return lhsNumber.localizedStandardCompare(rhsNumber) == .orderedAscending
    }

    /// 0…1 read progress for the cover pie.
    var progress: Double {
        guard pageCount > 1 else { return lastReadPage > 0 ? 1 : 0 }
        return min(1, max(0, Double(lastReadPage) / Double(pageCount - 1)))
    }

    /// "12 pages" / "1 page" — inflected for the cover and list captions.
    var pageCountLabel: String { "\(pageCount) page\(pageCount == 1 ? "" : "s")" }

    /// "Opened 7 times" / "Opened once" / "Never opened" — for the Discover info panel.
    var openCountLabel: String {
        switch openCount {
        case 0:  return "Never opened"
        case 1:  return "Opened once"
        default: return "Opened \(openCount) times"
        }
    }
}
