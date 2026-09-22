//
//  RecentComicWidget.swift
//  Comic Widget
//
//  The Recent Comic widget: the cover of the comic at the top of Recents, edge to edge, and a
//  tap that opens it where it was left. Nothing else on it, on purpose. The corners are the
//  system's own container shape, never drawn here.
//

import SwiftUI
import UIKit
import WidgetKit

@main
struct ComicWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecentComicWidget()
    }
}

struct RecentComicWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RecentComicShared.widgetKind, provider: RecentComicProvider()) { entry in
            RecentComicView(entry: entry)
        }
        .configurationDisplayName("Recent Comic")
        .description("The comic you read last. Tap to continue where you left off.")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
        // The cover IS the widget: StandBy and the lock screen must not strip it away as if it
        // were decoration.
        .containerBackgroundRemovable(false)
    }

    /// Extra Large Portrait only exists from iOS 27; on 26 the widget is Small only. The compiler
    /// check is for the SDK: the family doesn't exist before the iOS 27 SDK (Swift 6.4, Xcode 27),
    /// and the GitHub release runner still builds with Xcode 26, whose sideload build then ships
    /// the Small widget only.
    private static var families: [WidgetFamily] {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return [.systemSmall, .systemExtraLargePortrait]
        }
        #endif
        return [.systemSmall]
    }
}

struct RecentComicEntry: TimelineEntry {
    let date: Date
    let snapshot: RecentComicShared.Snapshot?
    let cover: UIImage?
    /// A deep tone of the cover's most vivid colour, for the Extra Large tile's info panel.
    var panelColor: UIColor? = nil

    static let empty = RecentComicEntry(date: .now, snapshot: nil, cover: nil)
}

struct RecentComicProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentComicEntry { .empty }

    func getSnapshot(in context: Context, completion: @escaping (RecentComicEntry) -> Void) {
        completion(load(for: context))
    }

    /// A single entry and no refresh schedule: the app reloads the timeline itself whenever what
    /// the widget shows changes (see RecentComicSync).
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentComicEntry>) -> Void) {
        completion(Timeline(entries: [load(for: context)], policy: .never))
    }

    private func load(for context: Context) -> RecentComicEntry {
        guard let snapshot = RecentComicShared.readSnapshot() else { return .empty }
        // Decoded to the widget's own size, not the stored cover's: widgets run under a tight
        // memory ceiling, and the Extra Large tile is the only one that needs the full cover.
        let side = max(context.displaySize.width, context.displaySize.height) * 3
        let cover = RecentComicShared.coverURL.flatMap {
            ImageDownsampler.downsample(url: $0, maxPixel: max(side, 300))
        }
        return RecentComicEntry(date: .now, snapshot: snapshot, cover: cover,
                                panelColor: cover.flatMap(Self.panelColor(of:)))
    }

    /// The cover's most frequent colour, pushed deep enough to carry white type.
    ///
    /// Measured on a tiny redraw of the cover, so it costs next to nothing. Paper and ink are
    /// skipped (too grey, too dark), since they would win on almost every comic and say nothing
    /// about it. What's left is counted by hue in 30° buckets, and the fullest bucket's pixels are
    /// averaged, which is the colour that covers the most of the artwork (Topolino's purple turnip)
    /// rather than a mix of every colour on it. The hue is kept, the brightness set low: a panel,
    /// not a poster, so the cover above stays the loudest thing on the tile.
    private static func panelColor(of image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }
        let width = 24, height = 36
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let bucketCount = 12
        var buckets = Array(repeating: (count: 0, r: CGFloat(0), g: CGFloat(0), b: CGFloat(0)),
                            count: bucketCount)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[i]) / 255, g = CGFloat(pixels[i + 1]) / 255, b = CGFloat(pixels[i + 2]) / 255
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            UIColor(red: r, green: g, blue: b, alpha: 1)
                .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            guard saturation > 0.25, brightness > 0.2 else { continue }   // paper, ink, greys
            let bucket = min(Int(hue * CGFloat(bucketCount)), bucketCount - 1)
            buckets[bucket].count += 1
            buckets[bucket].r += r; buckets[bucket].g += g; buckets[bucket].b += b
        }
        // A cover with no colour to speak of (a sketch, a black-and-white reprint): neutral.
        guard let top = buckets.max(by: { $0.count < $1.count }), top.count > 0 else {
            return UIColor(white: 0.2, alpha: 1)
        }
        let n = CGFloat(top.count)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: top.r / n, green: top.g / n, blue: top.b / n, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return UIColor(hue: hue, saturation: min(max(saturation, 0.3), 0.7), brightness: 0.26, alpha: 1)
    }
}

