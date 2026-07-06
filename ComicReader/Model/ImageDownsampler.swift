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

    /// Full-resolution decode (used by the reader for the on-screen page).
    static func decode(_ data: Data) -> UIImage? { UIImage(data: data) }

    @discardableResult
    static func writeJPEG(_ image: UIImage, to url: URL, quality: CGFloat = 0.85) -> Bool {
        guard let data = image.jpegData(compressionQuality: quality) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
