import AppKit
import Darwin

struct ProcessPresentation: Sendable {
    let displayName: String
    let icon: NSImage
    let bundlePath: String?
    let executablePath: String?
    /// Where the process was started; for a dev server that is the project it belongs to.
    let workingDirectory: String?
    let commandLine: String?

    var projectName: String? { Self.projectName(workingDirectory: workingDirectory, home: NSHomeDirectory()) }

    /// The folder name, unless the directory says nothing about a project (`/` and the home folder).
    static func projectName(workingDirectory: String?, home: String) -> String? {
        guard let workingDirectory, workingDirectory != "/", workingDirectory != home else { return nil }
        return (workingDirectory as NSString).lastPathComponent
    }
}

@MainActor
final class ProcessInfoResolver {
    /// What is known about a pid. `icon` is nil when the process has no app icon; the row then gets its
    /// kind's symbol, which is chosen per call because a probe can change the kind after the first lookup.
    private struct Resolved {
        let displayName: String
        let icon: NSImage?
        let bundlePath: String?
        let executablePath: String?
        let workingDirectory: String?
        let commandLine: String?
    }

    private var cache: [pid_t: Resolved] = [:]
    private var symbols: [ServiceKind: NSImage] = [:]

    func presentation(for port: ListeningPort, kind: ServiceKind) -> ProcessPresentation {
        let r = cache[port.pid] ?? resolve(port)
        cache[port.pid] = r
        return ProcessPresentation(displayName: r.displayName, icon: r.icon ?? symbol(for: kind),
                                   bundlePath: r.bundlePath, executablePath: r.executablePath,
                                   workingDirectory: r.workingDirectory, commandLine: r.commandLine)
    }

    func evict(pidsNotIn live: Set<pid_t>) {
        cache = cache.filter { live.contains($0.key) }
    }

    private func symbol(for kind: ServiceKind) -> NSImage {
        if let cached = symbols[kind] { return cached }
        let image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.label)
            ?? NSImage(systemSymbolName: "network", accessibilityDescription: kind.label)!
        symbols[kind] = image
        return image
    }

    private func resolve(_ port: ListeningPort) -> Resolved {
        let exe = ProcessLookup.executablePath(pid: port.pid)
        let bundle = exe.flatMap(bundlePath(containing:))
        let cwd = ProcessLookup.workingDirectory(pid: port.pid)
        let command = ProcessLookup.arguments(pid: port.pid).map { String($0.joined(separator: " ").prefix(300)) }

        if let app = NSRunningApplication(processIdentifier: port.pid), let icon = app.icon {
            return Resolved(displayName: app.localizedName ?? port.processName,
                            icon: icon, bundlePath: app.bundleURL?.path, executablePath: exe,
                            workingDirectory: cwd, commandLine: command)
        }
        if let bundle {
            let icon = NSWorkspace.shared.icon(forFile: bundle)
            let name = Bundle(path: bundle).flatMap { b in
                (b.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? b.object(forInfoDictionaryKey: "CFBundleName")) as? String
            } ?? port.processName
            return Resolved(displayName: name, icon: icon, bundlePath: bundle, executablePath: exe,
                            workingDirectory: cwd, commandLine: command)
        }
        return Resolved(displayName: port.processName, icon: nil, bundlePath: nil, executablePath: exe,
                        workingDirectory: cwd, commandLine: command)
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
