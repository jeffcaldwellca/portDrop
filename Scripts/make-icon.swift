import AppKit
// Generates AppIcon PNGs: rounded squircle gradient with a network glyph.
let sizes: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
let dir = CommandLine.arguments[1]
for (pt, scale) in sizes {
    let px = pt * scale
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let r = NSRect(x: 0, y: 0, width: px, height: px).insetBy(dx: CGFloat(px) * 0.05, dy: CGFloat(px) * 0.05)
    let path = NSBezierPath(roundedRect: r, xRadius: r.width * 0.22, yRadius: r.width * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.95, alpha: 1), NSColor(calibratedRed: 0.45, green: 0.2, blue: 0.85, alpha: 1)])!
        .draw(in: path, angle: -60)
    let cfg = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.55, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "network", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size, flipped: false) { rect in
            sym.draw(in: rect); NSColor.white.set(); rect.fill(using: .sourceAtop); return true }
        let s = tinted.size
        tinted.draw(in: NSRect(x: (CGFloat(px) - s.width)/2, y: (CGFloat(px) - s.height)/2, width: s.width, height: s.height))
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/icon_\(pt)x\(pt)@\(scale)x.png"))
}
