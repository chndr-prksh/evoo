// Link-preview images for the website (LinkedIn, X, Slack, iMessage…):
//   swiftc -o /tmp/make-og scripts/make-og.swift && /tmp/make-og site
// → site/og.png (1200×627 card) and site/logo.png (512×512 app icon, also the touch icon).
import AppKit

func bitmap(_ w: Int, _ h: Int, _ draw: (CGFloat, CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(w), CGFloat(h))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// The app icon (same as scripts/make-icon.swift): five white bars on a dark rounded square.
func icon(in body: CGRect) {
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.27, alpha: 1),
                        NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)])!.draw(in: path, angle: -90)
    let unit = body.width / 32, bar = unit * 2.6
    NSColor.white.setFill()
    for (x, h) in zip([8, 12, 16, 20, 24] as [CGFloat], [6, 12, 16, 10, 4] as [CGFloat]) {
        let r = CGRect(x: body.minX + (x - 1.3) * unit, y: body.midY - h * unit / 2, width: bar, height: h * unit)
        NSBezierPath(roundedRect: r, xRadius: bar / 2, yRadius: bar / 2).fill()
    }
}

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, at p: CGPoint, kern: CGFloat = 0) {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                               .foregroundColor: color, .kern: kern]).draw(at: p)
}

let ink = NSColor(calibratedRed: 0.059, green: 0.067, blue: 0.082, alpha: 1) // #0f1115
let muted = NSColor(calibratedRed: 0.40, green: 0.42, blue: 0.46, alpha: 1)
let soft = NSColor(calibratedRed: 0.965, green: 0.969, blue: 0.976, alpha: 1) // #f6f7f9
let dir = URL(fileURLWithPath: CommandLine.arguments[1])

let card = bitmap(1200, 627) { w, h in
    NSColor.white.setFill(); CGRect(x: 0, y: 0, width: w, height: h).fill()
    // Soft panel on the right with a big icon; text on the left (kept inside LinkedIn's crop-safe area).
    let panel = NSBezierPath(roundedRect: CGRect(x: 760, y: 60, width: 380, height: 507), xRadius: 36, yRadius: 36)
    soft.setFill(); panel.fill()
    icon(in: CGRect(x: 830, y: 193, width: 240, height: 240))
    icon(in: CGRect(x: 80, y: 452, width: 64, height: 64))
    text("Evoo", 40, .bold, ink, at: CGPoint(x: 160, y: 461), kern: -0.5)
    text("Hold fn, speak, release.", 64, .bold, ink, at: CGPoint(x: 76, y: 300), kern: -1.6)
    text("Clean text at your cursor, in any app.", 34, .regular, muted, at: CGPoint(x: 80, y: 244))
    let pills = ["Free", "Open source", "100% on your Mac"]
    var x: CGFloat = 80
    for p in pills {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: ink]
        let size = NSAttributedString(string: p, attributes: attrs).size()
        let r = CGRect(x: x, y: 110, width: size.width + 40, height: 52)
        NSColor.white.setFill()
        let b = NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26); b.fill()
        NSColor(calibratedRed: 0.906, green: 0.910, blue: 0.925, alpha: 1).setStroke(); b.lineWidth = 2; b.stroke()
        NSAttributedString(string: p, attributes: attrs).draw(at: CGPoint(x: x + 20, y: 110 + (52 - size.height) / 2))
        x += r.width + 14
    }
}
try! card.write(to: dir.appendingPathComponent("og.png"))
try! bitmap(512, 512) { w, _ in icon(in: CGRect(x: 0, y: 0, width: w, height: w)) }.write(to: dir.appendingPathComponent("logo.png"))
print("wrote og.png and logo.png")
