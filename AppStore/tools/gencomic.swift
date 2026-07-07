// gencomic.swift — renders an original sample comic ("INKLINGS #1") as page PNGs.
// Brand-matched to the app icon (yellow gradient + white speech bubbles). Fully
// original artwork (abstract geometric characters) so it is rights-clean for use in
// App Store screenshots and as the App Review demo file.
//
//   swift gencomic.swift <output-dir>
//
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let W = 2000.0, H = 3000.0

// MARK: Palette (sRGB, close to the icon's display-p3 gradient)
let ink    = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
let cream  = NSColor(srgbRed: 0.965, green: 0.935, blue: 0.865, alpha: 1)
let yellow = NSColor(srgbRed: 0.99, green: 0.90, blue: 0.16, alpha: 1)
let amber  = NSColor(srgbRed: 1.00, green: 0.80, blue: 0.11, alpha: 1)
let white  = NSColor.white
let red    = NSColor(srgbRed: 0.90, green: 0.26, blue: 0.22, alpha: 1)
let blue   = NSColor(srgbRed: 0.24, green: 0.47, blue: 0.86, alpha: 1)
let sky    = NSColor(srgbRed: 0.86, green: 0.90, blue: 0.95, alpha: 1)

// MARK: Coordinate helper — spec rects from the TOP (y-down), converted to AppKit's
// y-up space so shapes and text share one mental model.
func rt(_ x: Double, _ yTop: Double, _ w: Double, _ h: Double) -> NSRect {
    NSRect(x: x, y: H - yTop - h, width: w, height: h)
}
func pt(_ x: Double, _ yTop: Double) -> NSPoint { NSPoint(x: x, y: H - yTop) }

// MARK: Primitives
func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); NSBezierPath(rect: r).fill() }

func gradient(_ r: NSRect, _ top: NSColor, _ bottom: NSColor) {
    NSGradient(colors: [top, bottom])?.draw(in: NSBezierPath(rect: r), angle: -90)
}

func roundedFill(_ r: NSRect, _ radius: Double, _ c: NSColor) {
    c.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
}

func stroke(_ path: NSBezierPath, _ c: NSColor, _ lw: Double) {
    c.setStroke(); path.lineWidth = lw; path.lineJoinStyle = .round; path.stroke()
}

// A comic panel: cream fill + thick ink border. Returns the inner rect.
@discardableResult
func panel(_ r: NSRect, fillColor: NSColor = cream, lw: Double = 10) -> NSRect {
    fillColor.setFill()
    let p = NSBezierPath(rect: r); p.fill()
    stroke(NSBezierPath(rect: r), ink, lw)
    return r.insetBy(dx: lw, dy: lw)
}

func clip(_ r: NSRect, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: r).addClip()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

// Even Ben-Day style halftone dots across a rect.
func halftone(_ r: NSRect, spacing: Double, radius: Double, _ c: NSColor) {
    c.setFill()
    var y = r.minY
    while y < r.maxY {
        var x = r.minX
        while x < r.maxX {
            NSBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius, width: radius*2, height: radius*2)).fill()
            x += spacing
        }
        y += spacing
    }
}

// Diagonal "burst" rays emanating from a center.
func rays(cx: Double, cyTop: Double, count: Int, inner: Double, outer: Double, _ c: NSColor, width: Double = 8) {
    let cy = H - cyTop
    c.setStroke()
    for i in 0..<count {
        let a = Double(i) / Double(count) * 2 * .pi
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx + cos(a)*inner, y: cy + sin(a)*inner))
        p.line(to: NSPoint(x: cx + cos(a)*outer, y: cy + sin(a)*outer))
        p.lineWidth = width; p.stroke()
    }
}

// MARK: Text — single line placed by its top-left / center, upright in y-up space.
func attr(_ s: String, _ font: NSFont, _ color: NSColor, align: NSTextAlignment = .center) -> NSAttributedString {
    let ps = NSMutableParagraphStyle(); ps.alignment = align; ps.lineSpacing = 6
    return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: ps])
}
func textCentered(_ s: String, cx: Double, topY: Double, _ font: NSFont, _ color: NSColor) {
    let a = attr(s, font, color); let sz = a.size()
    a.draw(at: NSPoint(x: cx - sz.width/2, y: H - topY - sz.height))
}
func textLeft(_ s: String, x: Double, topY: Double, _ font: NSFont, _ color: NSColor) {
    let a = attr(s, font, color, align: .left); let sz = a.size()
    a.draw(at: NSPoint(x: x, y: H - topY - sz.height))
}
// Wrapped multi-line block inside a rect (top-aligned), returns used height.
@discardableResult
func textBlock(_ s: String, in r: NSRect, _ font: NSFont, _ color: NSColor, align: NSTextAlignment = .center) -> Double {
    let a = attr(s, font, color, align: align)
    let bounds = a.boundingRect(with: NSSize(width: r.width, height: 10000), options: [.usesLineFragmentOrigin])
    let drawRect = NSRect(x: r.minX, y: r.maxY - bounds.height, width: r.width, height: bounds.height)
    a.draw(with: drawRect, options: [.usesLineFragmentOrigin])
    return bounds.height
}

