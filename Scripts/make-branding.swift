import AppKit

// Regenerates every branding asset from the single source artwork in Branding/PortDropIcon.png.
// Usage: swift Scripts/make-branding.swift [source.png] [Assets.xcassets]
//   AppIcon.appiconset   — white glyph on the blue→purple brand squircle, all 10 macOS sizes
//   MenuBarIcon.imageset — the bare glyph as a template image at menu-bar size

let source = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Branding/PortDropIcon.png"
let assets = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "PortDrop/Resources/Assets.xcassets"

let brandBlue = NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.95, alpha: 1)
let brandPurple = NSColor(calibratedRed: 0.45, green: 0.20, blue: 0.85, alpha: 1)

/// The artwork sits on a transparent canvas with uneven margins, so crop to the ink before laying it out.
func trimmedArtwork(_ path: String) -> NSImage {
    guard let image = NSImage(contentsOfFile: path),
          let data = image.tiffRepresentation, let rep = NSBitmapImageRep(data: data) else {
        fatalError("Cannot read artwork at \(path)")
    }
    var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = 0, maxY = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide where rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.02 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { fatalError("Artwork at \(path) is fully transparent") }
    let size = NSSize(width: maxX - minX + 1, height: maxY - minY + 1)
    let out = NSImage(size: size)
    out.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    // NSImage draws bottom-up; the scan above is top-down, so flip the source rect's origin.
    image.draw(in: NSRect(origin: .zero, size: size),
               from: NSRect(x: CGFloat(minX), y: CGFloat(rep.pixelsHigh - maxY - 1), width: size.width, height: size.height),
               operation: .copy, fraction: 1)
    out.unlockFocus()
    return out
}

let glyph = trimmedArtwork(source)

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    NSImage(size: image.size, flipped: false) { rect in
        image.draw(in: rect); color.set(); rect.fill(using: .sourceAtop); return true
    }
}

func writePNG(_ image: NSImage, pointSize: NSSize, to path: String) {
    guard let rep = NSBitmapImageRep(data: image.tiffRepresentation!) else { fatalError("render failed") }
    rep.size = pointSize
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// Draws the glyph centred and aspect-fit inside a square of `side` points, occupying `fraction` of it.
func drawGlyph(color: NSColor, in side: CGFloat, fraction: CGFloat) {
    let target = side * fraction
    let scale = min(target / glyph.size.width, target / glyph.size.height)
    let size = NSSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
    tinted(glyph, color).draw(in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                         width: size.width, height: size.height))
}

// MARK: - AppIcon

let iconDir = "\(assets)/AppIcon.appiconset"
for (point, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let px = CGFloat(point * scale)
    let image = NSImage(size: NSSize(width: px, height: px))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    // Apple's macOS grid: the squircle body is 824/1024 of the canvas, cornered at ~22.4% of the body.
    let inset = px * 0.098
    let body = NSRect(x: inset, y: inset, width: px - inset * 2, height: px - inset * 2)
    let squircle = NSBezierPath(roundedRect: body, xRadius: body.width * 0.2237, yRadius: body.width * 0.2237)
    NSGradient(colors: [brandBlue, brandPurple])!.draw(in: squircle, angle: -60)
    // The line art loses its strokes below 32 px, so let it take more of the tile at those sizes.
    let glyphShare = px <= 32 ? 0.82 : 0.70
    drawGlyph(color: .white, in: px, fraction: body.width / px * glyphShare)
    image.unlockFocus()
    writePNG(image, pointSize: NSSize(width: px, height: px), to: "\(iconDir)/icon_\(point)x\(point)@\(scale)x.png")
}
print("✓ AppIcon (10 sizes) → \(iconDir)")

// MARK: - MenuBarIcon

// 16 pt tall is the largest the glyph reads cleanly at in the menu bar; width follows the artwork's aspect.
let menuBarHeight: CGFloat = 16
let menuBarWidth = (menuBarHeight * glyph.size.width / glyph.size.height).rounded()
let menuBarDir = "\(assets)/MenuBarIcon.imageset"
try? FileManager.default.createDirectory(atPath: menuBarDir, withIntermediateDirectories: true)
for scale in 1...2 {   // macOS asset catalogs have no 3x idiom
    let px = NSSize(width: menuBarWidth * CGFloat(scale), height: menuBarHeight * CGFloat(scale))
    let image = NSImage(size: px)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    // Template images are masked by alpha, but a flat black fill keeps the source's own ink out of the mask.
    tinted(glyph, .black).draw(in: NSRect(origin: .zero, size: px))
    image.unlockFocus()
    writePNG(image, pointSize: px, to: "\(menuBarDir)/menubar@\(scale)x.png")
}
let contents = """
{
  "images": [
    { "idiom": "mac", "scale": "1x", "filename": "menubar@1x.png" },
    { "idiom": "mac", "scale": "2x", "filename": "menubar@2x.png" }
  ],
  "info": { "author": "xcode", "version": 1 },
  "properties": { "template-rendering-intent": "template" }
}

"""
try! contents.write(toFile: "\(menuBarDir)/Contents.json", atomically: true, encoding: .utf8)
print("✓ MenuBarIcon (\(Int(menuBarWidth))×\(Int(menuBarHeight)) pt, 1–2x) → \(menuBarDir)")
