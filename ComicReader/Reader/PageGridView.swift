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
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            Button { onSelect(index) } label: {
                                VStack(spacing: 5) {
                                    PageThumb(store: store, index: index)
                                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
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
                    .padding()
                }
                // Defer one runloop so the lazy grid has laid out before we jump to
                // the active page — otherwise the scroll target row may not exist yet.
                .onAppear { DispatchQueue.main.async { proxy.scrollTo(current, anchor: .center) } }
            }
            .navigationTitle("\(pageCount) pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .preferredColorScheme(.dark)
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
            store.thumbnail(at: index) { loaded in image = loaded }
        }
    }
}