func font(_ size: Double, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}
func rounded(_ size: Double, _ weight: NSFont.Weight = .heavy) -> NSFont {
    if let d = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        .withDesign(.rounded) { return NSFont(descriptor: d, size: size) ?? font(size, weight) }
    return font(size, weight)
}

// MARK: Speech bubble — rounded white bubble + tail, centered text.
func bubble(_ r: NSRect, tail: NSPoint?, _ lines: String, _ f: NSFont, textColor: NSColor = ink, fillColor: NSColor = white) {
    let radius = min(r.height, r.width) * 0.28
    // 1+2. body fill + outline
    roundedFill(r, radius, fillColor)
    stroke(NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius), ink, 7)
    // 3. tail — docks on the edge facing the speaker and points outward, so it never
    //    crosses the bubble face. The white triangle fill also hides the body outline
    //    at the tail mouth (drawn after the body stroke).
    if let t = tail {
        let cx = r.midX, cy = r.midY
        let dx = t.x - cx, dy = t.y - cy
        var baseC: NSPoint; var tangent: NSPoint
        if abs(dy) * r.width >= abs(dx) * r.height {
            // top or bottom edge (y-up: minY = bottom)
            let bx = min(max(t.x, r.minX + radius + 50), r.maxX - radius - 50)
            baseC = NSPoint(x: bx, y: t.y < cy ? r.minY : r.maxY)
            tangent = NSPoint(x: 1, y: 0)
        } else {
            let by = min(max(t.y, r.minY + radius + 40), r.maxY - radius - 40)
            baseC = NSPoint(x: t.x < cx ? r.minX : r.maxX, y: by)
            tangent = NSPoint(x: 0, y: 1)
        }
        let half = 44.0
        let baseA = NSPoint(x: baseC.x + tangent.x*half, y: baseC.y + tangent.y*half)
        let baseB = NSPoint(x: baseC.x - tangent.x*half, y: baseC.y - tangent.y*half)
        let dist = max(sqrt(dx*dx + dy*dy), 1)
        let len = min(dist, 160)
        let tip = NSPoint(x: baseC.x + dx/dist*len, y: baseC.y + dy/dist*len)
        let tri = NSBezierPath(); tri.move(to: baseA); tri.line(to: baseB); tri.line(to: tip); tri.close()
        fillColor.setFill(); tri.fill()
        let edge = NSBezierPath()
        edge.move(to: baseA); edge.line(to: tip); edge.move(to: baseB); edge.line(to: tip)
        stroke(edge, ink, 7)
    }
    // 4. text on top
    let inset = r.insetBy(dx: r.width*0.10, dy: r.height*0.12)
    textBlock(lines, in: inset, f, textColor)
}

// MARK: Character — a round "inkling" (body circle, eyes, little smile, feet).
func inkling(cx: Double, cyTop: Double, radius: Double, body: NSColor, looking: Double = 0) {
    let cy = H - cyTop
    // feet
    ink.setFill()
    NSBezierPath(ovalIn: NSRect(x: cx - radius*0.55, y: cy - radius - radius*0.35, width: radius*0.5, height: radius*0.4)).fill()
    NSBezierPath(ovalIn: NSRect(x: cx + radius*0.05, y: cy - radius - radius*0.35, width: radius*0.5, height: radius*0.4)).fill()
    // body
    body.setFill()
    let b = NSBezierPath(ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius*2, height: radius*2)); b.fill()
    stroke(NSBezierPath(ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius*2, height: radius*2)), ink, 7)
    // eyes
    ink.setFill()
    let ex = radius*0.35, ey = cy + radius*0.15, er = radius*0.16
    NSBezierPath(ovalIn: NSRect(x: cx - ex - er + looking*ex*0.4, y: ey - er, width: er*2, height: er*2)).fill()
    NSBezierPath(ovalIn: NSRect(x: cx + ex - er + looking*ex*0.4, y: ey - er, width: er*2, height: er*2)).fill()
    // smile
    let smile = NSBezierPath()
    smile.appendArc(withCenter: NSPoint(x: cx, y: cy - radius*0.05), radius: radius*0.45,
                    startAngle: 210, endAngle: 330)
    stroke(smile, ink, 6)
}

