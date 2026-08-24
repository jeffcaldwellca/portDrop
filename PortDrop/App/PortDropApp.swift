import AppKit
import SwiftUI

@main
struct PortDropApp: App {
    @State private var monitor = PortMonitor()

    init() {
        // Debug/README hook: render the panel to a PNG and exit.
        //   PORTDROP_SNAPSHOT=/path/out.png            required
        //   PORTDROP_SNAPSHOT_APPEARANCE=light|dark    default light
        //   PORTDROP_SNAPSHOT_SCALE=1|2|3              default: the screen's backing scale
        let env = ProcessInfo.processInfo.environment
        if let path = env["PORTDROP_SNAPSHOT"] {
            Task { @MainActor in
                let m = PortMonitor(autoStart: false)
                await m.refresh()
                // cacheDisplay only draws the view tree, so the panel paints its own window background
                // (and menu-bar-window corners) to keep the PNG self-contained in both appearances.
                let host = NSHostingView(rootView: PanelView(monitor: m)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                window.appearance = NSAppearance(named: env["PORTDROP_SNAPSHOT_APPEARANCE"] == "dark" ? .darkAqua : .aqua)
                window.backgroundColor = .clear
                window.isOpaque = false
                window.orderFrontRegardless()
                try? await Task.sleep(for: .seconds(2))
                host.layoutSubtreeIfNeeded()
                let scale = env["PORTDROP_SNAPSHOT_SCALE"].flatMap { Double($0) }.map { CGFloat($0) } ?? window.backingScaleFactor
                let bounds = host.bounds
                if let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                    rep.size = bounds.size   // point size < pixel size ⇒ cacheDisplay renders at `scale`
                    host.cacheDisplay(in: bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                    }
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(monitor: monitor)
        } label: {
            let count = monitor.ports.count
            if let image = StatusBarLabel.image(count: count) {
                Image(nsImage: image)
                    .accessibilityLabel(StatusBarLabel.accessibilityLabel(count: count))
            } else {
                // Fallback keeps the count visible even if offscreen rendering is unavailable.
                HStack(alignment: .center, spacing: 3) {
                    Image(.menuBarIcon).renderingMode(.template)
                    Text("\(count)").monospacedDigit()
                }
                .accessibilityLabel(StatusBarLabel.accessibilityLabel(count: count))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
