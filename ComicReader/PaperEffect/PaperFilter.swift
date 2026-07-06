//
//  PaperFilter.swift
//  Comic Reader
//
//  Applies a "paper" look to comic pages: harsh blacks are lifted to a dark
//  warm grey, white is pulled towards a warm cream, and an organic, isotropic
//  paper texture is laid over the page (multiply "body" + screen "show-through"
//  so the paper peeks through the ink). See PaperKernels.metal.
//
//  Platform-neutral engine: works on CIImage / CGImage and provides a UIImage
//  convenience. GPU-accelerated via a Metal-backed CIContext; if the Metal
//  kernel can not be loaded it falls back to a pure Core Image approximation.
//

import Foundation
import CoreImage
import CoreGraphics
import Metal
#if canImport(UIKit)
import UIKit
#endif

public final class PaperFilter {

	public static let shared = PaperFilter()

	private let context: CIContext
	private let kernel: CIKernel?
	private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

	public init() {
		// NSNull working space => filters operate directly on the (sRGB encoded)
		// pixel values, giving intuitive "levels"-style tonal math.
		let options: [CIContextOption: Any] = [.workingColorSpace: NSNull()]
		if let device = MTLCreateSystemDefaultDevice() {
			context = CIContext(mtlDevice: device, options: options)
		} else {
			context = CIContext(options: options)
		}
		kernel = PaperFilter.loadKernel()
	}

	/// True when the Metal kernel is in use (false => Core Image fallback).
	public var usesMetalKernel: Bool { kernel != nil }

	private static func loadKernel() -> CIKernel? {
		guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
			  let data = try? Data(contentsOf: url) else { return nil }
		return try? CIKernel(functionName: "paperTexture", fromMetalLibraryData: data)
	}

	// MARK: - Public API

	/// Core transform: CIImage → CIImage.
	public func apply(to input: CIImage, params: PaperParams = .cream) -> CIImage {
		let t = tones(warmth: params.warmth, blackLift: params.blackLift)

		// 1. Compress tonal range + tint: out = in * (ceil - floor) + floor.
		let sR = t.ceil.x - t.floor.x, sG = t.ceil.y - t.floor.y, sB = t.ceil.z - t.floor.z
		var toned = input.applyingFilter("CIColorMatrix", parameters: [
			"inputRVector": CIVector(x: sR, y: 0, z: 0, w: 0),
			"inputGVector": CIVector(x: 0, y: sG, z: 0, w: 0),
			"inputBVector": CIVector(x: 0, y: 0, z: sB, w: 0),
			"inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
			"inputBiasVector": CIVector(x: t.floor.x, y: t.floor.y, z: t.floor.z, w: 0),
		])
		// 2. Gentle desaturation + soft contrast for a matte, printed feel.
		toned = toned.applyingFilter("CIColorControls", parameters: [
			kCIInputSaturationKey: 0.92,
			kCIInputContrastKey: 0.96,
		])

		// 3. Organic paper texture (Metal), with a Core Image fallback.
		if let kernel = kernel {
			let textured = kernel.apply(extent: input.extent,
										roiCallback: { _, rect in rect },
										arguments: [toned, params.grain, params.showThrough,
													params.fiberScale, t.tint])
			if let textured = textured {
				return textured.cropped(to: input.extent)
			}
		}
		return fallbackTexture(on: toned, tint: t.tint,
							   grain: params.grain, showThrough: params.showThrough)
			.cropped(to: input.extent)
	}

	/// Renders the effect to a new CGImage.
	public func makeCGImage(from cg: CGImage, params: PaperParams = .cream) -> CGImage? {
		let input = CIImage(cgImage: cg)
		let output = apply(to: input, params: params)
		return context.createCGImage(output, from: input.extent,
									 format: .RGBA8, colorSpace: outputColorSpace)
	}

	#if canImport(UIKit)
	/// Convenience: UIImage → UIImage (nil if it can not be rendered).
	public func apply(to image: UIImage, params: PaperParams = .cream) -> UIImage? {
		guard let cg = image.cgImage,
			  let out = makeCGImage(from: cg, params: params) else { return nil }
		return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
	}
	#endif

	// MARK: - Tonal endpoints

	/// Interpolates the tonal endpoints between a neutral grey paper (warmth 0)
	/// and a warm cream stock (warmth 1); `blackLift` scales how far pure black
	/// is raised.
	private func tones(warmth: CGFloat, blackLift: CGFloat)
		-> (floor: CIVector, ceil: CIVector, tint: CIVector) {
		func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: CGFloat)
			-> (Double, Double, Double) {
			let tt = Double(t)
			return (a.0 + (b.0 - a.0) * tt, a.1 + (b.1 - a.1) * tt, a.2 + (b.2 - a.2) * tt)
		}
		let neutralFloor = (0.145, 0.145, 0.145), warmFloor = (0.16, 0.14, 0.11)
		let neutralCeil  = (0.93, 0.93, 0.93),    warmCeil  = (0.96, 0.92, 0.82)
		let neutralTint  = (0.92, 0.92, 0.92),    warmTint  = (0.95, 0.90, 0.78)

		let fl = lerp(neutralFloor, warmFloor, warmth)
		let ce = lerp(neutralCeil,  warmCeil,  warmth)
		let ti = lerp(neutralTint,  warmTint,  warmth)
		let bl = Double(blackLift)
		return (CIVector(x: fl.0 * bl, y: fl.1 * bl, z: fl.2 * bl),
				CIVector(x: ce.0, y: ce.1, z: ce.2),
				CIVector(x: ti.0, y: ti.1, z: ti.2))
	}

	// MARK: - Core Image fallback

	/// Used when the Metal kernel is unavailable: a softened multiply grain for
	/// the body + a screen highlight for the show-through.
	private func fallbackTexture(on toned: CIImage, tint: CIVector,
								 grain: CGFloat, showThrough: CGFloat) -> CIImage {
		let extent = toned.extent
		guard let gen = CIFilter(name: "CIRandomGenerator")?.outputImage else { return toned }
		var fiber = gen.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
		fiber = fiber.clampedToExtent()
			.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.1])
			.cropped(to: extent)

		let m = grain
		let mult = fiber.applyingFilter("CIColorMatrix", parameters: [
			"inputRVector": CIVector(x: m, y: 0, z: 0, w: 0),
			"inputGVector": CIVector(x: 0, y: m, z: 0, w: 0),
			"inputBVector": CIVector(x: 0, y: 0, z: m, w: 0),
			"inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
			"inputBiasVector": CIVector(x: 1 - m, y: 1 - m, z: 1 - m, w: 1),
		])
		var out = mult.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: toned])

		let peaks = fiber.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 2.2])
		let s = showThrough
		let peek = peaks.applyingFilter("CIColorMatrix", parameters: [
			"inputRVector": CIVector(x: tint.x * s, y: 0, z: 0, w: 0),
			"inputGVector": CIVector(x: 0, y: tint.y * s, z: 0, w: 0),
			"inputBVector": CIVector(x: 0, y: 0, z: tint.z * s, w: 0),
			"inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
			"inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
		])
		out = out.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: peek])
		return out
	}
}