// MARK: Page renderer
func renderPage(_ index: Int, _ draw: () -> Void) {
    let img = NSImage(size: NSSize(width: W, height: H))
    img.lockFocus()
    // default page background
    fill(NSRect(x: 0, y: 0, width: W, height: H), cream)
    draw()
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("render failed page \(index)\n".data(using: .utf8)!); return
    }
    let name = String(format: "page-%02d.png", index)
    try? png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
    print("wrote \(name)")
}

let TITLE = rounded(210, .black)
let H1 = rounded(120, .black)
let H2 = rounded(64, .heavy)
let CAP = font(46, .semibold)
let BUB = rounded(52, .bold)
let BUBs = rounded(44, .bold)
let SFX = rounded(150, .black)

// ============================ PAGES ============================

// 1 — COVER
renderPage(1) {
    gradient(NSRect(x: 0, y: 0, width: W, height: H), yellow, amber)
    clip(NSRect(x: 0, y: 0, width: W, height: H)) {
        halftone(rt(-40, -40, W+80, 620), spacing: 44, radius: 9, ink.withAlphaComponent(0.12))
    }
    // big white bubble
    bubble(rt(W/2-360, 300, 720, 560), tail: pt(W/2+150, 900), "", H1)
    textCentered("!", cx: W/2, topY: 470, rounded(360, .black), amber)
    // title block
    textCentered("INKLINGS", cx: W/2, topY: 1180, TITLE, ink)
    fill(rt(W/2-320, 1420, 640, 12), ink)
    textCentered("ISSUE #1", cx: W/2, topY: 1470, H2, ink)
    // footer strip
    fill(rt(0, H-220, W, 220), ink)
    textCentered("A COMIC READER SAMPLE", cx: W/2, topY: H-170, rounded(56, .heavy), yellow)
    textCentered("Wiredframe", cx: W/2, topY: H-96, font(40, .medium), white.withAlphaComponent(0.85))
}

// 2 — SPLASH: the blank page
renderPage(2) {
    let inner = panel(rt(80, 80, W-160, H-160))
    // sky
    clip(inner) {
        gradient(inner, sky, cream)
        // ground line
        fill(NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: 200), cream)
        stroke({ let p = NSBezierPath(); p.move(to: NSPoint(x: inner.minX, y: inner.minY+200)); p.line(to: NSPoint(x: inner.maxX, y: inner.minY+200)); return p }(), ink, 8)
        inkling(cx: W/2, cyTop: H-360, radius: 150, body: yellow)
    }
    // caption box
    roundedFill(rt(160, 200, 900, 190), 8, white)
    stroke(NSBezierPath(roundedRect: rt(160, 200, 900, 190), xRadius: 8, yRadius: 8), ink, 6)
    textBlock("Every comic starts with a blank page…", in: rt(200, 235, 820, 130), CAP, ink, align: .left)
}

// 3 — FOUR PANELS: discovery
renderPage(3) {
    fill(NSRect(x: 0, y: 0, width: W, height: H), ink) // gutter
    let g = 26.0, m = 70.0
    let pw = (W - m*2 - g) / 2
    let ph = (H - m*2 - g) / 2
    let p1 = rt(m, m, pw, ph)
    let p2 = rt(m+pw+g, m, pw, ph)
    let p3 = rt(m, m+ph+g, pw, ph)
    let p4 = rt(m+pw+g, m+ph+g, pw, ph)
    // P1
    let i1 = panel(p1)
    clip(i1) { inkling(cx: i1.midX-120, cyTop: H-i1.minY-260, radius: 120, body: yellow, looking: 1) }
    bubble(NSRect(x: i1.midX+40, y: i1.maxY-230, width: 300, height: 170), tail: NSPoint(x: i1.midX+60, y: i1.maxY-240), "Oh?", BUB)
    // P2 — the glowing book
    let i2 = panel(p2)
    clip(i2) {
        rays(cx: i2.midX, cyTop: H-i2.midY, count: 20, inner: 190, outer: 520, amber.withAlphaComponent(0.55), width: 10)
        roundedFill(NSRect(x: i2.midX-150, y: i2.midY-190, width: 300, height: 380), 16, yellow)
        stroke(NSBezierPath(roundedRect: NSRect(x: i2.midX-150, y: i2.midY-190, width: 300, height: 380), xRadius: 16, yRadius: 16), ink, 8)
        textCentered("!", cx: i2.midX, topY: H-i2.midY-95, rounded(180, .black), ink)
    }
    textLeft("It was warm.", x: i2.minX+30, topY: H-i2.minY-70, CAP, ink)
    // P3 — reaching out
    let i3 = panel(p3)
    clip(i3) {
        inkling(cx: i3.midX-40, cyTop: H-i3.minY-300, radius: 140, body: yellow)
        halftone(NSRect(x: i3.midX+120, y: i3.midY-40, width: 260, height: 260), spacing: 34, radius: 7, red.withAlphaComponent(0.5))
    }
    textCentered("hummm…", cx: i3.midX, topY: H-i3.maxY+90, rounded(70, .black), red)
    // P4 — the flash
    let i4 = panel(p4, fillColor: white)
    clip(i4) {
        rays(cx: i4.midX, cyTop: H-i4.midY, count: 28, inner: 60, outer: 700, amber, width: 14)
        textCentered("!", cx: i4.midX, topY: H-i4.midY-190, SFX, ink)
    }
}

