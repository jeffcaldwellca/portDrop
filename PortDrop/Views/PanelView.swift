import SwiftUI

struct PanelView: View {
    @Bindable var monitor: PortMonitor
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @ObservedObject private var updater = Updater.shared
    @State private var listContentHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @State private var selectedID: String?
    @State private var openRequest = 0
    @State private var killRequest = 0

    static let width: CGFloat = 420
    static let maxListHeight: CGFloat = 480

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
        }
        .frame(width: Self.width)
        .onAppear {
            monitor.isPanelVisible = true
            NSApp.activate()   // MenuBarExtra windows don't become key otherwise, so TextField edits never commit
            searchFocused = true
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
                        .onChange(of: launchAtLogin) { _, v in
                            guard v != LaunchAtLogin.isEnabled else { return }
                            LaunchAtLogin.isEnabled = v
                            launchAtLogin = LaunchAtLogin.isEnabled   // snaps back if macOS refused
                        }
                    Toggle("Notify on new ports", isOn: Binding(
                        get: { monitor.notifyOnNewPorts }, set: { monitor.notifyOnNewPorts = $0 }))
                    Toggle("Show system ports", isOn: $monitor.showSystemPorts)
                        .onChange(of: monitor.showSystemPorts) { Task { await monitor.refresh() } }
                    if !monitor.hiddenProcessNames.isEmpty {
                        Menu("Hidden Processes (\(monitor.hiddenProcessNames.count))") {
                            ForEach(monitor.hiddenProcessNames.sorted(), id: \.self) { name in
                                Button("Show \(name)") { monitor.unhide(name); Task { await monitor.refresh() } }
                            }
                            Divider()
                            Button("Show All") { monitor.unhideAll(); Task { await monitor.refresh() } }
                        }
                    }
                    Divider()
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Toggle("Check for Updates Automatically", isOn: $updater.automaticallyChecksForUpdates)
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
            TextField("Search port, process, folder…", text: $monitor.searchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .help("↑ ↓ to select a row, ⏎ to open it, ⌘⌫ twice to kill it, esc to clear")
                .onChange(of: monitor.searchText) { selectedID = nil }
                .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
                .onKeyPress(.return) {
                    guard selectedID != nil else { return .ignored }
                    openRequest += 1
                    return .handled
                }
                .onKeyPress(.escape) {
                    if selectedID != nil { selectedID = nil } else if !monitor.searchText.isEmpty { monitor.searchText = "" } else { return .ignored }
                    return .handled
                }
                .onKeyPress(keys: [.delete]) { press in
                    // Plain ⌘⌫ still edits the search text until a row has been picked with the arrows.
                    guard press.modifiers.contains(.command), selectedID != nil else { return .ignored }
                    killRequest += 1
                    return .handled
                }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func moveSelection(by delta: Int) {
        selectedID = Self.nextSelection(current: selectedID, by: delta, in: monitor.filteredPorts.map(\.id))
    }

    /// With nothing selected (or the selected row gone) ↓ starts at the top and ↑ at the bottom; otherwise the move clamps.
    nonisolated static func nextSelection(current: String?, by delta: Int, in ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let i = ids.firstIndex(of: current) else { return delta > 0 ? ids.first : ids.last }
        return ids[min(max(i + delta, 0), ids.count - 1)]
    }

    private func showAbout() {
        let credits = NSAttributedString(
            string: "Shows every process listening on a local TCP port, opens the service, and kills it on demand.",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.activate()
        // Name and version come from Info.plist; only the credits are overridden.
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        // An LSUIElement app has no Dock tile or Window menu to recover a buried window, so keep About on top.
        for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
            window.level = .floating
        }
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
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(monitor.filteredPorts) { port in
                        let service = monitor.service(for: port)
                        let docker = monitor.dockerBinding(for: port)
                        PortRowView(
                            port: port,
                            service: service,
                            presentation: monitor.resolver.presentation(for: port, kind: service.kind),
                            onKill: { force in try await monitor.kill(port, force: force) },
                            docker: docker,
                            onDocker: { action in try await monitor.perform(action) },
                            projectContainerCount: docker?.container.project.map(monitor.projectContainerCount) ?? 0,
                            isSelected: selectedID == port.id,
                            openRequest: openRequest,
                            killRequest: killRequest,
                            onHide: { monitor.hide(port.processName) }
                        )
                        .id(port.id)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(6)
                .animation(.snappy, value: monitor.filteredPorts)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listContentHeight = $0 }
            }
            .frame(height: min(max(listContentHeight, PortRowView.minRowHeight), Self.maxListHeight))
            .onChange(of: selectedID) { _, id in if let id { proxy.scrollTo(id) } }
            }
        }
    }
}
