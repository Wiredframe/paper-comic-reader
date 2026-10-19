//
//  LibraryStore.swift
//  Comic Reader
//
//  Opening the SwiftData store, and what happens when that fails.
//
//  The store is everything the library knows: reading progress, bookmarks, favorites, metadata,
//  and which `<uuid>.cbz` in Application Support is which comic. Losing it is losing years of
//  reading, so a failed open is never answered by deleting it:
//
//   1. The open is retried. Most failures are transient (file protection while the device is
//      still locked, a previous process not done releasing the file).
//   2. If the store can't even be read, or the disk is all but full, nothing is touched. The app
//      runs on a temporary in-memory library and says so; the next launch tries again.
//   3. Only then is the store MOVED aside into `StoreBackups/<timestamp>/`, never deleted, and a
//      reset is recorded so the app can offer to rebuild the library from the safety snapshot
//      (see `LibrarySnapshot`).
//

import Foundation
import SwiftData

enum LibraryStore {

    /// The container the app runs on, and whether it is the real library or a stand-in.
    struct Opened {
        let container: ModelContainer
        /// True when the store couldn't be opened and the app is running on an in-memory library
        /// that vanishes on quit. Nothing may be written about the library in that state: not the
        /// safety snapshot, not the sample comics.
        let isTemporary: Bool
    }

    static let schema = Schema([ComicBook.self, Bookmark.self])

    /// How many moved-aside stores are kept. Each is metadata only, so a few cost almost nothing.
    static let keptBackups = 5

    static func open() -> Opened {
        let config = ModelConfiguration(schema: schema)
        if let container = openWithRetries(config) {
            return Opened(container: container, isTemporary: false)
        }

        // A store that can't be read at all (protected data before the first unlock) or a disk
        // with no room to open it would fail the same way empty. Neither says anything about the
        // store itself, so it is left exactly where it is.
        if isUnreadable(config.url) || isLowOnSpace(config.url) {
            return temporary()
        }

        let backups = Storage.appSupport.appendingPathComponent("StoreBackups", isDirectory: true)
        guard moveAside(storeAt: config.url, into: backups) != nil else { return temporary() }
        LibraryReset.isPending = true
        if let container = try? ModelContainer(for: schema, configurations: config) {
            return Opened(container: container, isTemporary: false)
        }
        return temporary()
    }

    /// The first try plus three more, 0.4 s apart.
    private static func openWithRetries(_ config: ModelConfiguration) -> ModelContainer? {
        for attempt in 0..<4 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.4) }
            if let container = try? ModelContainer(for: schema, configurations: config) {
                return container
            }
        }
        return nil
    }

    private static func temporary() -> Opened {
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return Opened(container: try ModelContainer(for: schema, configurations: memory),
                          isTemporary: true)
        } catch {
            fatalError("Failed to create an in-memory ModelContainer: \(error)")
        }
    }

    // MARK: Moving aside

    /// Moves the store and its `-wal`/`-shm` into a new `<yyyy-MM-dd-HHmmss>` folder under
    /// `backups`, then prunes all but the newest `keptBackups`. Returns the folder, or nil when
    /// nothing could be moved, in which case the store is still in place.
    @discardableResult
    static func moveAside(storeAt url: URL, into backups: URL, now: Date = .now) -> URL? {
        let fm = Storage.fm
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        var folder = backups.appendingPathComponent(formatter.string(from: now), isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: folder.path) {
            folder = backups.appendingPathComponent("\(formatter.string(from: now))-\(suffix)",
                                                    isDirectory: true)
            suffix += 1
        }
        guard (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else {
            return nil
        }

        var movedStore = false
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            guard fm.fileExists(atPath: file.path) else { continue }
            let target = folder.appendingPathComponent(file.lastPathComponent)
            if (try? fm.moveItem(at: file, to: target)) != nil, suffix.isEmpty { movedStore = true }
        }
        // No store file means there was nothing to recover from in the first place, which is
        // still a reset worth recording. A store that refused to move is not: it is still there.
        guard movedStore || !fm.fileExists(atPath: url.path) else { return nil }

        prune(backups, keeping: keptBackups)
        return folder
    }

    /// Keeps the newest `count` folders. The names sort by time, so newest is last.
    static func prune(_ backups: URL, keeping count: Int) {
        let folders = ((try? Storage.fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for folder in folders.dropLast(count) {
            try? Storage.fm.removeItem(at: folder)
        }
    }

    // MARK: Telling a bad store from a bad moment

    /// True when the store file exists but can't be read, which is what file protection looks
    /// like before the first unlock after a restart.
    private static func isUnreadable(_ url: URL) -> Bool {
        guard Storage.fm.fileExists(atPath: url.path) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) == nil
    }

    /// Under 50 MB free. SQLite needs room for its journal to open at all.
    private static func isLowOnSpace(_ url: URL) -> Bool {
        let folder = url.deletingLastPathComponent()
        guard let free = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            .volumeAvailableCapacity else { return false }
        return free < 50 * 1024 * 1024
    }
}

/// Whether the library was started over after its store couldn't be opened. While it is pending,
/// the safety snapshot is frozen (so the empty library can't overwrite it) and the app offers to
/// restore from it. Cleared by either answer.
enum LibraryReset {

    private static let key = "library.resetPending"

    static var isPending: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