// 4 — SPLASH: inside the paperverse
renderPage(4) {
    let inner = panel(rt(80, 80, W-160, H-160), fillColor: ink)
    clip(inner) {
        // floating panels
        let recs = [(300.0,500.0,240.0,150.0),(1300.0,420.0,300.0,190.0),(520.0,1500.0,260.0,170.0),
                    (1250.0,1700.0,320.0,200.0),(820.0,900.0,300.0,190.0),(300.0,2200.0,280.0,180.0),
                    (1350.0,2350.0,260.0,170.0)]
        for (x,y,w,h) in recs {
            roundedFill(rt(x, y, w, h), 10, cream.withAlphaComponent(0.9))
            stroke(NSBezierPath(roundedRect: rt(x,y,w,h), xRadius: 10, yRadius: 10), yellow, 5)
        }
        halftone(inner, spacing: 70, radius: 4, yellow.withAlphaComponent(0.35))
        inkling(cx: W/2, cyTop: H/2+120, radius: 175, body: yellow)
    }
    roundedFill(rt(160, 190, 1000, 190), 8, yellow)
    stroke(NSBezierPath(roundedRect: rt(160,190,1000,190), xRadius: 8, yRadius: 8), ink, 6)
    textBlock("Inside, the pages went on forever.", in: rt(200, 225, 920, 130), CAP, ink, align: .left)
}

// 5 — THREE PANELS: dialogue (rich text for the Live Text screenshot)
renderPage(5) {
    fill(NSRect(x: 0, y: 0, width: W, height: H), ink)
    let m = 70.0, g = 26.0
    let ph = (H - m*2 - g*2) / 3
    let pA = rt(m, m, W-m*2, ph)
    let pB = rt(m, m+ph+g, W-m*2, ph)
    let pC = rt(m, m+ph*2+g*2, W-m*2, ph)
    // A
    let a = panel(pA)
    clip(a) { gradient(a, sky, cream); inkling(cx: a.minX+260, cyTop: H-a.minY-360, radius: 130, body: yellow) ; inkling(cx: a.maxX-260, cyTop: H-a.minY-360, radius: 130, body: blue, looking: -1) }
    bubble(NSRect(x: a.minX+80, y: a.maxY-210, width: 430, height: 150), tail: NSPoint(x: a.minX+260, y: a.minY+360), "Where are we?", BUBs)
    bubble(NSRect(x: a.maxX-500, y: a.minY+40, width: 460, height: 150), tail: NSPoint(x: a.maxX-260, y: a.minY+360), "Between the panels.", BUBs)
    // B
    let b = panel(pB)
    clip(b) { inkling(cx: b.midX, cyTop: H-b.minY-300, radius: 150, body: blue) ; halftone(b, spacing: 60, radius: 4, blue.withAlphaComponent(0.25)) }
    bubble(NSRect(x: b.midX-560, y: b.minY+50, width: 1120, height: 150), tail: NSPoint(x: b.midX, y: b.minY+300), "Every story ever drawn passes through here.", BUBs)
    // C
    let c = panel(pC)
    clip(c) { gradient(c, cream, yellow.withAlphaComponent(0.4)); inkling(cx: c.minX+260, cyTop: H-c.minY-360, radius: 130, body: yellow) ; inkling(cx: c.maxX-260, cyTop: H-c.minY-360, radius: 130, body: blue, looking: -1) }
    bubble(NSRect(x: c.minX+80, y: c.maxY-210, width: 560, height: 150), tail: NSPoint(x: c.minX+260, y: c.minY+360), "So… which one is ours?", BUBs)
    bubble(NSRect(x: c.maxX-540, y: c.minY+40, width: 500, height: 150), tail: NSPoint(x: c.maxX-260, y: c.minY+360), "The one you're reading.", BUBs)
}

