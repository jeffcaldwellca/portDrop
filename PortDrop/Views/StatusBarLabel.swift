import AppKit
import SwiftUI

/// Renders the menu-bar label (icon + count) as a single template image so the glyph and digits share one baseline.
enum StatusBarLabel {
    @MainActor
    static func image(count: Int) -> NSImage {
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
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "network", accessibilityDescription: nil)!
        image.isTemplate = true
        return image
    }
}
