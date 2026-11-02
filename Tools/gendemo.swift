// gendemo.swift: renders a shelf of original demo comics for the App Store screenshots.
//
// Every page is drawn here from shapes and words, so the screenshots carry nothing anyone else
// owns: minimal covers in one colour with a single tone-on-tone shape, and interior pages laid out
// in panels of flat tints with a few speech bubbles in English, which give Live Text something to
// select. Each comic gets a ComicInfo.xml with invented credits.
// The first four share their names and colours with the iOS app's demo comics.
//
//   swift scripts/screens/gendemo.swift <out-dir>
//
// GENDEMO_ONLY="Solar Flare,Deep Blue" limits the run to those series, GENDEMO_QUALITY=0.7 sets the
// JPEG quality (default 0.85). The app's bundled sample comics (PaperComic/Resources/SampleComics)
// are made with `GENDEMO_ONLY=… GENDEMO_QUALITY=0.6 GENDEMO_SCALE=0.6`.
//
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let W = 1600.0, H = 2400.0

func rgb(_ hex: UInt32) -> NSColor {
	NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
			blue: Double(hex & 0xFF) / 255, alpha: 1)
}

/// A seeded generator, so every run draws the same pages.
struct RNG {
	var state: UInt64
	mutating func next() -> Double {
		state = state &* 6364136223846793005 &+ 1442695040888963407
		return Double(state >> 11) / Double(1 << 53)
	}
	mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
	mutating func pick<T>(_ xs: [T]) -> T { xs[Int(next() * Double(xs.count)) % xs.count] }
}

struct Demo {
	let file, series, cover, story: String
	let number: Int
	let bg, ink, accent: NSColor
	let sky: [NSColor]
	let pages: Int
	let writer, artist: String
	let year: Int
	let lines: [String]
	let motif: Motif
}

enum Motif { case sun, city, waves, circuit, moon, mountains, kite, orchard, bloom, rain, dusk, stripes }

