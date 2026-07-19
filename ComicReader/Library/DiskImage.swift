//
//  DiskImage.swift
//  Comic Reader
//
//  Loads a locally-stored image file (cover / thumbnail) off the main thread and
//  fades it in. Decoded images are held in a shared in-memory cache, so a cover
//  that scrolls out of and back into the grid isn't re-read and re-decoded. Covers
//  and thumbnails are already downsampled; passing `maxPixel` shrinks them further
//  for small cells.
//

import SwiftUI
import UIKit

struct DiskImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// If set, the image is decoded down to at most this many device pixels on its
    /// longest side — worth it for small cells (covers are stored at 1200px).
    var maxPixel: CGFloat? = nil

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .task(id: cacheKey) { await load() }
    }

    /// Cache / reload key: the same file at a different target size is a different
    /// entry, and changing it re-runs `.task`.
    private var cacheKey: String { "\(url?.path ?? "")#\(maxPixel.map { Int($0) } ?? 0)" }

    private func load() async {
        guard let url else { image = nil; return }
        let key = cacheKey
        if let cached = ImageCache.image(forKey: key) {
            image = cached
            return
        }
        let maxPixel = maxPixel
        let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
            // Decode from the file URL: for the common (downsampled) case ImageIO streams only the
            // thumbnail's worth of bytes, so a big cover never fully materialises in memory — the
            // difference that keeps a large, fast-scrolled grid off the memory ceiling. The
            // full-size branch (no maxPixel) likewise decodes from disk without an explicit buffer.
            if let maxPixel { return ImageDownsampler.downsample(url: url, maxPixel: maxPixel) }
            return UIImage(contentsOfFile: url.path)
        }.value
        guard !Task.isCancelled else { return }
        if let loaded { ImageCache.set(loaded, forKey: key) }
        withAnimation(.easeOut(duration: 0.15)) { image = loaded }
    }
}
