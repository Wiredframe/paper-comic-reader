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
            .accessibilityLabel("Read")
    }
}

/// Shown first in a comic's status row when it's folder-backed but not downloaded yet — the
/// "lives in your library folder, fetched when you open it" mark. Its absence means the comic is
/// local (owned copies and downloaded comics show nothing, local being the default expectation),
/// so the row stays uncluttered for the common case.
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