let demos: [Demo] = [
	Demo(file: "Solar Flare 1", series: "Solar Flare", cover: "SOLAR FLARE", story: "Ignition", number: 1,
		 bg: rgb(0xFCD329), ink: rgb(0x261F05), accent: rgb(0xE8502E), sky: [rgb(0xFFE07A), rgb(0xF59E42)],
		 pages: 18, writer: "A. Vance", artist: "M. Okafor", year: 2026,
		 lines: ["THE SUN IS LATE TODAY.", "THEN WE WAIT.", "NOBODY WAITS FOR THE SUN!", "I DO.", "LOOK. THERE IT IS.", "HOLD ON TO SOMETHING!"],
		 motif: .sun),
	Demo(file: "Crimson Alley 3", series: "Crimson Alley", cover: "CRIMSON ALLEY", story: "The Long Rain", number: 3,
		 bg: rgb(0xD7263D), ink: rgb(0xFFF4E6), accent: rgb(0x1B1B2F), sky: [rgb(0x2E2B4A), rgb(0x7A3B5C)],
		 pages: 16, writer: "R. Delacroix", artist: "S. Lindqvist", year: 2025,
		 lines: ["IT HAS RAINED FOR NINE DAYS.", "AND YOU STILL HAVE NO UMBRELLA?", "I HAVE A HAT.", "WHO SENT YOU?", "THE RAIN DID.", "FOLLOW THE RED DOOR."],
		 motif: .city),
	Demo(file: "Deep Blue 2", series: "Deep Blue", cover: "DEEP BLUE", story: "The Halcyon Dive", number: 2,
		 bg: rgb(0x1F5FAD), ink: rgb(0xF2F7FF), accent: rgb(0x7FD1F5), sky: [rgb(0x9AD8F0), rgb(0x2B6CB0)],
		 pages: 20, writer: "K. Tanaka", artist: "L. Moreau", year: 2026,
		 lines: ["HOW DEEP DOES IT GO?", "DEEPER THAN THE MAPS.", "DID YOU HEAR THAT?", "WHALES. SINGING.", "WE ARE NOT ALONE DOWN HERE.", "GOOD."],
		 motif: .waves),
	Demo(file: "Jade Circuit 1", series: "Jade Circuit", cover: "JADE CIRCUIT", story: "Borrowed Memory", number: 1,
		 bg: rgb(0x1D9E8C), ink: rgb(0xFFFFFF), accent: rgb(0xF2C14E), sky: [rgb(0xB8F2E6), rgb(0x3BA99C)],
		 pages: 14, writer: "J. Okonkwo", artist: "E. Brandt", year: 2025,
		 lines: ["WHOSE MEMORY IS THIS?", "YOURS, NOW.", "I REMEMBER A GARDEN.", "THERE WAS NEVER A GARDEN.", "THEN WHY CAN I SMELL IT?", "SYSTEM REBOOTING."],
		 motif: .circuit),
	Demo(file: "Night Ferry 4", series: "Night Ferry", cover: "NIGHT FERRY", story: "Last Crossing", number: 4,
		 bg: rgb(0x23264F), ink: rgb(0xFFD166), accent: rgb(0xFFD166), sky: [rgb(0x3A3F7A), rgb(0x12142E)],
		 pages: 16, writer: "P. Albescu", artist: "N. Haddad", year: 2024,
		 lines: ["ONE TICKET, PLEASE.", "ONE WAY OR RETURN?", "I HAVEN'T DECIDED.", "THE FERRY DECIDES FOR YOU.", "THEN ONE WAY.", "WELCOME ABOARD."],
		 motif: .moon),
	Demo(file: "Northbound 1", series: "Northbound", cover: "NORTHBOUND", story: "Thin Air", number: 1,
		 bg: rgb(0xE9EEF2), ink: rgb(0x1E3A5F), accent: rgb(0xD1495B), sky: [rgb(0xDDE7EE), rgb(0x9DB4C8)],
		 pages: 18, writer: "I. Sørensen", artist: "T. Achebe", year: 2026,
		 lines: ["THE PASS IS CLOSED.", "PASSES OPEN FOR THE STUBBORN.", "THAT IS NOT HOW SNOW WORKS.", "WATCH ME.", "...FINE. I'LL CARRY THE TEA.", "NORTH IT IS."],
		 motif: .mountains),
	Demo(file: "Kite Season 2", series: "Kite Season", cover: "KITE SEASON", story: "Paper Wings", number: 2,
		 bg: rgb(0xF6A6B2), ink: rgb(0x3D1E2B), accent: rgb(0x2EC4B6), sky: [rgb(0xBDE4F4), rgb(0x8ECAE6)],
		 pages: 14, writer: "M. Rossi", artist: "C. Nakamura", year: 2025,
		 lines: ["MORE STRING!", "THERE IS NO MORE STRING!", "THEN TIE YOUR SHOELACE ON.", "THAT IS A TERRIBLE IDEA.", "IT'S FLYING, ISN'T IT?", "IT IS FLYING."],
		 motif: .kite),
	Demo(file: "The Glass Orchard 1", series: "The Glass Orchard", cover: "THE GLASS ORCHARD", story: "First Frost", number: 1,
		 bg: rgb(0x6A994E), ink: rgb(0xF2E8CF), accent: rgb(0xBC4749), sky: [rgb(0xF2E8CF), rgb(0xA7C957)],
		 pages: 16, writer: "H. Quist", artist: "D. Ferreira", year: 2024,
		 lines: ["THE APPLES ARE RINGING.", "THAT MEANS FROST.", "CAN WE SAVE THEM?", "WE CAN LISTEN TO THEM.", "THAT'S NOT THE SAME THING.", "IT IS TONIGHT."],
		 motif: .orchard),
	Demo(file: "Copper Fox 5", series: "Copper Fox", cover: "COPPER FOX", story: "Foxfire", number: 5,
		 bg: rgb(0xD9752B), ink: rgb(0xFFF8EE), accent: rgb(0x2D3047), sky: [rgb(0xFFD6A5), rgb(0xE07A3F)],
		 pages: 15, writer: "A. Vance", artist: "B. Kowalski", year: 2026,
		 lines: ["SOMEONE TOOK THE BELL.", "WHO STEALS A BELL?", "SOMEONE WHO WANTS QUIET.", "OR SOMEONE WHO WANTS NOISE.", "FOX TRACKS. COPPER ONES.", "OF COURSE THEY ARE."],
		 motif: .dusk),
	Demo(file: "Static Bloom 1", series: "Static Bloom", cover: "STATIC BLOOM", story: "Signal", number: 1,
		 bg: rgb(0x7B2CBF), ink: rgb(0xF8F0FF), accent: rgb(0xFF9E00), sky: [rgb(0xE0AAFF), rgb(0x9D4EDD)],
		 pages: 14, writer: "Y. Park", artist: "F. Duarte", year: 2025,
		 lines: ["CAN YOU HEAR THE FLOWERS?", "THAT'S JUST THE RADIO.", "THE RADIO IS OFF.", "...OH.", "THEY'RE SINGING OUR SONG.", "WE DON'T HAVE A SONG."],
		 motif: .bloom),
	Demo(file: "Little Tempest 2", series: "Little Tempest", cover: "LITTLE TEMPEST", story: "Teacup Storm", number: 2,
		 bg: rgb(0x5FA8D3), ink: rgb(0x0B2545), accent: rgb(0xFFD166), sky: [rgb(0xCAE9FF), rgb(0x62B6CB)],
		 pages: 14, writer: "G. Mbeki", artist: "O. Lindgren", year: 2026,
		 lines: ["IS IT RAINING INDOORS?", "ONLY OVER YOUR DESK.", "WHY MY DESK?", "IT LIKES YOU.", "TELL IT TO STOP.", "IT DOESN'T LISTEN. IT'S TWO."],
		 motif: .rain),
	Demo(file: "Ember & Ash 1", series: "Ember & Ash", cover: "EMBER\n& ASH", story: "Kindling", number: 1,
		 bg: rgb(0x2B2D42), ink: rgb(0xEF8354), accent: rgb(0xEF8354), sky: [rgb(0x8D99AE), rgb(0x2B2D42)],
		 pages: 16, writer: "S. Laurent", artist: "R. Iqbal", year: 2024,
		 lines: ["THE FIRE WENT OUT.", "FIRES DON'T GO OUT HERE.", "THIS ONE DID.", "THEN WHO IS WATCHING THE GATE?", "WE ARE.", "BRING THE MATCHES."],
		 motif: .stripes),
]

