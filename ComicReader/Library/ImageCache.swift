//
//  ImageCache.swift
//  Comic Reader
//
//  A small in-memory cache of decoded cover / thumbnail images so scrolling the
//  library grid doesn't re-read and re-decode the same JPEGs from disk each time a
//  cell reappears. Entries are evicted automatically under memory pressure.
//

import UIKit

enum ImageCache {

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // Bound by decoded bytes, not count: a count limit alone could pin a lot of memory on a big
        // library. Kept deliberately MODEST — the old 96 MB let a cover-heavy browse
        // (Recents/Library/Bookmarks) pin enough decoded memory that a smaller device's
        // allocator/GPU came under pressure, which surfaced as UNRELATED jank: the Paper Effect
        // sliders in Settings turned laggy *after* visiting those views, worse the more comics they
        // showed. Lower on every device (a big grid still scrolls smoothly at 32 MB — a viewport is
        // ~12–20 covers); a little RAM-aware so an 8 GB phone still caches a bit more. NSCache also
        // evicts under system memory pressure, and covers re-decode from disk cheaply via ImageIO.
        let gb = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        cache.totalCostLimit = (gb >= 6 ? 64 : 32) * 1024 * 1024
        return cache
    }()

    static func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: cost(of: image))
    }

    /// Drops all decoded images (covers rebuild on demand from disk). Backs "Clear Cache".
    static func clear() { cache.removeAllObjects() }

    /// Approximate decoded size in bytes (4 bytes per device pixel).
    private static func cost(of image: UIImage) -> Int {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels) * 4
    }
}
