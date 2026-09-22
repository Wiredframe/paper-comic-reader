//
//  ProgressPie.swift
//  Comic Reader
//
//  The little read-progress pie shown under a cover (as in the reference app).
//

import SwiftUI

struct ProgressPie: View {
    let progress: Double        // 0…1
    var size: CGFloat = 15
    // Scale with Dynamic Type so the pie tracks the adjacent caption text instead of
    // staying a fixed size while the label grows.
    @ScaledMetric(relativeTo: .caption) private var unit: CGFloat = 1

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary, lineWidth: 1)
            PieWedge(progress: progress).fill(Color.secondary)
        }
        .frame(width: size * unit, height: size * unit)
        .accessibilityLabel("Reading progress")
        .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded())) percent")
    }
}

/// The "read" badge shown beside the progress pie. Deliberately separate from the pie:
/// `isRead` is a manual/last-page flag that browsing never overwrites, so it carries its
/// own always-visible mark (a filled green check) rather than riding on read progress.
struct ReadCheck: View {
    var size: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var unit: CGFloat = 1

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size * unit))
            .foregroundStyle(.green)
            .accessibilityLabel("Marked as read")
    }
}

/// The favourite mark, shown FIRST in a comic's status row — ahead of availability and progress.
/// It leads because it's the only badge there the reader put on deliberately: the others state
/// facts about the file or about the reading, this one states a preference. Red rather than the
/// accent, which is a bright orange-yellow that a small heart would read as gold against.
struct FavoriteHeart: View {
    var size: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var unit: CGFloat = 1

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size * unit))
            .foregroundStyle(.red)
            .accessibilityLabel("Favorite")
    }
}

/// Shown early in a comic's status row — after the favourite heart, before progress — when it's
/// folder-backed but not downloaded yet: the "lives in your library folder, fetched when you open
/// it" mark. Its absence means the comic is local (owned copies and downloaded comics show
/// nothing, local being the default expectation), so the row stays uncluttered for the common case.
struct AvailabilityBadge: View {
    var size: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var unit: CGFloat = 1

    var body: some View {
        Image(systemName: "icloud.and.arrow.down")
            .font(.system(size: size * unit))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Not downloaded")
    }
}

/// A download in flight: the fetched share as a ring, with the mark for stopping it in the middle.
/// The same shape iOS uses for an app downloading to the Home Screen, so it reads as "working, and
/// you can stop it" without a label.
///
/// The ring animates to each new value because the copy layer reports progress once per megabyte,
/// which without the tween would step visibly. It stays a hair short of the full circle until the
/// bytes have actually landed: the indicator disappearing is what says "done", so a ring closing
/// early would claim it twice.
///
/// Until the first megabyte it turns instead of filling. That gap is real — the copy reports
/// nothing before it, and nothing at all for a source that can't say how big it is — and one ring
/// that spins and then fills says "working" throughout, where a ring frozen at zero would read as
/// stuck and a spinner stood in front of would just be two marks in one place.
struct DownloadRing: View {
    let progress: Double
    var size: CGFloat = 15
    /// `xmark` at caption sizes, where it is the only cancel mark that survives being 5 points
    /// wide; the reader's big ring uses the stop bars instead.
    var glyph: String = "xmark"
    /// Everything is drawn in this one colour (the track as a faded version of it), so the ring
    /// can sit on the accent-coloured Discover button as readably as it sits in a caption row.
    var tint: Color = .accentColor
    @ScaledMetric(relativeTo: .caption) private var unit: CGFloat = 1

    /// Drives the waiting turn. One 360° rotation repeating forever, so it's a single
    /// render-server animation rather than anything per frame.
    @State private var turning = false

    private var clamped: Double { min(1, max(0, progress)) }
    private var isWaiting: Bool { clamped <= 0 }

    var body: some View {
        let side = size * unit
        ZStack {
            Circle()
                .stroke(tint.opacity(0.25), lineWidth: side * 0.11)
            Circle()
                .trim(from: 0, to: isWaiting ? 0.25 : clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: side * 0.11, lineCap: .round))
                .rotationEffect(.degrees(isWaiting && turning ? 270 : -90))
                .animation(isWaiting ? .linear(duration: 0.9).repeatForever(autoreverses: false) : nil,
                           value: turning)
                .animation(.linear(duration: 0.25), value: clamped)
            Image(systemName: glyph)
                .font(.system(size: side * 0.42, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: side, height: side)
        .onAppear { turning = true }
        .accessibilityLabel("Downloading")
        .accessibilityValue(isWaiting ? String(localized: "Starting") : String(localized: "\(Int((clamped * 100).rounded())) percent"))
    }
}

/// What a comic's status row says about where its bytes are: nothing when it's local, the cloud
/// when it's waiting in the library folder, the ring while it's being fetched.
///
/// A leaf on purpose. It looks its own download up in the environment rather than being handed one,
/// so a progress tick re-renders this badge and nothing above it: neither the grid's memoised
/// derivation nor the carousel's scroll (see the header of `PeekCarouselView`).
struct AvailabilityIndicator: View {
    let book: ComicBook
    var size: CGFloat = 15

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        if let ticket = downloads.ticket(for: book.id) {
            DownloadRing(progress: ticket.progress, size: size)
        } else if book.isRemote {
            AvailabilityBadge(size: size)
        }
    }
}

private struct PieWedge: Shape {
    let progress: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2 * 0.72
        path.move(to: center)
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(1, max(0, progress))),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}
