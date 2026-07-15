//
//  PageImageStore.swift
//  Comic Reader
//
//  Decodes comic pages off the main thread, applies the paper effect, and caches
//  the display-ready images. Archive access is serialised on one queue (the ZIP /
//  RAR readers are not thread-safe). Also vends small thumbnails for the page
//  grid and bookmarks.
//

import UIKit

/// `@unchecked Sendable` is the design, not a shortcut: every archive read and every mutation
/// of `paperEnabled` / `paperParams` happens on the private `work` queue (the ZIP/RAR readers
/// are not thread-safe), and both caches are `NSCache`, which is. The type is handed between
/// the main actor and that queue on every page request. The archive is opened once on
/// `openQueue` before the store is handed to anyone (see `open`), so that can't race a read.
final class PageImageStore: @unchecked Sendable {

    /// 0 when the archive couldn't be opened (missing/corrupt file after import) — the
    /// reader shows an "unavailable" state rather than a run of blank pages, since trusting
    /// the stale metadata page count would render `pageCount` empty slots.
    let pageCount: Int

    private let bookID: UUID
    private let archive: ComicArchive?
    private let work = DispatchQueue(label: "de.wiredframe.comicreader.page-decode", qos: .userInitiated)
    /// Opening is one shot per reader session, so it gets its own queue rather than sharing
    /// `work` — nothing is waiting behind it, and `work` doesn't exist until init returns.
    private static let openQueue = DispatchQueue(label: "de.wiredframe.comicreader.archive-open",
                                                 qos: .userInitiated)
    private let cache = NSCache<NSNumber, UIImage>()
    // Keyed by page index AND target size: the page grid asks for small (260px)
    // thumbnails, a bookmark for a full-size (1200px) shot. Keying by index alone let
    // a bookmark receive a previously-cached grid thumbnail — a blurry bookmark card.
    private let thumbCache = NSCache<NSString, UIImage>()

    private var paperEnabled: Bool
    private var paperParams: PaperParams

    /// Opens `url` off the main thread and hands back the ready store.
    ///
    /// ALWAYS open through this, never by calling `init` directly on the main actor. Opening an
    /// archive is file I/O whose cost scales with the archive, not with the page being read:
    /// ZIPFoundation walks the CBZ's central directory entry by entry and seeks to each page's
    /// *local* header on the way — offsets scattered across the whole file — plus a second seek
    /// past a page's compressed bytes for the streamed ZIPs that carry a data descriptor; a CBR
    /// is worse still, since UnrarKit skips through every RAR header end to end. On a big comic,
    /// or one whose bytes aren't in the page cache yet, that is hundreds of milliseconds to
    /// seconds — which is exactly how long the app froze while `init` ran on the main thread.
    static func open(bookID: UUID, url: URL,
                     paperEnabled: Bool, paperParams: PaperParams) async -> PageImageStore {
        await withCheckedContinuation { continuation in
            openQueue.async {
                continuation.resume(returning: PageImageStore(bookID: bookID, url: url,
                                                              paperEnabled: paperEnabled,
                                                              paperParams: paperParams))
            }
        }
    }

    /// Private so the blocking open can't accidentally be put back on the main actor — see `open`.
    /// Takes the book's id and URL rather than the `ComicBook` itself: the model belongs to the
    /// main actor's SwiftData context and must not be read from the queue this runs on.
    private init(bookID: UUID, url: URL, paperEnabled: Bool, paperParams: PaperParams) {
        self.bookID = bookID
        self.archive = try? ComicArchiveFactory.open(url: url)
        self.pageCount = archive?.pageCount ?? 0
        self.paperEnabled = paperEnabled
        self.paperParams = paperParams
        cache.countLimit = 10   // current page + double-page spread + ±2 prefetch fan-out
        // Bound the grid/bookmark thumbnails by decoded bytes so a long comic's page grid
        // (a 260px thumb each) can't grow the cache without limit for the reader session.
        thumbCache.totalCostLimit = 32 * 1024 * 1024   // ~32 MB
    }

    // MARK: Display images (paper applied)

    func cachedImage(at index: Int) -> UIImage? {
        cache.object(forKey: NSNumber(value: index))
    }

