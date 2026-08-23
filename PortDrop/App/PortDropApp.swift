import AppKit
import SwiftUI

@main
struct PortDropApp: App {
    @State private var monitor = PortMonitor()

    init() {
        if let path = ProcessInfo.processInfo.environment["PORTDROP_SNAPSHOT"] {
            Task { @MainActor in
                let m = PortMonitor(autoStart: false)
                await m.refresh()
                let host = NSHostingView(rootView: PanelView(monitor: m))
                host.frame = NSRect(x: 0, y: 0, width: 380, height: host.fittingSize.height)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                window.appearance = NSAppearance(named: .aqua)
                window.backgroundColor = .windowBackgroundColor
                window.orderFrontRegardless()
                try? await Task.sleep(for: .seconds(2))
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
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
            HStack(spacing: 3) {
                Image(systemName: "network")
                Text("\(monitor.ports.count)")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
