//
//  ComicDetailView.swift
//  Comic Reader
//
//  Everything known about one comic, as a sheet. The app's missing middle: until now a tap
//  went straight from a cover to the reader, and only Discover's pinned panel said anything
//  about a comic at all — which left the grid and the list with a file name and a page count.
//
//  The body below the header is `ComicMetadataSection`, the same view the Discover carousel
//  shows inline under its bookmarks. This adds what a sheet needs and the carousel already
//  has: the cover, the title, and a way into the reader.
//

import SwiftUI

struct ComicDetailView: View {
    let book: ComicBook
    /// "The user asked to read this" — NOT "present the reader now". The presenter is expected
    /// to wait for this sheet to actually be gone (its `onDismiss`) before opening the reader:
    /// a full-screen cover raised while the sheet is still dismissing is two presentations at
    /// once, which SwiftUI drops on the floor.
    let onRead: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if book.hasMetadata {
                        ComicMetadataSection(book: book, showsHeading: false)
                    } else {
                        untagged
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle(book.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            DiskImage(url: book.coverURL, contentMode: .fit,
                      maxPixel: LibraryGridMetrics.coverMaxPixel(columns: 3))
                .aspectRatio(book.coverAspect ?? (2.0 / 3.0), contentMode: .fit)
                .frame(width: 104)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.displayTitle)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = book.displaySubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 5) {
                    Text(book.pageCountLabel)
                    if book.progress > 0 { ProgressPie(progress: book.progress, size: 12) }
                    if book.isRead { ReadCheck(size: 12) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button {
                    // Only ask to dismiss; the reader is opened from the sheet's onDismiss so
                    // the two presentations don't overlap. See `onRead`.
                    onRead()
                    dismiss()
                } label: {
                    Label("Read", systemImage: "book")
                        // The accent is a bright orange-yellow — white on it barely reads.
                        .foregroundStyle(.black)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
        }
    }

    /// A comic with no ComicInfo.xml. Says so plainly rather than showing an empty screen —
    /// and says where metadata would come from, since the fix is outside the app.
    private var untagged: some View {
        ContentUnavailableView {
            Label("No metadata", systemImage: "tag.slash")
        } description: {
            Text("This comic has no ComicInfo.xml. Tag it with a tool like ComicTagger, then import it again.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}
