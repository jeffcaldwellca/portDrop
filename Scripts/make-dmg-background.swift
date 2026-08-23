import AppKit
// Usage: swift make-dmg-background.swift <out.png> <width> <height> <scale>
// Draws the DMG window background: soft gradient, title, and an arrow from the app slot to the Applications slot.
let out = CommandLine.arguments[1]
let w = Double(CommandLine.arguments[2])!, h = Double(CommandLine.arguments[3])!, scale = Double(CommandLine.arguments[4])!
let size = NSSize(width: w * scale, height: h * scale)
let img = NSImage(size: size)
img.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
let ctx = NSGraphicsContext.current!.cgContext
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
text("PortDrop", NSFont.systemFont(ofSize: 30, weight: .bold), NSColor(calibratedWhite: 0.12, alpha: 1), y: h - 74)
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

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
rep.size = NSSize(width: w, height: h)   // keep point size so Finder shows it at the right scale
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
