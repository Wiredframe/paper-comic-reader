//
//  PaperFilterTests.swift
//  ComicReaderTests
//
//  With every slider at zero the paper effect leaves a page exactly as it is; with warmth it
//  tints the white towards cream. The kernel and the Core Image fallback both do nothing at zero
//  grain and show-through, so this holds whichever one the host app loads.
//

import XCTest
import CoreGraphics
@testable import ComicReader

final class PaperFilterTests: XCTestCase {

	private func image(white: CGFloat) -> CGImage {
		let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
								space: CGColorSpace(name: CGColorSpace.sRGB)!,
								bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		context.setFillColor(red: white, green: white, blue: white, alpha: 1)
		context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
		return context.makeImage()!
	}

	private func rgb(_ image: CGImage) -> (CGFloat, CGFloat, CGFloat) {
		let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
								space: CGColorSpace(name: CGColorSpace.sRGB)!,
								bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
		context.draw(image, in: CGRect(x: -4, y: -4, width: 8, height: 8))
		let p = context.data!.assumingMemoryBound(to: UInt8.self)
		return (CGFloat(p[0]) / 255, CGFloat(p[1]) / 255, CGFloat(p[2]) / 255)
	}

	private let off = PaperParams(showThrough: 0, grain: 0, warmth: 0, blackLift: 0)

	func testAllSlidersAtZeroKeepWhiteWhite() throws {
		let out = try XCTUnwrap(PaperFilter().makeCGImage(from: image(white: 1), params: off))
		let (r, g, b) = rgb(out)
		XCTAssertGreaterThan(min(r, g, b), 0.98, "white came out as \(r), \(g), \(b)")
	}

	func testAllSlidersAtZeroKeepBlackBlack() throws {
		let out = try XCTUnwrap(PaperFilter().makeCGImage(from: image(white: 0), params: off))
		let (r, g, b) = rgb(out)
		XCTAssertLessThan(max(r, g, b), 0.02)
	}

	func testWarmthTintsTheWhiteTowardsCream() throws {
		var warm = off
		warm.warmth = 1
		let out = try XCTUnwrap(PaperFilter().makeCGImage(from: image(white: 1), params: warm))
		let (r, _, b) = rgb(out)
		XCTAssertGreaterThan(r, b + 0.08, "warm paper should be yellower than white")
	}
}
