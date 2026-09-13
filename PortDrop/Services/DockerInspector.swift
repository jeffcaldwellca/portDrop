import Foundation

enum DockerInspector {
    /// macOS processes that own the host side of published container ports. lsof truncates command
    /// names to 9 characters in some modes, so a prefix of at least that length also matches.
    static let hostProcessNames: [String] = ["com.docker.backend", "com.docker.vpnkit", "vpnkit", "OrbStack Helper"]

    static func isHostProcess(_ processName: String) -> Bool {
        hostProcessNames.contains { $0 == processName || (processName.count >= 9 && $0.hasPrefix(processName)) }
    }

    /// Parses `docker ps --no-trunc --format '{{json .}}'` output (one JSON object per line).
    static func parse(_ output: String) -> [DockerContainer] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["ID"] as? String, let name = obj["Names"] as? String else { return nil }
            let labels = parseLabels(obj["Labels"] as? String ?? "")
            return DockerContainer(id: id, name: name,
                                   project: labels["com.docker.compose.project"],
                                   service: labels["com.docker.compose.service"],
                                   ports: parsePorts(obj["Ports"] as? String ?? ""))
        }
    }

    /// `k=v,k=v`; values may contain `=` but the labels we read never contain `,`.
    static func parseLabels(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in s.split(separator: ",") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            out[String(pair[..<eq])] = String(pair[pair.index(after: eq)...])
        }
        return out
    }

    /// `0.0.0.0:5433->5432/tcp, [::]:5433->5432/tcp, 6379/tcp` → [(5433, 5432)]: IPv4/IPv6 twins collapse,
    /// exposed-but-unpublished entries (no arrow) are ignored. Docker collapses consecutive mappings into
    /// ranges (`0.0.0.0:8000-8002->8000-8002/tcp`), which expand to one mapping per port.
    static func parsePorts(_ s: String) -> [DockerPortMapping] {
        var seen: Set<UInt16> = []
        var out: [DockerPortMapping] = []
        for entry in s.split(separator: ",") {
            let e = entry.trimmingCharacters(in: .whitespaces)
            guard e.hasSuffix("/tcp"), let arrow = e.range(of: "->") else { continue }
            let hostSide = e[..<arrow.lowerBound]
            guard let colon = hostSide.lastIndex(of: ":"),
                  let hosts = portRange(hostSide[hostSide.index(after: colon)...]),
                  let containers = portRange(e[arrow.upperBound...].dropLast(4)),
                  hosts.count == containers.count else { continue }
            for (host, container) in zip(hosts, containers) where seen.insert(host).inserted {
                out.append(DockerPortMapping(hostPort: host, containerPort: container))
            }
        }
        return out
    }

    /// "5432" → [5432]; "8000-8002" → [8000, 8001, 8002]; anything else → nil.
    private static func portRange(_ s: Substring) -> [UInt16]? {
        let parts = s.split(separator: "-", maxSplits: 1).map { UInt16($0) }
        switch parts.count {
        case 1: return parts[0].map { [$0] }
        case 2:
            guard let lo = parts[0], let hi = parts[1], lo <= hi else { return nil }
            return Array(lo...hi)
        default: return nil
        }
    }

    static func bindings(from containers: [DockerContainer]) -> [UInt16: DockerBinding] {
        var out: [UInt16: DockerBinding] = [:]
        for c in containers {
            for m in c.ports where out[m.hostPort] == nil {
                out[m.hostPort] = DockerBinding(container: c, containerPort: m.containerPort)
            }
        }
        return out
    }
}

// MARK: - Running the CLI

extension DockerInspector {
    static let candidatePaths: [String] = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        NSString(string: "~/.docker/bin/docker").expandingTildeInPath,
        "/Applications/Docker.app/Contents/Resources/bin/docker",
        "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
    ]

    private static let pathLock = NSLock()
    nonisolated(unsafe) private static var cachedPath: String?

    /// First executable docker binary from `candidatePaths`. Only a hit is cached, so installing Docker
    /// while PortDrop is running (a menu-bar app can stay up for weeks) is picked up on the next scan.
    static func locateDocker() -> String? {
        pathLock.lock(); defer { pathLock.unlock() }
        if let cachedPath { return cachedPath }
        let found = candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        cachedPath = found
        return found
    }

    struct CLIResult: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        /// The deadline fired and the process was killed; `status` is then meaningless.
        let timedOut: Bool
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// Runs the docker CLI with a PATH that includes its own directory (for cli-plugins and credential helpers).
    /// Returns nil when no binary exists or it cannot be launched. Both pipes are drained concurrently so a
    /// chatty child (compose logs progress to stderr) cannot fill one and stall; at `timeout` the process gets
    /// SIGTERM and, two seconds later, SIGKILL.
    static func run(_ arguments: [String], timeout: Duration) async -> CLIResult? {
        guard let docker = locateDocker() else { return nil }
        let seconds = Int(timeout.components.seconds)
        return await Task.detached(priority: .userInitiated) { () -> CLIResult? in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: docker)
            p.arguments = arguments
            // A neutral cwd: `compose -p X down` would otherwise pick up a compose file from wherever the app was launched.
            p.currentDirectoryURL = FileManager.default.temporaryDirectory
            var env = ProcessInfo.processInfo.environment
            let dir = (docker as NSString).deletingLastPathComponent
            env["PATH"] = [dir, "/usr/local/bin", "/opt/homebrew/bin", env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
            p.environment = env
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do { try p.run() } catch { return nil }
            let timedOut = Flag()
            let pid = p.processIdentifier
            let deadline = DispatchWorkItem {
                guard p.isRunning else { return }
                timedOut.set()
                p.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(2)) { if p.isRunning { kill(pid, SIGKILL) } }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds), execute: deadline)
            let errTask = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = await errTask.value
            p.waitUntilExit()
            deadline.cancel()
            return CLIResult(status: p.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self),
                             timedOut: timedOut.isSet)
        }.value
    }

    /// Running containers, or an empty list when Docker is absent, stopped, or slow. Never throws: that is normal.
    static func scan() async -> [DockerContainer] {
        guard let r = await run(["ps", "--no-trunc", "--format", "{{json .}}"], timeout: .seconds(5)),
              !r.timedOut, r.status == 0 else { return [] }
        return parse(r.stdout)
    }
}
