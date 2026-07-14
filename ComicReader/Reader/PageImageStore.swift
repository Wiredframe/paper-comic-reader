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

final class PageImageStore {

    let pageCount: Int

    private let archive: ComicArchive?
    private let work = DispatchQueue(label: "de.wiredframe.comicreader.page-decode", qos: .userInitiated)
    private let cache = NSCache<NSNumber, UIImage>()
    // Keyed by page index AND target size: the page grid asks for small (260px)
    // thumbnails, a bookmark for a full-size (1200px) shot. Keying by index alone let
    // a bookmark receive a previously-cached grid thumbnail — a blurry bookmark card.
    private let thumbCache = NSCache<NSString, UIImage>()

    private var paperEnabled: Bool
    private var paperParams: PaperParams

    init(book: ComicBook, paperEnabled: Bool, paperParams: PaperParams) {
        self.archive = try? ComicArchiveFactory.open(url: book.archiveURL)
        self.pageCount = archive?.pageCount ?? book.pageCount
        self.paperEnabled = paperEnabled
        self.paperParams = paperParams
        cache.countLimit = 7   // current page + ±2 prefetch, with headroom
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
        work.async { [weak self] in
            guard let self else { return }
            self.paperEnabled = enabled
            self.paperParams = params
            self.cache.removeAllObjects()
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

    func thumbnail(at index: Int, maxPixel: CGFloat = 260, completion: @escaping (UIImage?) -> Void) {
        let key = "\(index)#\(Int(maxPixel))" as NSString
        if let cached = thumbCache.object(forKey: key) {
            completion(cached)
            return
        }
        work.async { [weak self] in
            let image = (self?.archive?.pageData(at: index)).flatMap { ImageDownsampler.downsample($0, maxPixel: maxPixel) }
            if let image { self?.thumbCache.setObject(image, forKey: key) }
            DispatchQueue.main.async { completion(image) }
        }
    }
}
