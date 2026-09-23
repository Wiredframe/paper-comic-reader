//
//  ReaderMetrics.swift
//  Comic Reader
//
//  Feel values both readers share (the portrait strip and the landscape pages), so a page
//  looks and answers the same whichever way the device is held.
//

import UIKit

enum ReaderMetrics {

    /// Width fraction of each outer navigation zone (page turn / tap-scroll / strip step), where
    /// a single tap fires instantly and the double-tap zoom is suppressed. The centre keeps the
    /// double-tap zoom.
    static let navEdgeFraction: CGFloat = 0.10

    static func isNavEdge(_ x: CGFloat, width: CGFloat) -> Bool {
        x < width * navEdgeFraction || x > width * (1 - navEdgeFraction)
    }

    /// The page shadow: soft, sitting a little below the page, as if lit from above. Sized
    /// generously rather than tightly: a hard, tight shadow reads as a drop-shadowed graphic, a
    /// wide diffuse one reads as paper resting on the mat.
    static let shadowRadius: CGFloat = 16

    static func applyPageShadow(to layer: CALayer) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = shadowRadius
        layer.shadowOffset = CGSize(width: 0, height: 6)
    }
}
