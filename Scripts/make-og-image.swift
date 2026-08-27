import AppKit
// Usage: make-og-image <out.png>   (run from the repo root; compile with swiftc like make-dmg.sh does)
// Renders the website's Open Graph / Twitter card at 1200×630: brand glow on a dark ground, app icon,
// wordmark and tagline on the left, the light panel screenshot on the right.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: make-og-image <out.png>") }
let out = args[1]
let w = 1200.0, h = 630.0
let iconPath = "PortDrop/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@1x.png"
let shotPath = "docs/screenshots/panel-light.png"
guard let icon = NSImage(contentsOfFile: iconPath) else { fail("missing \(iconPath)") }
guard let shot = NSImage(contentsOfFile: shotPath) else { fail("missing \(shotPath)") }

guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let gc = NSGraphicsContext(bitmapImageRep: rep) else {
    fail("could not create a \(Int(w))×\(Int(h)) drawing context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gc
gc.imageInterpolation = .high
let ctx = gc.cgContext

// Ground + brand glow (same blue/purple as make-branding.swift).
NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: w, height: h).fill()
let blue = NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.95, alpha: 1)
let purple = NSColor(calibratedRed: 0.45, green: 0.20, blue: 0.85, alpha: 1)
let cs = CGColorSpaceCreateDeviceRGB()
let glow = CGGradient(colorsSpace: cs,
                      colors: [blue.withAlphaComponent(0.55).cgColor,
                               purple.withAlphaComponent(0.28).cgColor,
                               purple.withAlphaComponent(0).cgColor] as CFArray,
                      locations: [0, 0.5, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 140, y: h - 60), startRadius: 0,
                       endCenter: CGPoint(x: 140, y: h - 60), endRadius: 760, options: [])

// Left column: icon, wordmark, tagline, facts line.
let left = 84.0
icon.draw(in: NSRect(x: left, y: h - 84 - 168, width: 168, height: 168))
let wordmark = NSFont.systemFont(ofSize: 92, weight: .bold)
NSString(string: "PortDrop").draw(at: NSPoint(x: left - 5, y: h - 84 - 168 - 122),
                                  withAttributes: [.font: wordmark, .foregroundColor: NSColor.white])
let para = NSMutableParagraphStyle(); para.lineSpacing = 6
NSString(string: "See every process listening on a local port.\nOpen it in one click, kill it in two.")
    .draw(in: NSRect(x: left, y: 118, width: 600, height: 110),
          withAttributes: [.font: NSFont.systemFont(ofSize: 31, weight: .medium),
                           .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1), .paragraphStyle: para])
NSString(string: "Free  ·  macOS 26+  ·  Homebrew or DMG").draw(
    at: NSPoint(x: left, y: 62),
    withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .regular),
                     .foregroundColor: NSColor(calibratedWhite: 0.66, alpha: 1)])

// Right: the panel screenshot (its PNG already has rounded transparent corners), with a soft shadow,
// top-aligned and bleeding slightly off the bottom edge.
let shotW = 440.0
let shotH = shotW * shot.size.height / shot.size.width
let shotRect = NSRect(x: w - shotW - 84, y: h - 56 - shotH, width: shotW, height: shotH)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 44,
              color: NSColor.black.withAlphaComponent(0.6).cgColor)
shot.draw(in: shotRect)
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not encode PNG") }
do { try png.write(to: URL(fileURLWithPath: out)) } catch { fail("could not write \(out): \(error)") }
