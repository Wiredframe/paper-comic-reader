//
//  ImageDownsampler.swift
//  Comic Reader
//
//  Efficient image decoding via ImageIO: thumbnails are produced without ever
//  materialising the full-size bitmap, which keeps memory low when building
//  covers and page-grid thumbnails from large comic pages.
//

import UIKit
import ImageIO

enum ImageDownsampler {

    /// Longest side (device pixels) for library-card images — cover thumbnails and
    /// bookmark page shots. Both render at the same full-width size in their grids
    /// (down to a single column), so they share this target; it's large enough to
    /// stay crisp at one column on the biggest displays. Stored images are decoded
    /// down further per cell at display time (see `DiskImage.maxPixel`).
    static let libraryCardPixel: CGFloat = 1200

    /// Decodes `data` and returns an image whose longest side is at most
    /// `maxPixel` device pixels, decoded straight to that size.
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    @discardableResult
    static func writeJPEG(_ image: UIImage, to url: URL, quality: CGFloat = 0.85) -> Bool {
        guard let data = image.jpegData(compressionQuality: quality) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
