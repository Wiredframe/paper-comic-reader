//
//  PaperParams.swift
//  Comic Reader
//
//  The tunable parameters of the paper effect, plus a few presets.
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
	/// Fibre size in pixels (larger = coarser grain).
	public var fiberScale: CGFloat

	public init(showThrough: CGFloat = 0.38,
				grain: CGFloat = 0.14,
				warmth: CGFloat = 1.0,
				blackLift: CGFloat = 1.0,
				fiberScale: CGFloat = 2.0) {
		self.showThrough = showThrough
		self.grain = grain
		self.warmth = warmth
		self.blackLift = blackLift
		self.fiberScale = fiberScale
	}

	public static let cream     = PaperParams(showThrough: 0.38, grain: 0.14, warmth: 1.0,  blackLift: 1.0)
	public static let newsprint = PaperParams(showThrough: 0.52, grain: 0.22, warmth: 0.55, blackLift: 1.0)
	public static let manga     = PaperParams(showThrough: 0.20, grain: 0.09, warmth: 0.25, blackLift: 0.85)
	public static let eInk      = PaperParams(showThrough: 0.30, grain: 0.12, warmth: 0.0,  blackLift: 1.0)

	public static let presets: [(name: String, params: PaperParams)] = [
		("Cream paper", .cream),
		("Newsprint",   .newsprint),
		("Manga",       .manga),
		("E-Ink",       .eInk),
	]
}
