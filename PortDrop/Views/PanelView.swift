import SwiftUI

struct PanelView: View {
    @Bindable var monitor: PortMonitor
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
        }
        .frame(width: 420)
        .onAppear {
            monitor.isPanelVisible = true
            NSApp.activate()   // MenuBarExtra windows don't become key otherwise, so TextField edits never commit
        }
        .onDisappear { monitor.isPanelVisible = false }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Ports")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(monitor.ports.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .glassEffect(.regular, in: Capsule())
                Button { Task { await monitor.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(monitor.isScanning ? 360 : 0))
                        .animation(monitor.isScanning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: monitor.isScanning)
                }
                .buttonStyle(.accessoryBar)
                .help("Refresh now")
                Menu {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.isEnabled = v }
                    Toggle("Notify on new ports", isOn: Binding(
                        get: { monitor.notifyOnNewPorts }, set: { monitor.notifyOnNewPorts = $0 }))
                    Divider()
                    Button("About PortDrop") { showAbout() }
                    Button("Quit PortDrop") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.button)
                .buttonStyle(.accessoryBar)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            TextField("Search port, process, user…", text: $monitor.searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let credits = NSAttributedString(
            string: "Shows every process listening on a local TCP port, opens the service, and kills it on demand.",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "PortDrop",
            .applicationVersion: version,
            .version: build,
            .credits: credits,
        ])
    }

    private static let rowHeight: CGFloat = 56
    private static let maxListHeight: CGFloat = 480

    /// MenuBarExtra windows size to their content's ideal height; a ScrollView has none, so derive it from the row count.
    private var listHeight: CGFloat {
        min(CGFloat(monitor.filteredPorts.count) * Self.rowHeight + 12, Self.maxListHeight)
    }

    @ViewBuilder private var content: some View {
        if let err = monitor.lastError {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 14).padding(.vertical, 8)
        }
        if monitor.filteredPorts.isEmpty {
            ContentUnavailableView(
                monitor.searchText.isEmpty ? "No listening services" : "No matches",
                systemImage: monitor.searchText.isEmpty ? "network.slash" : "magnifyingglass",
                description: Text(monitor.searchText.isEmpty ? "Nothing is listening on a TCP port right now." : "Try a different port or process name.")
            )
            .frame(height: 200)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(monitor.filteredPorts) { port in
                        let service = monitor.service(for: port)
                        PortRowView(
                            port: port,
                            service: service,
                            presentation: monitor.resolver.presentation(for: port, kind: service.kind),
                            onKill: { force in try await monitor.kill(port, force: force) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(6)
                .animation(.snappy, value: monitor.filteredPorts)
            }
            .frame(height: listHeight)
        }
    }
}
