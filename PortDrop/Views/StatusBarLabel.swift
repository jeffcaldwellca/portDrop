import AppKit
import SwiftUI

/// Renders the menu-bar label (icon + count) as a single template image so the glyph and digits share one baseline.
/// Images are cached per count so polling doesn't re-rasterise an identical label.
@MainActor
enum StatusBarLabel {
    private static var cache: [Int: NSImage] = [:]

    static func image(count: Int) -> NSImage? {
        if let cached = cache[count] { return cached }
        let view = HStack(alignment: .center, spacing: 3) {
            Image(systemName: "network")
                .font(.system(size: 14, weight: .medium))
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.black)
        .frame(height: 18)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityLabel(count: count)
        cache[count] = image
        return image
    }

    static func accessibilityLabel(count: Int) -> String {
        "PortDrop, \(count) listening \(count == 1 ? "port" : "ports")"
    }
}
