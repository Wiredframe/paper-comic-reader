//
//  LibrarySource.swift
//  Comic Reader
//
//  The optional "library folder": one place on a file server / iCloud (anything the
//  Files app can reach) that the app scans for comics. Unlike a single import, a
//  folder-scanned comic is NOT copied in — only its cover and metadata are. The
//  archive bytes are fetched on demand when the comic is opened, and can be dropped
//  again to save space (see ComicBook.sourceRelativePath and Importer.download/evict).
//
//  Access to a folder outside our container is security-scoped: the folder is picked
//  once, and a bookmark persists that grant across launches. Resolving a bookmark to a
//  disconnected share can block on the network, so resolve/enumerate off the main actor.
//

import Foundation

enum LibrarySource {

    private static let bookmarkKey = "library.sourceFolderBookmark"
    private static let displayKey  = "library.sourceFolderName"

    enum SourceError: Error {
        case notConfigured      // no folder has been chosen
        case unresolved         // the bookmark won't resolve — share offline, or folder gone
        case fileMissing        // the folder resolved, but this comic's file isn't in it
        case copyFailed         // the bytes wouldn't copy into local storage
        case cancelled          // the download was cancelled (reader closed mid-fetch)
    }

    // MARK: Configured state (main-actor cheap — reads UserDefaults only, no resolution)

    static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// A human label for the chosen folder — its name, for the Settings row. Nil when unset.
    static var displayName: String? {
        UserDefaults.standard.string(forKey: displayKey)
    }

    /// Persists the picked folder as a security-scoped bookmark. `url` comes from the folder
    /// picker and is already scoped; the bookmark is created while that grant is held so it
    /// carries the scope forward. Throws if the bookmark can't be made.
    static func setFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // No `.withSecurityScope` here: that option is macOS-only. On iOS a bookmark made from
        // a picker URL is security-scoped implicitly, and resolves back the same way.
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: bookmarkKey)
        defaults.set(url.lastPathComponent.isEmpty ? "Selected folder" : url.lastPathComponent,
                     forKey: displayKey)
    }

    /// Forgets the folder. Existing folder-backed comics are left in place: they simply fail to
    /// resolve when next opened, which surfaces the reader's "update path / pick a file" prompt —
    /// the deliberately implicit "source missing" path, never a background sweep.
    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: displayKey)
    }

    // MARK: Resolution + scoped access (call OFF the main actor — may block on the network)

    /// Resolves the stored bookmark to the folder URL. A stale bookmark (the volume remounted
    /// elsewhere) is re-saved when it still resolves, so it keeps working next time. Returns a
    /// URL on which the caller must `startAccessingSecurityScopedResource()` — use `withFolderAccess`.
    static func resolveFolder() throws -> URL {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw SourceError.notConfigured
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            throw SourceError.unresolved
        }
        if stale {
            // Best-effort refresh; ignore failure — the current URL still works this time.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }

    /// Runs `body` with the library folder security-scope held. The single place that owns the
    /// start/stop pairing, so the scope can't leak. Throws `.notConfigured`/`.unresolved` before
    /// `body` runs if the folder can't be reached.
    static func withFolderAccess<T>(_ body: (URL) throws -> T) throws -> T {
        let folder = try resolveFolder()
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        return try body(folder)
    }

    // MARK: Enumeration

    /// The comic files under `folder`, each with its path relative to `folder` (the stable
    /// identity a folder-backed entry stores). Recurses so a foldered collection still scans,
    /// and matches by extension only: probing magic bytes on every file would mean a network
    /// read apiece, and a library folder is CBZs by convention. Call inside `withFolderAccess`.
    static func comicFiles(in folder: URL) -> [(url: URL, relativePath: String)] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }

        var result: [(URL, String)] = []
        for case let url as URL in walker {
            let ext = url.pathExtension.lowercased()
            guard ext == "cbz" || ext == "zip" else { continue }
            if let isFile = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
               isFile == false { continue }
            result.append((url, relativePath(of: url, in: folder)))
        }
        return result
    }

    /// `child` expressed relative to `folder` — "Topolino/1900.cbz". Falls back to the file name
    /// if `child` isn't genuinely under `folder`. The prefix is compared on a path boundary
    /// ("/base/") so a sibling folder whose name merely starts the same — Comics vs ComicsExtra —
    /// isn't mistaken for a descendant.
    static func relativePath(of child: URL, in folder: URL) -> String {
        let base = folder.standardizedFileURL.path
        let path = child.standardizedFileURL.path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard path.hasPrefix(prefix) else { return child.lastPathComponent }
        let rel = String(path.dropFirst(prefix.count))
        return rel.isEmpty ? child.lastPathComponent : rel
    }

    /// Whether `url` lives inside `folder` — the same boundary-aware test `relativePath` uses, for
    /// callers deciding if a picked file belongs to the library folder (see `Importer.relink`).
    static func contains(_ url: URL, in folder: URL) -> Bool {
        let base = folder.standardizedFileURL.path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return url.standardizedFileURL.path.hasPrefix(prefix)
    }
}