// MARK: Drawing helpers

func fill(_ path: NSBezierPath, _ c: NSColor) { c.setFill(); path.fill() }
func fillRect(_ r: NSRect, _ c: NSColor) { fill(NSBezierPath(rect: r), c) }

func gradient(_ r: NSRect, _ colors: [NSColor], angle: Double = 90) {
	NSGradient(colors: colors)?.draw(in: r, angle: angle)
}

func font(_ size: Double, _ weight: NSFont.Weight = .black) -> NSFont {
	let base = NSFont.systemFont(ofSize: size, weight: weight)
	if let d = base.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: d, size: size) ?? base }
	return base
}

func comicFont(_ size: Double) -> NSFont {
	NSFont(name: "ChalkboardSE-Bold", size: size) ?? font(size, .heavy)
}

func draw(_ s: String, centeredAt p: NSPoint, _ f: NSFont, _ c: NSColor, maxWidth: Double = .infinity) {
	var f = f
	var a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c])
	while a.size().width > maxWidth, f.pointSize > 10 {
		f = NSFont(descriptor: f.fontDescriptor, size: f.pointSize * 0.94) ?? f
		a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c])
	}
	let size = a.size()
	a.draw(at: NSPoint(x: p.x - size.width / 2, y: p.y - size.height / 2))
}

func bitmap(_ w: Double, _ h: Double, _ body: () -> Void) -> NSBitmapImageRep {
	// Drawn in 1600×2400 points; GENDEMO_SCALE renders them at fewer pixels.
	let scale = ProcessInfo.processInfo.environment["GENDEMO_SCALE"].flatMap(Double.init) ?? 1
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
							   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
							   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
	rep.size = NSSize(width: w, height: h)
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	body()
	NSGraphicsContext.restoreGraphicsState()
	return rep
}

func bubble(_ text: String, in panel: NSRect, rng: inout RNG, tailTo: NSPoint?) {
	let f = comicFont(46)
	let para = NSMutableParagraphStyle(); para.alignment = .center
	let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: NSColor.black, .paragraphStyle: para]
	let maxTextW = min(panel.width * 0.62, 520)
	let a = NSAttributedString(string: text, attributes: attrs)
	let bounds = a.boundingRect(with: NSSize(width: maxTextW, height: 1000), options: [.usesLineFragmentOrigin])
	let bw = bounds.width + 80, bh = bounds.height + 60
	let x = rng.range(panel.minX + 24, max(panel.minX + 24, panel.maxX - bw - 24))
	let y = panel.maxY - bh - rng.range(24, 60)
	let rect = NSRect(x: x, y: y, width: bw, height: bh)
	let shape = NSBezierPath(ovalIn: rect)
	if let t = tailTo {
		let tail = NSBezierPath()
		tail.move(to: NSPoint(x: rect.midX - 30, y: rect.minY + 20))
		tail.line(to: NSPoint(x: rect.midX + (t.x < rect.midX ? -50 : 50), y: rect.minY - 80))
		tail.line(to: NSPoint(x: rect.midX + 30, y: rect.minY + 20))
		tail.close()
		fill(tail, .white); NSColor.black.setStroke(); tail.lineWidth = 6; tail.stroke()
	}
	fill(shape, .white)
	NSColor.black.setStroke(); shape.lineWidth = 6; shape.stroke()
	a.draw(with: NSRect(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2,
						width: bounds.width, height: bounds.height), options: [.usesLineFragmentOrigin])
}

