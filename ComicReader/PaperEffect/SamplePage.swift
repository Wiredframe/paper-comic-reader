//
//  SamplePage.swift
//  Comic Reader
//
//  Generates a synthetic "comic page" (black line-art, greys, a gradient and a
//  few colour swatches on white) so the paper effect can be previewed without
//  loading a real file yet.
//

import UIKit

enum SamplePage {
	static func make(size: CGSize = CGSize(width: 900, height: 1300)) -> UIImage {
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = true
		let renderer = UIGraphicsImageRenderer(size: size, format: format)
		return renderer.image { ctx in
			let cg = ctx.cgContext
			let w = size.width, h = size.height

			UIColor.white.setFill()
			cg.fill(CGRect(x: 0, y: 0, width: w, height: h))

			// Solid black panel (tests deep blacks + show-through).
			UIColor.black.setFill()
			cg.fill(CGRect(x: 60, y: 110, width: w - 120, height: 240))

			// Title text on the panel.
			let title = "COMIC READER" as NSString
			title.draw(at: CGPoint(x: 80, y: 150),
					   withAttributes: [.font: UIFont.boldSystemFont(ofSize: 60),
										.foregroundColor: UIColor.white])

			// 50% grey block (midtones).
			UIColor(white: 0.5, alpha: 1).setFill()
			cg.fill(CGRect(x: 60, y: h - 420, width: 300, height: 300))

			// Horizontal black→white gradient strip (tonal remap).
			let cs = CGColorSpaceCreateDeviceRGB()
			if let grad = CGGradient(colorsSpace: cs,
									 colors: [UIColor.black.cgColor, UIColor.white.cgColor] as CFArray,
									 locations: [0, 1]) {
				cg.saveGState()
				cg.clip(to: CGRect(x: 60, y: 470, width: w - 120, height: 120))
				cg.drawLinearGradient(grad, start: CGPoint(x: 60, y: 0),
									  end: CGPoint(x: w - 60, y: 0), options: [])
				cg.restoreGState()
			}

			// Thin black "line art".
			UIColor.black.setStroke()
			cg.setLineWidth(3)
			for i in 0..<8 {
				let y = 650 + CGFloat(i) * 22
				cg.stroke(CGRect(x: 60, y: y, width: w - 120, height: 1))
			}

			// Colour swatches (colour handling / show-through on saturated ink).
			let colours: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow]
			for (i, colour) in colours.enumerated() {
				colour.setFill()
				cg.fill(CGRect(x: 420 + CGFloat(i) * 110, y: h - 400, width: 90, height: 260))
			}
		}
	}
}
