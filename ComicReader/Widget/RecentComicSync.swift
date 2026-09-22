//
//  RecentComicSync.swift
//  Comic Reader
//
//  Keeps the Recent Comic widget's snapshot in step with the top of Recents. Called wherever
//  that can change in the foreground (a comic opened, its progress saved, Recents cleared or
//  trimmed) and once more
//  on launch and on leaving the foreground, which catches the rarer paths (a deleted comic, a
//  restored backup) without each of them having to know the widget exists.
//

import Foundation
import SwiftData
import WidgetKit

@MainActor
enum RecentComicSync {

    static func refresh(in context: ModelContext) {
        guard let directory = RecentComicShared.directory,
              let snapshotURL = RecentComicShared.snapshotURL,
              let coverURL = RecentComicShared.coverURL else { return }

        var descriptor = FetchDescriptor<ComicBook>(
            predicate: #Predicate { $0.dateOpened != nil },
            sortBy: [SortDescriptor(\.dateOpened, order: .reverse)])
        descriptor.fetchLimit = 1
        let book = (try? context.fetch(descriptor))?.first

        let snapshot = book.map {
            RecentComicShared.Snapshot(bookID: $0.id, title: $0.displayTitle,
                                       subtitle: $0.displaySubtitle, year: $0.year,
                                       publisher: $0.publisher?.nonEmpty, pageCount: $0.pageCount,
                                       lastReadPage: $0.lastReadPage, isRead: $0.isRead,
                                       coverSource: $0.coverName)
        }
        let current = RecentComicShared.readSnapshot()
        let fm = FileManager.default
        // A cover copy that failed earlier (the source was missing at the time) is retried
        // whenever the app refreshes, not only when something else about the comic changes.
        let coverMissing = book?.coverURL.map { fm.fileExists(atPath: $0.path) } == true
            && !fm.fileExists(atPath: coverURL.path)
        // Nothing the widget shows changed: skip the write AND the timeline reload, which the
        // system budgets.
        guard snapshot != current || coverMissing else { return }

        if let snapshot, let book {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if snapshot.coverSource != current?.coverSource || !fm.fileExists(atPath: coverURL.path) {
                try? fm.removeItem(at: coverURL)
                if let source = book.coverURL { try? fm.copyItem(at: source, to: coverURL) }
            }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: snapshotURL, options: .atomic)
            }
        } else {
            try? fm.removeItem(at: snapshotURL)
            try? fm.removeItem(at: coverURL)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: RecentComicShared.widgetKind)
    }
}
