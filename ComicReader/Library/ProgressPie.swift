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

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary, lineWidth: 1)
            PieWedge(progress: progress).fill(Color.secondary)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Reading progress")
        .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded())) percent")
    }
}

/// The "read" badge shown beside the progress pie. Deliberately separate from the pie:
/// `isRead` is a manual/last-page flag that browsing never overwrites, so it carries its
/// own always-visible mark (a filled green check) rather than riding on read progress.
struct ReadCheck: View {
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size))
            .foregroundStyle(.green)
            .accessibilityLabel("Read")
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
