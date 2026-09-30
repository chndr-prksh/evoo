// Draws Evoo's app icon at every size macOS needs:
//   swiftc -o /tmp/make-icon scripts/make-icon.swift && /tmp/make-icon /tmp/AppIcon.iconset
//   iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit
// Evoo app icon: the site's logo (five waveform bars) on a dark macOS-style rounded square.
func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: 824/1024 body with room for the shadow.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset * 1.1, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.225
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.27, alpha: 1),
                        NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)])!.draw(in: path, angle: -90)
    NSShadow().set()
    NSColor.white.withAlphaComponent(0.08).setStroke()
    path.lineWidth = max(1, s / 512)
    path.stroke()
    // Five bars, like the logo: heights 6,12,16,10,4 on a 32-unit grid centred at 16.
    let unit = body.width / 32
    let heights: [CGFloat] = [6, 12, 16, 10, 4]
    let xs: [CGFloat] = [8, 12, 16, 20, 24]
    let bar = unit * 2.6
    NSColor.white.setFill()
    for (x, h) in zip(xs, heights) {
        let r = CGRect(x: body.minX + (x - 0.5 * 2.6) * unit, y: body.midY - h * unit / 2, width: bar, height: h * unit)
        NSBezierPath(roundedRect: r, xRadius: bar / 2, yRadius: bar / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! draw(1024).write(to: dir.deletingLastPathComponent().appendingPathComponent("preview.png"))
