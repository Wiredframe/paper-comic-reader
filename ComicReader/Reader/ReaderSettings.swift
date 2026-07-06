//
//  ReaderSettings.swift
//  Comic Reader
//
//  Persisted reader preferences (UserDefaults, same pattern as PaperSettings):
//  the thirds-scroll reading mode, native Live Text, snappy animations, and the
//  global double-page-in-landscape layout. There is no pinch zoom: the double-tap
//  fit-width/fit-height toggle replaces it, so there's nothing to "remember".
//

import Foundation
import Combine

@MainActor
final class ReaderSettings: ObservableObject {

    /// Tap advances by a third of the page, turning the page at the bottom.
    @Published var thirdsScroll: Bool { didSet { defaults.set(thirdsScroll, forKey: K.thirds) } }

    /// Enable native Live Text selection (press-and-hold) on comic pages.
    @Published var liveText: Bool { didSet { defaults.set(liveText, forKey: K.liveText) } }

    /// Snappier UI animations (chrome show/hide, page turns, fit toggles).
    @Published var fastAnimations: Bool { didSet { defaults.set(fastAnimations, forKey: K.fastAnim) } }

    /// Show two pages side by side in landscape (cover alone, then fixed pairs).
    @Published var doublePage: Bool { didSet { defaults.set(doublePage, forKey: K.double) } }

    /// Duration to use for reader chrome / overlay animations.
    var uiAnimationDuration: TimeInterval { fastAnimations ? 0.08 : 0.16 }

    private let defaults: UserDefaults
    private enum K {
        static let thirds = "reader.thirdsScroll"
        static let liveText = "reader.liveText"
        static let fastAnim = "reader.fastAnimations"
        static let double = "reader.doublePage"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        thirdsScroll = defaults.object(forKey: K.thirds) as? Bool ?? false
        liveText = defaults.object(forKey: K.liveText) as? Bool ?? false
        fastAnimations = defaults.object(forKey: K.fastAnim) as? Bool ?? true
        doublePage = defaults.object(forKey: K.double) as? Bool ?? false
    }
}
