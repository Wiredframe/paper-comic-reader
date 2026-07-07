// gencovers.swift — a handful of original, title-forward comic covers (one PNG each)
// in distinct colour worlds, to fill the Library grid in App Store screenshots.
//   swift gencovers.swift <out-dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let W = 2000.0, H = 3000.0
let ink = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)

func rt(_ x: Double,_ yTop: Double,_ w: Double,_ h: Double) -> NSRect { NSRect(x: x, y: H - yTop - h, width: w, height: h) }
func fill(_ r: NSRect,_ c: NSColor){ c.setFill(); NSBezierPath(rect:r).fill() }
func gradient(_ r: NSRect,_ a: NSColor,_ b: NSColor){ NSGradient(colors:[a,b])?.draw(in: NSBezierPath(rect:r), angle:-90) }
func halftone(_ r: NSRect,_ sp: Double,_ rad: Double,_ c: NSColor){ c.setFill(); var y=r.minY; while y<r.maxY { var x=r.minX; while x<r.maxX { NSBezierPath(ovalIn: NSRect(x:x-rad,y:y-rad,width:rad*2,height:rad*2)).fill(); x+=sp }; y+=sp } }
func rounded(_ s: Double,_ w: NSFont.Weight = .black) -> NSFont {
    if let d = NSFont.systemFont(ofSize:s, weight:w).fontDescriptor.withDesign(.rounded) { return NSFont(descriptor:d,size:s) ?? NSFont.systemFont(ofSize:s,weight:w) }
    return NSFont.systemFont(ofSize:s, weight:w)
}
func attr(_ s: String,_ f: NSFont,_ c: NSColor) -> NSAttributedString {
    let ps = NSMutableParagraphStyle(); ps.alignment = .center
    return NSAttributedString(string:s, attributes:[.font:f,.foregroundColor:c,.paragraphStyle:ps])
}
// Title fitted to a max width (scales the font down if needed), centered at topY.
func fittedTitle(_ s: String, cx: Double, topY: Double, maxW: Double, base: Double,_ c: NSColor) {
    var size = base
    while size > 40 { if attr(s, rounded(size), c).size().width <= maxW { break }; size -= 8 }
    let a = attr(s, rounded(size), c); let sz = a.size()
    a.draw(at: NSPoint(x: cx - sz.width/2, y: H - topY - sz.height))
}
func textCentered(_ s: String, cx: Double, topY: Double,_ f: NSFont,_ c: NSColor) {
    let a = attr(s,f,c); let sz = a.size(); a.draw(at: NSPoint(x: cx - sz.width/2, y: H - topY - sz.height))
}

struct Cover { let title: String; let top: NSColor; let bottom: NSColor; let text: NSColor; let accent: NSColor }
func rgb(_ r: Double,_ g: Double,_ b: Double) -> NSColor { NSColor(srgbRed:r,green:g,blue:b,alpha:1) }

let covers = [
    Cover(title:"NIGHTFALL",     top:rgb(0.24,0.26,0.48), bottom:rgb(0.08,0.09,0.20), text:.white,           accent:rgb(0.99,0.80,0.20)),
    Cover(title:"THE LONG WALK", top:rgb(0.15,0.56,0.52), bottom:rgb(0.05,0.26,0.28), text:.white,           accent:rgb(0.99,0.88,0.35)),
    Cover(title:"STARDUST",      top:rgb(0.44,0.30,0.58), bottom:rgb(0.18,0.11,0.32), text:.white,           accent:rgb(0.99,0.80,0.20)),
    Cover(title:"RED KITE",      top:rgb(0.88,0.30,0.26), bottom:rgb(0.48,0.10,0.12), text:.white,           accent:rgb(0.99,0.90,0.40)),
    Cover(title:"QUIET SEA",     top:rgb(0.26,0.50,0.88), bottom:rgb(0.08,0.22,0.52), text:.white,           accent:rgb(0.99,0.88,0.35)),
    Cover(title:"PAPER MOON",    top:rgb(0.99,0.87,0.46), bottom:rgb(0.97,0.62,0.18), text:ink,              accent:ink),
]

for c in covers {
    let img = NSImage(size: NSSize(width:W,height:H)); img.lockFocus()
    gradient(rt(0,0,W,H), c.top, c.bottom)
    NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: rt(0,0,W,H)).addClip()
    halftone(rt(-40,-40,W+80,700), 46, 9, c.text.withAlphaComponent(0.10))
    NSGraphicsContext.restoreGraphicsState()
    // hero title block, vertically centred-ish
    fittedTitle(c.title, cx: W/2, topY: 1180, maxW: W-320, base: 240, c.text)
    fill(rt(W/2-260, 1500, 520, 10), c.accent)
    textCentered("GRAPHIC NOVEL", cx: W/2, topY: 1560, rounded(58,.heavy), c.text.withAlphaComponent(0.9))
    // footer strip
    fill(rt(0, H-210, W, 210), ink.withAlphaComponent(c.text == ink ? 0.9 : 1))
    textCentered("ISSUE #1", cx: W/2, topY: H-165, rounded(56,.heavy), c.accent == ink ? .white : c.accent)
    textCentered("Comic Reader", cx: W/2, topY: H-92, NSFont.systemFont(ofSize:40,weight:.medium), .white.withAlphaComponent(0.8))
    img.unlockFocus()
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using:.png, properties:[:]) {
        try? png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("\(c.title).png"))
        print("wrote \(c.title).png")
    }
}
print("done")
