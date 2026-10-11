import Foundation

/// Listeners owned by root and other users. lsof only reports the caller's own processes without root;
/// `netstat -anv` names the owning pid of every socket, so it fills in the rest.
enum SystemPortScanner {
    static let netstatPath = "/usr/sbin/netstat"
    static let arguments = ["-anv", "-p", "tcp"]

    /// Parses `netstat -anv -p tcp` into listening ports, merging IPv4/IPv6 twins. The process column is
    /// truncated (and may contain spaces), so `name` supplies the full name when the pid can be looked up.
    static func parse(_ output: String, user: (pid_t) -> String?, name: (pid_t) -> String?) -> [ListeningPort] {
        var result: [String: ListeningPort] = [:]
        for line in output.split(separator: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count > 10, f[0].hasPrefix("tcp"), f[5] == "LISTEN",
                  let dot = f[3].lastIndex(of: "."), let port = UInt16(f[3][f[3].index(after: dot)...]),
                  // "process:pid" — the first field from the process column on that ends in ":<digits>".
                  let end = f[10...].firstIndex(where: { $0.split(separator: ":").count > 1 && pid_t($0.split(separator: ":").last!) != nil }),
                  let pid = pid_t(f[end].split(separator: ":").last!) else { continue }
            let column = f[10...end].joined(separator: " ")
            let truncated = String(column[..<column.lastIndex(of: ":")!])
            let versions: Set<IPVersion> = switch f[0] {
            case "tcp4": [.v4]
            case "tcp6": [.v6]
            default: [.v4, .v6]
            }
            let key = "\(pid):\(port)"
            if var existing = result[key] {
                existing.ipVersions.formUnion(versions)
                result[key] = existing
            } else {
                result[key] = ListeningPort(pid: pid, processName: name(pid) ?? truncated, user: user(pid) ?? "?",
                                            port: port, bindAddress: String(f[3][..<dot]), ipVersions: versions)
            }
        }
        return result.values.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    /// Every listener netstat can see, or an empty list when it fails: the lsof scan still stands on its own.
    static func scan() async -> [ListeningPort] {
        guard let r = await Subprocess.run(netstatPath, arguments, timeout: .seconds(5)), !r.timedOut else { return [] }
        return parse(r.stdout, user: ProcessLookup.user(pid:), name: ProcessLookup.executableName(pid:))
    }
}
