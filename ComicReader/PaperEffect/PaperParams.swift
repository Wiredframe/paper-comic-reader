//
//  PaperParams.swift
//  Comic Reader
//
//  The tunable parameters of the paper effect, plus a few presets.
//
//  Every value a slider can reach sits on a 5-percentage-point notch of that slider's own
//  range (see `PaperSettingsView.slider`, step = upperBound / 20). The presets below are
//  written to land on those notches too, so picking one and then nudging a slider moves from
//  where the preset left off instead of first snapping somewhere else.
//

import CoreGraphics

// Sendable: a pure value type (all CGFloat) that legitimately crosses to the page-decode
// queue — see PageImageStore.open / setPaper, which hand it off in a @Sendable closure.
public struct PaperParams: Equatable, Sendable {
	/// Cream paper peeking THROUGH the ink (screen). 0…0.8
	public var showThrough: CGFloat
	/// Paper tooth on the light stock (multiply). 0…0.4
	public var grain: CGFloat
	/// 0 = neutral grey paper, 1 = warm cream.
	public var warmth: CGFloat
	/// 0 = pure black / high contrast, 1 = fully softened black.
	public var blackLift: CGFloat
	/// Fibre size in pixels (larger = coarser grain). Not exposed as a slider.
	public var fiberScale: CGFloat

	/// The defaults are the app's out-of-the-box look (`standard` below): a restrained overlay
	/// with barely any warmth and the blacks left mostly intact, so colour art keeps its bite.
	public init(showThrough: CGFloat = 0.32,
				grain: CGFloat = 0.08,
				warmth: CGFloat = 0.10,
				blackLift: CGFloat = 0.40,
				fiberScale: CGFloat = 2.0) {
		self.showThrough = showThrough
		self.grain = grain
		self.warmth = warmth
		self.blackLift = blackLift
		self.fiberScale = fiberScale
	}

	/// What a fresh install reads with, and the "Default" preset: 40% show-through, 20% grain,
	/// 10% warmth, 40% black lift. Listed first below so the picker names the out-of-the-box look
	/// instead of calling it Custom, and so there is always a way back to it.
	public static let standard  = PaperParams()

	public static let cream     = PaperParams(showThrough: 0.40, grain: 0.14, warmth: 1.0,  blackLift: 1.0)
	public static let newsprint = PaperParams(showThrough: 0.52, grain: 0.22, warmth: 0.55, blackLift: 1.0)
	public static let manga     = PaperParams(showThrough: 0.20, grain: 0.10, warmth: 0.25, blackLift: 0.85)
	public static let eInk      = PaperParams(showThrough: 0.32, grain: 0.12, warmth: 0.0,  blackLift: 1.0)

	public static let presets: [(name: String, params: PaperParams)] = [
		("Default",     .standard),
		("Cream paper", .cream),
		("Newsprint",   .newsprint),
		("Manga",       .manga),
		("E-Ink",       .eInk),
	]
}
