//
//  ReaderSettings.swift
//  Comic Reader
//
//  Persisted reader preferences (UserDefaults, same pattern as PaperSettings):
//  the tap-scroll reading mode, native Live Text, snappy animations, and the
//  global double-page-in-landscape layout. There is no pinch zoom: the double-tap
//  fit-width/fit-height toggle replaces it, so there's nothing to "remember".
//

import Foundation
import Combine

@MainActor
final class ReaderSettings: ObservableObject {

    /// Tap the left/right edge to move through the page (a half at a time) and turn
    /// pages. Off by default — when disabled a tap only toggles the chrome.
    @Published var tapToNavigate: Bool { didSet { defaults.set(tapToNavigate, forKey: K.tapNav) } }

    /// Enable native Live Text selection (press-and-hold) on comic pages.
    @Published var liveText: Bool { didSet { defaults.set(liveText, forKey: K.liveText) } }

    /// Snappier UI animations (chrome show/hide, page turns, fit toggles).
    @Published var fastAnimations: Bool { didSet { defaults.set(fastAnimations, forKey: K.fastAnim) } }

    /// Show two pages side by side in landscape (cover alone, then fixed pairs).
    @Published var doublePage: Bool { didSet { defaults.set(doublePage, forKey: K.double) } }

    /// Duration to use for reader chrome / overlay animations.
    var uiAnimationDuration: TimeInterval { fastAnimations ? 0.08 : 0.16 }

    /// Both reader movements — the tap page turn and a tap-scroll step — share one snappy
    /// easeOutBack curve (see EasedScrollAnimator). This is its overshoot strength: 0.8 →
    /// ~2% past the target before it settles back, which reads as the light bounce.
    var movementOvershoot: Double { 0.8 }
    /// Duration of a tap page turn (a full page slide) — snappier with fast animations on.
    var pageTurnDuration: TimeInterval { fastAnimations ? 0.30 : 0.44 }
    /// Duration of a tap-scroll step (the shorter vertical half-page move). Kept quicker
    /// than a full turn so repeated taps stay snappy.
    var tapScrollDuration: TimeInterval { fastAnimations ? 0.16 : 0.30 }

    private let defaults: UserDefaults
    private enum K {
        static let tapNav = "reader.tapToNavigate"
        static let liveText = "reader.liveText"
        static let fastAnim = "reader.fastAnimations"
        static let double = "reader.doublePage"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tapToNavigate = defaults.object(forKey: K.tapNav) as? Bool ?? false
        liveText = defaults.object(forKey: K.liveText) as? Bool ?? false
        fastAnimations = defaults.object(forKey: K.fastAnim) as? Bool ?? true
        doublePage = defaults.object(forKey: K.double) as? Bool ?? false
    }
}