// MARK: Pages

func tone(_ c: NSColor, _ amount: Double, toward other: NSColor) -> NSColor {
	c.blended(withFraction: amount, of: other) ?? c
}

/// One large shape, tone on tone, that gives each cover its character.
func motif(_ d: Demo, in r: NSRect, _ c: NSColor) {
	let w = r.width, h = r.height
	switch d.motif {
	case .sun:
		fill(NSBezierPath(ovalIn: NSRect(x: r.minX + w * 0.28, y: r.minY + h * 0.12, width: w * 0.95, height: w * 0.95)), c)
	case .moon:
		fill(NSBezierPath(ovalIn: NSRect(x: r.minX + w * 0.38, y: r.minY + h * 0.36, width: w * 0.5, height: w * 0.5)), c)
		fill(NSBezierPath(ovalIn: NSRect(x: r.minX + w * 0.5, y: r.minY + h * 0.42, width: w * 0.5, height: w * 0.5)), d.bg)
	case .waves:
		for i in 0..<5 {
			let p = NSBezierPath(); p.lineWidth = w * 0.035; p.lineCapStyle = .round
			let y0 = r.minY + h * (0.16 + Double(i) * 0.075)
			p.move(to: NSPoint(x: r.minX - 40, y: y0))
			var x = r.minX - 40
			while x < r.maxX + 40 { p.curve(to: NSPoint(x: x + 260, y: y0), controlPoint1: NSPoint(x: x + 85, y: y0 + 70), controlPoint2: NSPoint(x: x + 175, y: y0 - 70)); x += 260 }
			c.setStroke(); p.stroke()
		}
	case .circuit:
		for i in 0..<4 {
			let inset = Double(i) * w * 0.09
			let sq = NSRect(x: r.minX + w * 0.2 + inset, y: r.minY + h * 0.1 + inset, width: w * 0.7 - 2 * inset, height: w * 0.7 - 2 * inset)
			let p = NSBezierPath(roundedRect: sq, xRadius: 40, yRadius: 40); p.lineWidth = w * 0.03
			c.setStroke(); p.stroke()
		}
	case .mountains:
		let p = NSBezierPath()
		p.move(to: NSPoint(x: r.minX - 100, y: r.minY)); p.line(to: NSPoint(x: r.minX + w * 0.42, y: r.minY + h * 0.55))
		p.line(to: NSPoint(x: r.minX + w * 0.62, y: r.minY + h * 0.38)); p.line(to: NSPoint(x: r.minX + w * 0.8, y: r.minY + h * 0.5))
		p.line(to: NSPoint(x: r.maxX + 100, y: r.minY)); p.close()
		fill(p, c)
	case .kite:
		let cx = r.minX + w * 0.6, cy = r.minY + h * 0.38, k = w * 0.32
		let p = NSBezierPath()
		p.move(to: NSPoint(x: cx, y: cy + k)); p.line(to: NSPoint(x: cx + k * 0.7, y: cy)); p.line(to: NSPoint(x: cx, y: cy - k * 1.3)); p.line(to: NSPoint(x: cx - k * 0.7, y: cy)); p.close()
		fill(p, c)
	case .orchard:
		let d0 = w * 0.13
		for row in 0..<4 { for col in 0..<5 {
			let x = r.minX + w * 0.1 + Double(col) * d0 * 1.45, y = r.minY + h * 0.1 + Double(row) * d0 * 1.45
			fill(NSBezierPath(ovalIn: NSRect(x: x, y: y, width: d0, height: d0)), c)
		} }
	case .bloom:
		for i in 0..<5 {
			let d0 = w * (0.95 - Double(i) * 0.18)
			let p = NSBezierPath(ovalIn: NSRect(x: r.minX + w * 0.55 - d0 / 2, y: r.minY + h * 0.38 - d0 / 2, width: d0, height: d0))
			p.lineWidth = w * 0.03; c.setStroke(); p.stroke()
		}
	case .rain:
		for i in 0..<9 { for j in 0..<6 {
			let x = r.minX + w * 0.05 + Double(i) * w * 0.115 + Double(j % 2) * w * 0.05
			let y = r.minY + h * 0.06 + Double(j) * h * 0.11
			let p = NSBezierPath(); p.lineWidth = w * 0.022; p.lineCapStyle = .round
			p.move(to: NSPoint(x: x, y: y)); p.line(to: NSPoint(x: x - w * 0.035, y: y - h * 0.05))
			c.setStroke(); p.stroke()
		} }
	case .dusk:
		fill(NSBezierPath(ovalIn: NSRect(x: r.minX + w * 0.1, y: r.minY - w * 0.4, width: w * 0.8, height: w * 0.8)), c)
	case .stripes:
		let p = NSBezierPath()
		for i in 0..<8 {
			let x = r.minX - w * 0.6 + Double(i) * w * 0.24
			p.move(to: NSPoint(x: x, y: r.minY)); p.line(to: NSPoint(x: x + w * 0.1, y: r.minY))
			p.line(to: NSPoint(x: x + w * 0.1 + h * 0.6, y: r.minY + h * 0.6)); p.line(to: NSPoint(x: x + h * 0.6, y: r.minY + h * 0.6)); p.close()
		}
		fill(p, c)
	case .city:
		var x = r.minX + w * 0.06
		for f in [0.42, 0.62, 0.34, 0.74, 0.5, 0.28] {
			fillRect(NSRect(x: x, y: r.minY, width: w * 0.12, height: h * f), c)
			x += w * 0.15
		}
	}
}

