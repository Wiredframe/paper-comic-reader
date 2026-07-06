//
//  PaperSettings.swift
//  Comic Reader
//
//  Observable, persisted settings for the paper effect (on/off + parameters).
//  Backed by UserDefaults so the choice survives launches.
//

import Foundation
import Combine

@MainActor
final class PaperSettings: ObservableObject {

	@Published var isEnabled: Bool = false {
		didSet { defaults.set(isEnabled, forKey: K.enabled) }
	}

	@Published var params: PaperParams = .cream {
		didSet { persist(params) }
	}

	private let defaults: UserDefaults

	private enum K {
		static let enabled     = "paper.enabled"
		static let showThrough = "paper.showThrough"
		static let grain       = "paper.grain"
		static let warmth      = "paper.warmth"
		static let blackLift   = "paper.blackLift"
		static let fiberScale  = "paper.fiberScale"
	}

	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		// NB: property observers do not fire during init, so this loads without
		// immediately writing back.
		isEnabled = defaults.object(forKey: K.enabled) as? Bool ?? false
		let base = PaperParams.cream
		params = PaperParams(
			showThrough: Self.load(defaults, K.showThrough, base.showThrough),
			grain:       Self.load(defaults, K.grain, base.grain),
			warmth:      Self.load(defaults, K.warmth, base.warmth),
			blackLift:   Self.load(defaults, K.blackLift, base.blackLift),
			fiberScale:  Self.load(defaults, K.fiberScale, base.fiberScale)
		)
	}

	/// Index of the preset that exactly matches the current params, or nil.
	var matchingPresetIndex: Int? {
		PaperParams.presets.firstIndex { $0.params == params }
	}

	func applyPreset(_ preset: PaperParams) {
		params = preset
	}

	// MARK: - Persistence

	private func persist(_ p: PaperParams) {
		defaults.set(Double(p.showThrough), forKey: K.showThrough)
		defaults.set(Double(p.grain), forKey: K.grain)
		defaults.set(Double(p.warmth), forKey: K.warmth)
		defaults.set(Double(p.blackLift), forKey: K.blackLift)
		defaults.set(Double(p.fiberScale), forKey: K.fiberScale)
	}

	private static func load(_ d: UserDefaults, _ key: String, _ fallback: CGFloat) -> CGFloat {
		d.object(forKey: key) == nil ? fallback : CGFloat(d.double(forKey: key))
	}
}
