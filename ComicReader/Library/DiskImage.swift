//
//  DiskImage.swift
//  Comic Reader
//
//  Loads a locally-stored image file (cover / thumbnail) off the main thread and
//  fades it in. Covers and thumbnails are already downsampled, so this stays
//  cheap.
//

import SwiftUI
import UIKit

struct DiskImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

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
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { image = nil; return }
        let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.15)) { image = loaded }
    }
}