struct RecentComicView: View {
    let entry: RecentComicEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(entry.snapshot.map { RecentComicShared.openURL(for: $0.bookID) })
    }

    @ViewBuilder
    private var content: some View {
        if let cover = entry.cover, let snapshot = entry.snapshot, family != .systemSmall {
            ExtraLargeComicView(cover: cover, snapshot: snapshot,
                                panel: Color(entry.panelColor ?? .darkGray))
        } else if let cover = entry.cover {
            // Full width, hung from the top: a cover's title sits at its top, so what the fill
            // has to crop comes off the bottom. Color.clear takes exactly the tile's size and the
            // overlay aligns the oversized image within it; a flexible frame around the image
            // itself would grow to the image's size and leave it centred.
            // In the content, not the container background: a tinted or clear home screen replaces
            // the background with its own glass, which left this tile empty.
            Color.clear
                .overlay(alignment: .top) {
                    Image(uiImage: cover)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                }
                .clipped()
                .containerBackground(for: .widget) { Color(.secondarySystemBackground) }
        } else {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .containerBackground(for: .widget) { Color(.secondarySystemBackground) }
        }
    }
}

/// The Extra Large Portrait tile: the whole cover at full width on top, and in the room the
/// tile's taller shape leaves below it, the comic's details on a panel toned from the cover.
private struct ExtraLargeComicView: View {
    let cover: UIImage
    let snapshot: RecentComicShared.Snapshot
    let panel: Color

    /// The band `ringRow(showsSubtitle: false)` needs: the 50 pt ring and 14 pt padding each way,
    /// with a little to spare so it never falls through to the empty fallback.
    private static let minimumBand: CGFloat = 82

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // Full width, but never so tall that the band below can't hold the ring row: a taller
            // cover is cropped at the bottom instead, where a cover carries the least.
            let fullHeight = size.width * cover.size.height / max(cover.size.width, 1)
            let coverHeight = max(0, min(fullHeight, size.height - Self.minimumBand))
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: coverHeight)
                    // Largest first. On an iPhone the band under a 2:3 cover is only about 95 pt,
                    // which is the ring row's job; the stacked layouts are for taller tiles.
                    ViewThatFits(in: .vertical) {
                        details(full: true)
                        details(full: false)
                        ringRow(showsSubtitle: true)
                        ringRow(showsSubtitle: false)
                        Color.clear
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }

                // The cover's bottom corners take the tile's OWN rounding. There is no API for the
                // widget's corner radius, but a ContainerRelativeShape laid over the whole tile IS
                // the tile's shape; shifted up by the band's height, its bottom corners land on the
                // cover's bottom edge. (Applied to the cover's own frame instead, the shape would
                // be inset by the band and come out with little or no rounding.) The top corners
                // sit above the tile and never show.
                Color.clear
                    .overlay(alignment: .top) {
                        Image(uiImage: cover)
                            .resizable()
                            .widgetAccentedRenderingMode(.fullColor)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size.width, height: coverHeight, alignment: .top)
                            .clipped()
                    }
                    .clipShape(ContainerRelativeShape().offset(y: coverHeight - size.height))
                    // Casts onto the panel, so the cover reads as a sheet lying on it.
                    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [panel.mix(with: .white, by: 0.08), panel.mix(with: .black, by: 0.35)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// `full` adds the subtitle and the publication line; the compact form keeps the title and
    /// the progress, for a tile whose cover left less room.
    private func details(full: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(kicker, systemImage: kickerSymbol)
                .font(.caption2.weight(.bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .opacity(0.6)
                .padding(.bottom, 8)

            Text(snapshot.title)
                .font(.title.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            if full, let subtitle = snapshot.subtitle {
                Text(subtitle)
                    .font(.body)
                    .opacity(0.75)
                    .lineLimit(2)
                    .padding(.top, 4)
            }

            Spacer(minLength: 16)

            progress

            if full, let meta {
                Text(meta)
                    .font(.caption)
                    .opacity(0.55)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    /// Title and page on the left, the progress as a ring on the right: everything in one row,
    /// for the short band a phone leaves under the cover.
    private func ringRow(showsSubtitle: Bool) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if showsSubtitle, let subtitle = snapshot.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.75)
                        .lineLimit(1)
                }
                Text("Page \(snapshot.lastReadPage + 1) of \(snapshot.pageCount)")
                    .font(.caption.monospacedDigit())
                    .opacity(0.55)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if snapshot.isRead {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                } else {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 50, height: 50)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Page \(snapshot.lastReadPage + 1) of \(snapshot.pageCount)")
                Spacer()
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .fontWeight(.semibold)
            }
            .font(.footnote.monospacedDigit())
            .opacity(0.85)

            Capsule()
                .fill(.white.opacity(0.18))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.white)
                            .frame(width: max(5, proxy.size.width * fraction))
                    }
                }
        }
    }

    private var fraction: Double {
        guard snapshot.pageCount > 1 else { return snapshot.isRead ? 1 : 0 }
        return min(1, max(0, Double(snapshot.lastReadPage) / Double(snapshot.pageCount - 1)))
    }

    private var kicker: LocalizedStringKey {
        if snapshot.isRead { return "Finished" }
        return snapshot.lastReadPage == 0 ? "Start reading" : "Continue reading"
    }

    private var kickerSymbol: String {
        snapshot.isRead ? "checkmark.circle.fill" : "book.pages.fill"
    }

    /// "2012 · Panini", as much as the metadata gives.
    private var meta: String? {
        let parts = [snapshot.year.map(String.init), snapshot.publisher].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