// 6 — WIDE SPREAD (left half): the skyline of stories
renderPage(6) {
    gradient(NSRect(x: 0, y: 0, width: W, height: H), NSColor(srgbRed: 0.13, green: 0.16, blue: 0.28, alpha: 1), NSColor(srgbRed: 0.35, green: 0.28, blue: 0.42, alpha: 1))
    clip(NSRect(x: 0, y: 0, width: W, height: H)) {
        // stacked-book "buildings"
        let cols: [(Double,Double)] = [(120,900),(360,1300),(640,780),(900,1500),(1240,1050),(1560,1700),(1820,1150)]
        for (x,h) in cols {
            let w = 220.0
            fill(rt(x, H-h, w, h), NSColor(srgbRed: 0.10, green: 0.12, blue: 0.20, alpha: 1))
            stroke(NSBezierPath(rect: rt(x, H-h, w, h)), yellow.withAlphaComponent(0.5), 4)
            var yy = H-h+40
            while yy < H-60 { fill(rt(x+20, yy, w-40, 10), yellow.withAlphaComponent(0.35)); yy += 90 }
        }
        halftone(NSRect(x: 0, y: H-800, width: W, height: 800), spacing: 90, radius: 3, white.withAlphaComponent(0.25))
        inkling(cx: W-360, cyTop: H-260, radius: 150, body: yellow)
    }
}

// 7 — WIDE SPREAD (right half): the sun rises
renderPage(7) {
    gradient(NSRect(x: 0, y: 0, width: W, height: H), NSColor(srgbRed: 0.35, green: 0.28, blue: 0.42, alpha: 1), amber)
    clip(NSRect(x: 0, y: 0, width: W, height: H)) {
        // the sun — a giant speech bubble
        rays(cx: 720, cyTop: 820, count: 32, inner: 420, outer: 1400, yellow.withAlphaComponent(0.6), width: 16)
        let sunRect = NSRect(x: 720-380, y: H-820-300, width: 760, height: 600)
        roundedFill(sunRect, 200, yellow)
        stroke(NSBezierPath(roundedRect: sunRect, xRadius: 200, yRadius: 200), ink, 8)
        let tri = NSBezierPath(); tri.move(to: NSPoint(x: 720-70, y: H-820-300+20)); tri.line(to: NSPoint(x: 720+70, y: H-820-300+20)); tri.line(to: NSPoint(x: 720+180, y: H-820-460)); tri.close(); yellow.setFill(); tri.fill()
        textCentered("♥", cx: 720, topY: 700, rounded(260, .black), red)
        // skyline continues low
        let cols: [(Double,Double)] = [(60,520),(320,760),(640,600),(980,900),(1360,680),(1680,1020)]
        for (x,h) in cols {
            let w = 220.0
            fill(rt(x, H-h, w, h), NSColor(srgbRed: 0.20, green: 0.16, blue: 0.24, alpha: 0.9))
            var yy = H-h+40
            while yy < H-60 { fill(rt(x+20, yy, w-40, 10), yellow.withAlphaComponent(0.4)); yy += 90 }
        }
    }
}

// 8 — END CARD
renderPage(8) {
    gradient(NSRect(x: 0, y: 0, width: W, height: H), amber, yellow)
    clip(NSRect(x: 0, y: 0, width: W, height: H)) {
        halftone(rt(-40, H-560, W+80, 600), spacing: 44, radius: 9, ink.withAlphaComponent(0.12))
    }
    bubble(rt(W/2-520, 760, 1040, 620), tail: pt(W/2-260, 1420), "", H1)
    textCentered("THE END?", cx: W/2, topY: 980, rounded(150, .black), ink)
    inkling(cx: W/2, cyTop: 1720, radius: 150, body: yellow)
    fill(rt(0, H-240, W, 240), ink)
    textCentered("THANKS FOR READING", cx: W/2, topY: H-190, rounded(58, .heavy), yellow)
    textCentered("Made with Comic Reader", cx: W/2, topY: H-108, font(40, .medium), white.withAlphaComponent(0.85))
}

print("done → \(outDir)")
