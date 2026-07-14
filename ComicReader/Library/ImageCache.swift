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
        // Bound by decoded bytes, not count: full-size covers are ~1200px, so a
        // count limit alone could pin a lot of memory on a big library. NSCache also
        // evicts under system memory pressure.
        cache.totalCostLimit = 96 * 1024 * 1024   // ~96 MB of decoded images
        return cache
    }()

    static func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString, cost: cost(of: image))
    }

    /// Approximate decoded size in bytes (4 bytes per device pixel).
    private static func cost(of image: UIImage) -> Int {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        return Int(pixels) * 4
    }
}
