//
//  ThumbnailProvider.swift
//  ComicThumbnail
//
//  A QuickLook thumbnail extension: it draws a CBZ's cover (its first page) so the
//  Files app, Spotlight and "Recents" show the actual comic instead of the generic
//  ZIP icon. Registered for our exported `de.wiredframe.comicreader.cbz` type, so
//  the system calls it for every .cbz — wherever it lives, imported or not.
//
//  Extensions run in a tight-memory process, so we reuse the same on-demand decode
//  the app relies on: ComicArchive seeks to a single entry (never inflates the whole
//  archive) and ImageDownsampler decodes straight to the requested size (never
//  materialises the full-resolution page). Both files are compiled into this target
//  as well as the app — see project.yml.
//

import QuickLookThumbnailing
import UIKit

final class ThumbnailProvider: QLThumbnailProvider {

    private enum ThumbnailError: Error {
        case noCover        // archive opened but held no readable page
        case decodeFailed   // the cover bytes weren't a decodable image
    }

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        do {
            let archive = try ComicArchive(url: request.fileURL)
            guard let coverData = archive.pageData(at: 0) else {
                return handler(nil, ThumbnailError.noCover)
            }

            // Decode to the largest edge QuickLook asked for, in device pixels — no
            // point rendering finer than the slot the thumbnail will sit in.
            let maxPixel = max(request.maximumSize.width, request.maximumSize.height) * request.scale
            guard let cover = ImageDownsampler.downsample(coverData, maxPixel: maxPixel) else {
                return handler(nil, ThumbnailError.decodeFailed)
            }

            // Reply sized to the cover's aspect (not the full box), so QuickLook frames
            // the page edge-to-edge instead of letterboxing it onto a padded canvas.
            let size = Self.aspectFit(cover.size, within: request.maximumSize)
            let reply = QLThumbnailReply(contextSize: size) {
                cover.draw(in: CGRect(origin: .zero, size: size))
                return true
            }
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }

    /// The largest size sharing `image`'s aspect ratio that fits inside `box`.
    private static func aspectFit(_ image: CGSize, within box: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return box }
        let scale = min(box.width / image.width, box.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
}
