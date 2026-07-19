//
//  PageGridView.swift
//  Comic Reader
//
//  Thumbnail overview of every page (the reader's page picker). The current page
//  is highlighted; tapping a thumbnail jumps there.
//

import SwiftUI

struct PageGridView: View {
    let store: PageImageStore
    let pageCount: Int
    let current: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize

    /// Larger thumbnails on the roomy iPad sheet (which `.presentationSizing(.page)` widens to
    /// near full-screen), the compact grid on a phone. `.adaptive` fills the width with as many
    /// as fit at that minimum.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: hSize == .regular ? 140 : 96),
                  spacing: LibraryGridMetrics.spacing)]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: LibraryGridMetrics.spacing) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            Button { onSelect(index) } label: {
                                VStack(spacing: 5) {
                                    PageThumb(store: store, index: index)
                                        .aspectRatio(LibraryGridMetrics.coverAspect, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(index == current ? Color.accentColor : Color.clear,
                                                              lineWidth: 4))
                                    Text("\(index + 1)")
                                        .font(.caption2.weight(index == current ? .bold : .regular))
                                        .foregroundStyle(index == current ? Color.accentColor : Color.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(LibraryGridMetrics.spacing)
                }
                // Defer one runloop so the lazy grid has laid out before we jump to
                // the active page — otherwise the scroll target row may not exist yet.
                .onAppear { DispatchQueue.main.async { proxy.scrollTo(current, anchor: .center) } }
            }
            .navigationTitle("\(pageCount) page\(pageCount == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
    }
}

/// A single page thumbnail, decoded on demand and cached by the store.
struct PageThumb: View {
    let store: PageImageStore
    let index: Int
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            }
        }
        .task(id: index) {
            image = await store.thumbnail(at: index)
        }
    }
}
