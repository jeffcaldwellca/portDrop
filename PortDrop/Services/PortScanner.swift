import Foundation

enum ScanError: LocalizedError {
    case lsofFailed(String)
    var errorDescription: String? {
        switch self {
        case .lsofFailed(let msg): return "lsof failed: \(msg)"
        }
    }
}

enum PortScanner {
    static let lsofPath = "/usr/sbin/lsof"
    static let arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-F", "pcLnT"]

    /// Parses `lsof -F pcLnT` output into listening ports, merging IPv4/IPv6 twins.
    static func parse(_ output: String) -> [ListeningPort] {
        var result: [String: ListeningPort] = [:]
        var order: [String] = []
        var pid: pid_t = 0
        var name = ""
        var user = ""

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = pid_t(value) ?? 0
                name = ""
                user = ""
            case "c": name = value
            case "L": user = value
            case "n":
                guard let (address, port, version) = splitAddress(value) else { continue }
                let key = "\(pid):\(port)"
                if var existing = result[key] {
                    existing.ipVersions.insert(version)
                    result[key] = existing
                } else {
                    result[key] = ListeningPort(pid: pid, processName: name, user: user,
                                                port: port, bindAddress: address, ipVersions: [version])
                    order.append(key)
                }
            default: break
            }
        }
        return order.compactMap { result[$0] }
            .sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    private static func splitAddress(_ value: String) -> (String, UInt16, IPVersion)? {
        guard let colon = value.lastIndex(of: ":") else { return nil }
        guard let port = UInt16(value[value.index(after: colon)...]) else { return nil }
        var host = String(value[..<colon])
        let isV6 = host.hasPrefix("[")
        if isV6 { host = String(host.dropFirst().dropLast()) }
        if host == "*" || host.isEmpty { host = "*" }
        return (host, port, isV6 ? .v6 : .v4)
    }

    static func scan() async throws -> [ListeningPort] {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: lsofPath)
            process.arguments = arguments
            let stdout = Pipe(), stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do { try process.run() } catch { throw ScanError.lsofFailed(error.localizedDescription) }
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: outData, as: UTF8.self)
            // lsof exits 1 when nothing matched or when some fds couldn't be read; only fail on empty output + error text.
            if output.isEmpty && process.terminationStatus != 0 {
                let err = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !err.isEmpty { throw ScanError.lsofFailed(err) }
            }
            return parse(output)
        }.value
    }
}
