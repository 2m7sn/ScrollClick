import AppKit

// Renders a simple keycap icon into an .iconset folder.
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // base (keycap side)
    let base = NSBezierPath(roundedRect: NSRect(x: s*0.1, y: s*0.1, width: s*0.8, height: s*0.8),
                            xRadius: s*0.18, yRadius: s*0.18)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.22, alpha: 1),
               ending: NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.38, alpha: 1))!.draw(in: base, angle: 90)
    // top (keycap face)
    let top = NSBezierPath(roundedRect: NSRect(x: s*0.19, y: s*0.24, width: s*0.62, height: s*0.58),
                           xRadius: s*0.12, yRadius: s*0.12)
    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.62, blue: 0.95, alpha: 1),
               ending: NSColor(calibratedRed: 0.45, green: 0.82, blue: 1.0, alpha: 1))!.draw(in: top, angle: 90)
    // legend
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let font = NSFont.systemFont(ofSize: s*0.30, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.12, alpha: 1),
                                                .paragraphStyle: para]
    ("↕" as NSString).draw(in: NSRect(x: s*0.19, y: s*0.33, width: s*0.62, height: s*0.40), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