func renderCover(_ d: Demo) -> NSBitmapImageRep {
	bitmap(W, H) {
		let page = NSRect(x: 0, y: 0, width: W, height: H)
		fillRect(page, d.bg)
		NSGraphicsContext.saveGraphicsState()
		NSBezierPath(rect: page).addClip()
		let light = d.ink.brightnessComponent > d.bg.brightnessComponent
		motif(d, in: NSRect(x: 0, y: 0, width: W, height: H * 0.78), tone(d.bg, 0.16, toward: light ? .white : .black))
		// One small accent, the only other colour on the cover.
		fill(NSBezierPath(ovalIn: NSRect(x: W - 230, y: H - 230, width: 90, height: 90)), d.accent)
		NSGraphicsContext.restoreGraphicsState()

		let left = 130.0
		var y = H - 200
		let words = d.cover.contains("\n") ? d.cover.components(separatedBy: "\n") : d.cover.components(separatedBy: " ")
		var size = words.count > 2 ? 210.0 : 250.0
		// Shrink until the longest line fits between the margins and the accent dot.
		while words.contains(where: { NSAttributedString(string: $0, attributes: [.font: font(size), .kern: -4]).size().width > W - left - 260 }) { size -= 6 }
		for word in words {
			let a = NSAttributedString(string: word, attributes: [.font: font(size), .foregroundColor: d.ink, .kern: -4])
			y -= a.size().height * 0.86
			a.draw(at: NSPoint(x: left - 8, y: y))
		}
		let issue = NSAttributedString(string: "Nº \(d.number)  ·  \(d.story.uppercased())",
									   attributes: [.font: font(64, .bold), .foregroundColor: d.ink.withAlphaComponent(0.85), .kern: 3])
		issue.draw(at: NSPoint(x: left, y: y - 110))
		let pub = NSAttributedString(string: "WIREDFRAME COMICS", attributes: [.font: font(52, .heavy), .foregroundColor: d.ink.withAlphaComponent(0.75), .kern: 6])
		pub.draw(at: NSPoint(x: left, y: 120))
	}
}

