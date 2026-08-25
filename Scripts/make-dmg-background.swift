import AppKit
// Usage: swift make-dmg-background.swift <out.png> <width> <height> <scale> [glyph.png]
// Draws the DMG window background: soft gradient, the PortDrop mark beside the title, and an arrow
// from the app slot to the Applications slot.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
let args = CommandLine.arguments
guard args.count >= 5, let w = Double(args[2]), let h = Double(args[3]), let scale = Double(args[4]) else {
    fail("usage: make-dmg-background <out.png> <width> <height> <scale> [glyph.png]")
}
let out = args[1]
let glyphPath = args.count > 5 ? args[5] : "Branding/PortDropIcon.png"

// Draw into an explicit bitmap context rather than NSImage.lockFocus(), which needs a window-server
// session and returns no current context on a headless CI runner.
guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let gc = NSGraphicsContext(bitmapImageRep: rep) else {
    fail("could not create a \(Int(w * scale))×\(Int(h * scale)) drawing context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gc
gc.imageInterpolation = .high
let ctx = gc.cgContext
ctx.scaleBy(x: scale, y: scale)

// Background: light, airy gradient with a faint brand glow in the top-left.
NSGradient(colors: [NSColor(calibratedWhite: 0.985, alpha: 1), NSColor(calibratedWhite: 0.94, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
let cs = CGColorSpaceCreateDeviceRGB()
let glowColors = [NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.95, alpha: 0.22).cgColor,
                  NSColor(calibratedRed: 0.45, green: 0.2, blue: 0.85, alpha: 0.06).cgColor,
                  NSColor(calibratedRed: 0.45, green: 0.2, blue: 0.85, alpha: 0.0).cgColor] as CFArray
let glow = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0, 0.55, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 110, y: h - 20), startRadius: 0,
                       endCenter: CGPoint(x: 110, y: h - 20), endRadius: 420, options: [])

// Title + hint
let para = NSMutableParagraphStyle(); para.alignment = .center
func text(_ s: String, _ font: NSFont, _ color: NSColor, y: Double) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
    NSString(string: s).draw(in: NSRect(x: 0, y: y, width: w, height: font.pointSize * 1.4), withAttributes: attrs)
}
// Mark + wordmark are laid out as one lockup: sized and centred against the wordmark's cap band,
// so they read as a single unit instead of two independently centred elements.
let ink = NSColor(calibratedWhite: 0.12, alpha: 1)
let titleFont = NSFont.systemFont(ofSize: 30, weight: .bold)
let titleRect = NSRect(x: 0, y: h - 74, width: w, height: titleFont.pointSize * 1.4)
let titleWidth = NSString(string: "PortDrop").size(withAttributes: [.font: titleFont]).width
let markSize = titleFont.capHeight * 1.7, markGap = 12.0
let lockupX = (w - (markSize + markGap + titleWidth)) / 2

if let glyph = NSImage(contentsOfFile: glyphPath) {
    let tintedGlyph = NSImage(size: glyph.size, flipped: false) { r in
        glyph.draw(in: r); ink.set(); r.fill(using: .sourceAtop); return true }
    let k = min(markSize / glyph.size.width, markSize / glyph.size.height)
    let mw = glyph.size.width * k, mh = glyph.size.height * k
    // NSString draws its first line with the top of the rect at the ascender, so derive the cap band from there.
    let baseline = titleRect.maxY - titleFont.ascender
    let capCentre = baseline + titleFont.capHeight / 2
    tintedGlyph.draw(in: NSRect(x: lockupX + (markSize - mw) / 2, y: capCentre - mh / 2, width: mw, height: mh))
}
let leftAligned = NSMutableParagraphStyle(); leftAligned.alignment = .left
NSString(string: "PortDrop").draw(
    in: NSRect(x: lockupX + markSize + markGap, y: titleRect.minY, width: titleWidth + 4, height: titleRect.height),
    withAttributes: [.font: titleFont, .foregroundColor: ink, .paragraphStyle: leftAligned])
text("Drag to Applications to install", NSFont.systemFont(ofSize: 14, weight: .medium), NSColor(calibratedWhite: 0.45, alpha: 1), y: h - 100)

// Arrow between the two icon slots (icons are centred at x = w*0.28 and x = w*0.72, y = h*0.47)
let y = h * 0.47, x0 = w * 0.28 + 84, x1 = w * 0.72 - 84
let arrow = NSBezierPath()
arrow.lineWidth = 5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: x0, y: y)); arrow.line(to: NSPoint(x: x1 - 6, y: y))
arrow.move(to: NSPoint(x: x1 - 24, y: y + 16)); arrow.line(to: NSPoint(x: x1, y: y)); arrow.line(to: NSPoint(x: x1 - 24, y: y - 16))
NSColor(calibratedRed: 0.3, green: 0.35, blue: 0.9, alpha: 0.55).setStroke()
arrow.stroke()

// Footer
text("© Jeffrey Caldwell", NSFont.systemFont(ofSize: 11, weight: .regular), NSColor(calibratedWhite: 0.6, alpha: 1), y: 18)

NSGraphicsContext.restoreGraphicsState()
rep.size = NSSize(width: w, height: h)   // keep point size so Finder shows it at the right scale
guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not encode PNG") }
do { try png.write(to: URL(fileURLWithPath: out)) } catch { fail("could not write \(out): \(error)") }
