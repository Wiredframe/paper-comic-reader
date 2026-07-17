// gendemo.swift — renders the app's four bundled demo comics: a plain solid-colour
// cover + a run of white pages, each with one big light-grey page number centred, so
// a reader can orient with nothing to read. Deliberately minimal and fully original,
// so it's rights-clean for App Store screenshots and as sample content. Also writes a
// ComicInfo.xml per comic (pseudo credits/summary) and a preview.png contact sheet.
//
//   swift gendemo.swift <out-dir>
//
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let W = 2000.0, H = 3000.0            // 2:3 comic page, crisp on iPad
let pageGrey = NSColor(srgbRed: 0.82, green: 0.82, blue: 0.85, alpha: 1)   // "hellgrau"

func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

// MARK: Model — a demo comic and its pseudo metadata.
struct Demo {
    let file: String        // output .cbz base name
    let series: String
    let title: String       // cover title (usually == series here)
    let issueTitle: String  // ComicInfo <Title> — the lead story, shown as the card subtitle
    let bg: NSColor         // solid cover colour
    let onBg: NSColor       // cover text colour
    let pages: Int          // interior pages (excludes the cover)
    let writer: String
    let penciller: String
    let year: Int
    let summary: String     // ComicInfo <Summary> — one uses the story-index format
}

// Yellow (the brand) + three fitting comic colours: red, blue, teal.
let demos: [Demo] = [
    Demo(file: "Solar Flare", series: "Solar Flare", title: "SOLAR FLARE", issueTitle: "Ignition",
         bg: rgb(0.99, 0.83, 0.16), onBg: rgb(0.15, 0.12, 0.02), pages: 13,
         writer: "A. Vance", penciller: "M. Okafor", year: 2026,
         // Story-index format — lights up the detail view's story list.
         summary: """
         1. [Story] «Ignition» {WF 001-A}
            Script: A. Vance · Art: M. Okafor
         2. [Story] «Coronal Mass» {WF 001-B}
            Script: A. Vance · Art: L. Bianchi
         3. [Pin-up] «First Light» {WF 001-C}
            Art: M. Okafor
         """),
    Demo(file: "Crimson Alley", series: "Crimson Alley", title: "CRIMSON ALLEY", issueTitle: "The Long Rain",
         bg: rgb(0.85, 0.24, 0.24), onBg: .white, pages: 11,
         writer: "R. Delgado", penciller: "S. Kerr", year: 2025,
         summary: "Rain never stops in the Alley, and neither does Detective Vale. A missing-persons case turns into something the whole precinct would rather forget."),
    Demo(file: "Deep Blue", series: "Deep Blue", title: "DEEP BLUE", issueTitle: "The Halcyon Dive",
         bg: rgb(0.20, 0.47, 0.85), onBg: .white, pages: 15,
         writer: "N. Fisher", penciller: "T. Amari", year: 2026,
         summary: "A kilometre down, the research sub Halcyon finds a light that shouldn't exist. The crew has one dive of air to decide whether to follow it."),
    Demo(file: "Jade Circuit", series: "Jade Circuit", title: "JADE CIRCUIT", issueTitle: "Borrowed Memory",
         bg: rgb(0.11, 0.62, 0.55), onBg: .white, pages: 12,
         writer: "K. Sole", penciller: "D. Rhodes", year: 2025,
         summary: "In a city that runs on borrowed memory, a courier wakes with one she can't account for — and every fixer in the Circuit wants it back."),
]

// MARK: Drawing helpers
func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); NSBezierPath(rect: r).fill() }

func rounded(_ size: Double, _ weight: NSFont.Weight = .black) -> NSFont {
    if let d = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.rounded) {
        return NSFont(descriptor: d, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }
    return NSFont.systemFont(ofSize: size, weight: weight)
}

func attr(_ s: String, _ f: NSFont, _ c: NSColor) -> NSAttributedString {
    let ps = NSMutableParagraphStyle(); ps.alignment = .center
    return NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c, .paragraphStyle: ps])
}

func drawCentered(_ s: String, cx: Double, cy: Double, _ f: NSFont, _ c: NSColor) {
    let a = attr(s, f, c); let sz = a.size()
    a.draw(at: NSPoint(x: cx - sz.width / 2, y: cy - sz.height / 2))
}

// Title fitted to a max width (scales down if needed), centred at y.
func drawFitted(_ s: String, cx: Double, cy: Double, maxW: Double, base: Double, _ c: NSColor) {
    var size = base
    while size > 48, attr(s, rounded(size), c).size().width > maxW { size -= 8 }
    drawCentered(s, cx: cx, cy: cy, rounded(size), c)
}