func renderPage(_ d: Demo, _ index: Int) -> NSBitmapImageRep {
	bitmap(W, H) {
		var rng = RNG(state: UInt64(index * 977 + d.series.count * 131))
		fillRect(NSRect(x: 0, y: 0, width: W, height: H), rgb(0xFBFAF7))
		let m = 90.0, gap = 30.0
		let content = NSRect(x: m, y: m + 50, width: W - 2 * m, height: H - 2 * m - 50)
		let grids: [[Double]] = [[1, 2, 2], [2, 1, 2], [1, 1, 1], [2, 2, 1], [1, 2]]
		let rows = rng.pick(grids)
		let rowH = (content.height - gap * Double(rows.count - 1)) / Double(rows.count)
		var lineIndex = index * 5
		for (ri, cols) in rows.enumerated() {
			let y = content.maxY - Double(ri + 1) * rowH - Double(ri) * gap
			let n = Int(cols)
			let colW = (content.width - gap * Double(n - 1)) / Double(n)
			for ci in 0..<n {
				let r = NSRect(x: content.minX + Double(ci) * (colW + gap), y: y, width: colW, height: rowH)
				NSGraphicsContext.saveGraphicsState()
				NSBezierPath(rect: r).addClip()
				// Flat tints of the cover colour, a horizon or a disc now and then.
				let tint = tone(d.bg, rng.range(0.45, 0.8), toward: .white)
				fillRect(r, tint)
				let shade = tone(tint, 0.14, toward: d.bg.brightnessComponent > 0.5 ? .black : d.bg)
				switch Int(rng.next() * 3) {
				case 0: fillRect(NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height * rng.range(0.25, 0.45)), shade)
				case 1:
					let s = min(r.width, r.height) * rng.range(0.35, 0.6)
					fill(NSBezierPath(ovalIn: NSRect(x: r.minX + rng.range(0.1, 0.9) * (r.width - s), y: r.minY + rng.range(0.1, 0.6) * (r.height - s), width: s, height: s)), shade)
				default: break
				}
				if rng.next() > 0.45 {
					bubble(d.lines[lineIndex % d.lines.count], in: r, rng: &rng,
						   tailTo: NSPoint(x: r.midX, y: r.maxY - 330))
					lineIndex += 1
				}
				NSGraphicsContext.restoreGraphicsState()
				rgb(0x222222).setStroke()
				let border = NSBezierPath(rect: r); border.lineWidth = 6; border.stroke()
			}
		}
		draw("\(index + 1)", centeredAt: NSPoint(x: W / 2, y: 80), font(34, .semibold), rgb(0x888888))
	}
}

// MARK: ComicInfo and packing

func xml(_ s: String) -> String {
	s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}

func comicInfo(_ d: Demo) -> String {
	"""
	<?xml version="1.0" encoding="utf-8"?>
	<ComicInfo>
	  <Title>\(xml(d.story))</Title>
	  <Series>\(xml(d.series))</Series>
	  <Number>\(d.number)</Number>
	  <Year>\(d.year)</Year>
	  <Writer>\(xml(d.writer))</Writer>
	  <Penciller>\(xml(d.artist))</Penciller>
	  <Publisher>Wiredframe Comics</Publisher>
	  <Summary>1. [Story] «\(xml(d.story))» {WF \(String(format: "%03d", d.number))-A}
	   Script: \(xml(d.writer)) · Art: \(xml(d.artist))
	2. [Story] «Postcards» {WF \(String(format: "%03d", d.number))-B}
	   Script: \(xml(d.artist)) · Art: \(xml(d.writer))</Summary>
	  <PageCount>\(d.pages + 1)</PageCount>
	  <LanguageISO>en</LanguageISO>
	</ComicInfo>
	"""
}

func png(_ rep: NSBitmapImageRep) -> Data {
	// JPEG keeps the archives small; the pages are flat colour and survive it well.
	rep.representation(using: .jpeg, properties: [.compressionFactor: quality])!
}

let env = ProcessInfo.processInfo.environment
let quality = env["GENDEMO_QUALITY"].flatMap(Double.init) ?? 0.85
let only = env["GENDEMO_ONLY"].map { Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
let fm = FileManager.default
for d in demos where only?.contains(d.series) ?? true {
	let work = fm.temporaryDirectory.appendingPathComponent("gendemo-\(UUID().uuidString)")
	try fm.createDirectory(at: work, withIntermediateDirectories: true)
	try png(renderCover(d)).write(to: work.appendingPathComponent("000.jpg"))
	for i in 1...d.pages {
		try png(renderPage(d, i)).write(to: work.appendingPathComponent(String(format: "%03d.jpg", i)))
	}
	try comicInfo(d).write(to: work.appendingPathComponent("ComicInfo.xml"), atomically: true, encoding: .utf8)
	let out = outDir.appendingPathComponent("\(d.file).cbz")
	try? fm.removeItem(at: out)
	let zip = Process()
	zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
	zip.currentDirectoryURL = work
	zip.arguments = ["-q", "-0", out.path] + (try fm.contentsOfDirectory(atPath: work.path).sorted())
	try zip.run(); zip.waitUntilExit()
	try? fm.removeItem(at: work)
	print("wrote \(out.lastPathComponent)")
}
