//
//  ReaderSettings.swift
//  Comic Reader
//
//  Persisted reader preferences (UserDefaults, same pattern as PaperSettings):
//  the tap-scroll reading mode, native Live Text, snappy animations, and the
//  double-page-in-landscape layout. Pinch zoom is deliberately transient (every other
//  gesture resets it), so there's nothing to persist there. Orientation is not a setting:
//  the reader simply follows the device (free rotation), the rest of the app stays portrait.
//

import Foundation
import Observation

@MainActor
@Observable
final class ReaderSettings {

    /// Tap the left/right edge to move through the page (a half at a time) and turn
    /// pages. On by default — when disabled a tap only toggles the chrome.
    var tapToNavigate: Bool { didSet { defaults.set(tapToNavigate, forKey: K.tapNav) } }

    /// Enable native Live Text selection (press-and-hold) on comic pages.
    var liveText: Bool { didSet { defaults.set(liveText, forKey: K.liveText) } }

    /// Snappier UI animations (chrome show/hide, page turns, fit toggles).
    var fastAnimations: Bool { didSet { defaults.set(fastAnimations, forKey: K.fastAnim) } }

    /// Show two pages side by side in landscape (cover alone, then fixed pairs).
    var doublePage: Bool { didSet { defaults.set(doublePage, forKey: K.double) } }

    /// Leave a thin line of the background between the two halves of a double page, so the spread
    /// reads as two sheets rather than one wide one. Only ever seen where a slot really holds two
    /// pages; a lone page (the cover, an unpaired last page) has no gutter to show. The width is a
    /// fixed layout metric, not a second setting (see `ReaderPageCell.spreadGap`).
    var pageGap: Bool { didSet { defaults.set(pageGap, forKey: K.pageGap) } }

    /// Cast a soft shadow around the page so it reads as a sheet lying on the letterbox mat.
    /// Seen wherever the page doesn't run to the screen edge; a spread casts a single shadow
    /// around the pair, never down the gutter. Read at layout time, so a change lands on the
    /// next open rather than mid-read — there's no way to reach Settings from the reader anyway.
    var pageShadow: Bool { didSet { defaults.set(pageShadow, forKey: K.pageShadow) } }

    /// How wide a single page fills the screen at fit-width (the default single-page look
    /// and the double-tap zoom). 1.0 = full width; lower values (down to 0.7) show more of
    /// the page height and read less zoomed-in.
    var doubleTapZoom: Double { didSet { defaults.set(doubleTapZoom, forKey: K.zoom) } }

    /// Where a page that doesn't fill the width comes to rest. Off, it sits centred with an even
    /// gap either side. On, a zoomed double page rests its LEFT page against the screen's left edge
    /// and its RIGHT page against the right, the way a printed spread's outer margins sit, so the
    /// spare width goes to showing more of the facing page instead of two dead margins. Paired with
    /// `doubleTapZoom` above, and only ever visible below 100%: at 100% there is no spare width to
    /// place and the layout arithmetic collapses to the same answer either way (see
    /// `ReaderPageCell.focusColumnOffsetX`). Off by default, so nobody's reader shifts under them.
    var alignToEdges: Bool { didSet { defaults.set(alignToEdges, forKey: K.alignToEdges) } }

    // Animation timing. With Fast Animations OFF every reader transition uses the iOS
    // defaults — the standard ~0.25s UIView.animate baseline paired with the system
    // ease-in-out curve. Every reader movement is driven by Core Animation (no custom
    // easing or overshoot, no per-frame main-thread loop), so all of them run on the render
    // server at the full ProMotion rate. Turning Fast Animations ON scales ALL of them down
    // together to a snappier ~0.6×, so the whole reader speeds up as one.

    /// Reader chrome / overlay fades (top & bottom bars, status bar).
    var uiAnimationDuration: TimeInterval { fastAnimations ? 0.15 : 0.25 }
    /// A tap page turn (a full page slide).
    var pageTurnDuration: TimeInterval { fastAnimations ? 0.20 : 0.30 }
    /// A tap-scroll step (the shorter vertical part-page move).
    var tapScrollDuration: TimeInterval { fastAnimations ? 0.15 : 0.25 }
    /// A double-tap fit toggle (fit-width ⇄ fit-height, spread ⇄ zoomed page).
    var fitToggleDuration: TimeInterval { fastAnimations ? 0.15 : 0.25 }

    private let defaults: UserDefaults
    private enum K {
        static let tapNav = "reader.tapToNavigate"
        static let liveText = "reader.liveText"
        static let fastAnim = "reader.fastAnimations"
        static let double = "reader.doublePage"
        static let zoom = "reader.doubleTapZoom"
        static let pageShadow = "reader.pageShadow"
        static let alignToEdges = "reader.alignToEdges"
        static let pageGap = "reader.pageGap"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tapToNavigate = defaults.object(forKey: K.tapNav) as? Bool ?? true
        liveText = defaults.object(forKey: K.liveText) as? Bool ?? true
        fastAnimations = defaults.object(forKey: K.fastAnim) as? Bool ?? false
        doublePage = defaults.object(forKey: K.double) as? Bool ?? true
        pageShadow = defaults.object(forKey: K.pageShadow) as? Bool ?? true
        doubleTapZoom = defaults.object(forKey: K.zoom) as? Double ?? 1.0
        alignToEdges = defaults.object(forKey: K.alignToEdges) as? Bool ?? false
        pageGap = defaults.object(forKey: K.pageGap) as? Bool ?? false
        // Legacy force-landscape preference from old builds. The reader now just follows the
        // device orientation, so drop any leftover value rather than let it linger.
        defaults.removeObject(forKey: "reader.forceLandscape")
    }
}