// MARK: Renderers → 8-bit RGB bitmap (no alpha), so solid covers and white pages
// compress to a few KB instead of the multi-MB Retina/16-bit blobs lockFocus makes.
func bitmap(_ w: Double, _ h: Double, _ body: () -> Void) -> NSBitmapImageRep {
    // 4 samples + alpha: the 3-sample/no-alpha rep yields a nil drawing context, which
    // silently leaves the zeroed (black) buffer. Alpha compresses to nothing on solid pages.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        FileHandle.standardError.write("no bitmap context\n".data(using: .utf8)!); return rep
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    body()
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func renderCover(_ d: Demo) -> NSBitmapImageRep {
    bitmap(W, H) {
        fill(NSRect(x: 0, y: 0, width: W, height: H), d.bg)
        // Title block, upper-middle.
        drawFitted(d.title, cx: W / 2, cy: H * 0.60, maxW: W - 320, base: 260, d.onBg)
        // Thin accent rule + issue tag.
        fill(NSRect(x: W / 2 - 220, y: H * 0.60 - 190, width: 440, height: 10), d.onBg)
        drawCentered("ISSUE #1", cx: W / 2, cy: H * 0.60 - 290, rounded(70, .heavy), d.onBg)
        // Quiet footer.
        drawCentered("WIREDFRAME COMICS", cx: W / 2, cy: 190, rounded(48, .semibold),
                     d.onBg.withAlphaComponent(0.7))
    }
}

// A white interior page with one big light-grey page number (its reader page index).
func renderPage(_ readerPage: Int) -> NSBitmapImageRep {
    bitmap(W, H) {
        fill(NSRect(x: 0, y: 0, width: W, height: H), .white)
        drawCentered("\(readerPage)", cx: W / 2, cy: H / 2, rounded(H * 0.38, .black), pageGrey)
    }
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) {
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
    } else {
        FileHandle.standardError.write("render failed \(url.lastPathComponent)\n".data(using: .utf8)!)
    }
}

func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
}

func comicInfo(_ d: Demo) -> String {
    """
    <?xml version="1.0" encoding="utf-8"?>
    <ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <Series>\(xmlEscape(d.series))</Series>
      <Number>1</Number>
      <Title>\(xmlEscape(d.issueTitle))</Title>
      <Writer>\(xmlEscape(d.writer))</Writer>
      <Penciller>\(xmlEscape(d.penciller))</Penciller>
      <Publisher>Wiredframe Comics</Publisher>
      <Year>\(d.year)</Year>
      <LanguageISO>en</LanguageISO>
      <PageCount>\(d.pages + 1)</PageCount>
      <Summary>\(xmlEscape(d.summary))</Summary>
    </ComicInfo>
    """
}

// MARK: Generate
let fm = FileManager.default
for d in demos {
    let dir = URL(fileURLWithPath: outDir).appendingPathComponent(d.file)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    // page-01 = cover; page-02… = numbered white pages (numbers match the reader).
    writePNG(renderCover(d), to: dir.appendingPathComponent("page-01.png"))
    for p in 2...(d.pages + 1) {
        writePNG(renderPage(p), to: dir.appendingPathComponent(String(format: "page-%02d.png", p)))
    }
    try? comicInfo(d).write(to: dir.appendingPathComponent("ComicInfo.xml"), atomically: true, encoding: .utf8)
    print("rendered \(d.file) — \(d.pages + 1) pages")
}

// MARK: Preview contact sheet — 4 covers + one sample interior page.
let tileW = 300.0, tileH = 450.0, pad = 28.0
let cols = 5.0
let sheetW = cols * tileW + (cols + 1) * pad
let sheetH = tileH + 2 * pad
var tiles: [NSBitmapImageRep] = demos.map(renderCover)
tiles.append(renderPage(7))
let sheet = bitmap(sheetW, sheetH) {
    fill(NSRect(x: 0, y: 0, width: sheetW, height: sheetH), rgb(0.93, 0.93, 0.95))
    for (i, tile) in tiles.enumerated() {
        let x = pad + Double(i) * (tileW + pad)
        tile.draw(in: NSRect(x: x, y: pad, width: tileW, height: tileH))
    }
}
writePNG(sheet, to: URL(fileURLWithPath: outDir).appendingPathComponent("preview.png"))
print("wrote preview.png")
print("done → \(outDir)")
