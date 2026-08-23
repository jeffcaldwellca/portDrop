import AppKit
import SwiftUI

struct PortRowView: View {
    let port: ListeningPort
    let service: ServiceInfo
    let presentation: ProcessPresentation
    let onKill: (_ force: Bool) async throws -> Void

    /// Wide enough for "65535" in bold monospaced body text.
    static let portColumnWidth: CGFloat = 52
    /// Wide enough for the idle icon; the Confirm pill may grow past this rather than clip.
    static let killColumnWidth: CGFloat = 28
    /// Lower bound for the list frame before the first geometry pass reports.
    static let minRowHeight: CGFloat = 56

    private enum KillState: Equatable {
        case idle, confirming, killing, failed(String)
    }

    @State private var killState: KillState = .idle
    @State private var revertTask: Task<Void, Never>?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: presentation.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .foregroundStyle(service.kind.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    KindChip(kind: service.kind)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if case .failed(let msg) = killState {
                    Text(msg).font(.caption2).foregroundStyle(.red).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(port.port))
                .font(.system(.body, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .fixedSize()
                .frame(minWidth: Self.portColumnWidth, alignment: .trailing)

            HStack(spacing: 6) {
                // Always laid out so the kill column lines up; invisible + inert when there is no URL.
                Button { if let url = service.url { NSWorkspace.shared.open(url) } } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.accessoryBar)
                .accessibilityLabel("Open")
                .help(service.url.map { "Open \($0.absoluteString)" } ?? "")
                .opacity(service.url == nil ? 0 : 1)
                .disabled(service.url == nil)
                .accessibilityHidden(service.url == nil)

                killButton
                    .frame(minWidth: Self.killColumnWidth, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovering ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .onHover { isHovering = $0 }
        .help(bindDescription)
        .contextMenu { contextMenu }
        .opacity(killState == .killing ? 0.4 : 1)
    }

    private var subtitle: String {
        "\(port.user) · PID \(port.pid)"
    }

    private var bindDescription: String {
        let addr = port.bindAddress == "*" ? "all interfaces" : port.bindAddress
        let versions = port.ipVersions.contains(.v4) && port.ipVersions.contains(.v6) ? "IPv4 + IPv6" : (port.ipVersions.contains(.v6) ? "IPv6" : "IPv4")
        return "\(presentation.executablePath ?? port.processName)\nListening on \(addr) (\(versions))"
    }

    @ViewBuilder private var killButton: some View {
        switch killState {
        case .idle, .failed:
            Button { beginConfirm() } label: {
                Image(systemName: "xmark.octagon")
            }
            .buttonStyle(.accessoryBar)
            .accessibilityLabel("Kill")
            .help("Kill process (click again to confirm, ⌥ for force kill)")
        case .confirming:
            Button { performKill(force: NSEvent.modifierFlags.contains(.option)) } label: {
                Text("Confirm").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
            .accessibilityLabel("Confirm kill")
        case .killing:
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder private var contextMenu: some View {
        if let url = service.url {
            Button("Open \(url.absoluteString)") { NSWorkspace.shared.open(url) }
            Button("Copy URL") { copy(url.absoluteString) }
        }
        Button("Copy PID") { copy(String(port.pid)) }
        Button("Copy host:port") { copy("\(ServiceClassifier.host(for: port.bindAddress)):\(port.port)") }
        if let path = presentation.bundlePath ?? presentation.executablePath {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
        }
        Divider()
        Button("Kill (SIGTERM)") { performKill(force: false) }
        Button("Force Kill (SIGKILL)") { performKill(force: true) }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func beginConfirm() {
        withAnimation(.snappy) { killState = .confirming }
        revertTask?.cancel()
        revertTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { if killState == .confirming { killState = .idle } }
        }
    }

    private func performKill(force: Bool) {
        revertTask?.cancel()
        withAnimation(.snappy) { killState = .killing }
        Task {
            do {
                try await onKill(force)
                killState = .idle
            } catch KillError.cancelled {
                withAnimation(.snappy) { killState = .idle }
            } catch {
                withAnimation(.snappy) { killState = .failed(error.localizedDescription) }
                try? await Task.sleep(for: .seconds(4))
                if case .failed = killState { withAnimation(.snappy) { killState = .idle } }
            }
        }
    }
}
