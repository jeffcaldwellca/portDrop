import AppKit
import Darwin

struct ProcessPresentation: Sendable {
    let displayName: String
    let icon: NSImage
    let bundlePath: String?
    let executablePath: String?
}

@MainActor
final class ProcessInfoResolver {
    private var cache: [pid_t: ProcessPresentation] = [:]

    func presentation(for port: ListeningPort, kind: ServiceKind) -> ProcessPresentation {
        if let cached = cache[port.pid] { return cached }
        let p = resolve(port, kind: kind)
        cache[port.pid] = p
        return p
    }

    func evict(pidsNotIn live: Set<pid_t>) {
        cache = cache.filter { live.contains($0.key) }
    }

    private func resolve(_ port: ListeningPort, kind: ServiceKind) -> ProcessPresentation {
        let exe = executablePath(pid: port.pid)
        let bundle = exe.flatMap(bundlePath(containing:))

        if let app = NSRunningApplication(processIdentifier: port.pid), let icon = app.icon {
            return ProcessPresentation(displayName: app.localizedName ?? port.processName,
                                       icon: icon, bundlePath: app.bundleURL?.path, executablePath: exe)
        }
        if let bundle {
            let icon = NSWorkspace.shared.icon(forFile: bundle)
            let name = Bundle(path: bundle).flatMap { b in
                (b.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? b.object(forInfoDictionaryKey: "CFBundleName")) as? String
            } ?? port.processName
            return ProcessPresentation(displayName: name, icon: icon, bundlePath: bundle, executablePath: exe)
        }
        let symbol = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.label)
            ?? NSImage(systemSymbolName: "network", accessibilityDescription: nil)!
        return ProcessPresentation(displayName: port.processName, icon: symbol, bundlePath: nil, executablePath: exe)
    }

    private func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(len)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private func bundlePath(containing path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        while url.path != "/" {
            if url.pathExtension == "app" { return url.path }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