    /// Returns the display image for `index`. Completion runs on the main queue.
    func requestImage(at index: Int, maxPixel: CGFloat, completion: @escaping (Int, UIImage?) -> Void) {
        if let cached = cachedImage(at: index) {
            completion(index, cached)
            return
        }
        work.async { [weak self] in
            guard let self else { return }
            let image = self.render(index: index, maxPixel: maxPixel)
            if let image { self.cache.setObject(image, forKey: NSNumber(value: index)) }
            DispatchQueue.main.async { completion(index, image) }
        }
    }

    func prefetch(around index: Int, maxPixel: CGFloat) {
        // Keep the neighbours ±2 decoded so page turns don't visibly fade in.
        for i in [index + 1, index - 1, index + 2, index - 2]
        where (0..<pageCount).contains(i) && cachedImage(at: i) == nil {
            requestImage(at: i, maxPixel: maxPixel) { _, _ in }
        }
    }

    /// Rebuilds cached images with a new paper setting.
    func setPaper(enabled: Bool, params: PaperParams) {
        // Clear the display cache synchronously: the reload that follows (paperVersion →
        // reloadCurrent) reads the cache on the main thread, and an async clear could run
        // *after* it, leaving the visible page rendered with the previous paper setting.
        // NSCache is thread-safe; the params are still set on the work queue where render()
        // reads them, and this call is enqueued before any reload's render, so re-decodes
        // pick up the new params.
        cache.removeAllObjects()
        work.async { [weak self] in
            self?.paperEnabled = enabled
            self?.paperParams = params
        }
    }

    private func render(index: Int, maxPixel: CGFloat) -> UIImage? {
        guard let data = archive?.pageData(at: index) else { return nil }
        guard var image = ImageDownsampler.downsample(data, maxPixel: maxPixel) ?? UIImage(data: data) else {
            return nil
        }
        if paperEnabled {
            image = PaperFilter.shared.apply(to: image, params: paperParams) ?? image
        }
        return image
    }

    // MARK: Thumbnails (no paper — for the page grid / bookmarks)

    /// A page thumbnail for the page grid (small) or a bookmark shot (full size). Checked in
    /// order: in-memory cache → on-disk cache (small thumbnails only) → decode from archive.
    /// Small thumbnails are persisted to `Storage.pageThumbs` so reopening the grid doesn't
    /// re-extract and re-downsample every page. Honours task cancellation, so fast grid
    /// scrolling doesn't backlog the decode queue with pages already scrolled past.
    func thumbnail(at index: Int, maxPixel: CGFloat = 260) async -> UIImage? {
        // Kept as a String (Sendable) so the decode closure below doesn't capture an NSString.
        let key = "\(index)#\(Int(maxPixel))"
        if let cached = thumbCache.object(forKey: key as NSString) { return cached }
        // Only the small, oft-revisited grid thumbnails are worth a disk cache; a bookmark's
        // one-off full-size shot isn't.
        let persist = maxPixel <= 400
        let flag = CancelFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                work.async { [weak self] in
                    guard let self, !flag.isCancelled else { return continuation.resume(returning: nil) }
                    if persist, let disk = self.diskThumb(index: index, maxPixel: maxPixel) {
                        self.thumbCache.setObject(disk, forKey: key as NSString, cost: Self.cost(of: disk))
                        return continuation.resume(returning: disk)
                    }
                    let image = (self.archive?.pageData(at: index))
                        .flatMap { ImageDownsampler.downsample($0, maxPixel: maxPixel) }
                    if let image {
                        self.thumbCache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
                        if persist { ImageDownsampler.writeJPEG(image, to: self.thumbDiskURL(index: index, maxPixel: maxPixel)) }
                    }
                    continuation.resume(returning: image)
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }

    private func thumbDiskURL(index: Int, maxPixel: CGFloat) -> URL {
        Storage.pageThumbs(for: bookID).appendingPathComponent("\(index)@\(Int(maxPixel)).jpg")
    }

    private func diskThumb(index: Int, maxPixel: CGFloat) -> UIImage? {
        guard let data = try? Data(contentsOf: thumbDiskURL(index: index, maxPixel: maxPixel)) else { return nil }
        return UIImage(data: data)
    }

    /// Approximate decoded size in bytes (4 per device pixel), for the thumbnail cost limit.
    private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale) * 4
    }
}

/// Thread-safe cancellation flag: set from a task-cancellation handler, read on the decode
/// queue so a superseded thumbnail request skips its decode. Unchecked because the lock is
/// the synchronisation.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
