import Foundation

enum DockerInspector {
    /// macOS processes that own the host side of published container ports. lsof truncates command
    /// names in some modes, so a prefix of at least five characters matches.
    static let hostProcessNames: [String] = ["com.docker.backend", "com.docker.vpnkit", "vpnkit", "OrbStack Helper"]

    static func isHostProcess(_ processName: String) -> Bool {
        processName.count >= 5 && hostProcessNames.contains { $0.hasPrefix(processName) }
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
    /// exposed-but-unpublished entries (no arrow) are ignored.
    static func parsePorts(_ s: String) -> [DockerPortMapping] {
        var seen: Set<UInt16> = []
        var out: [DockerPortMapping] = []
        for entry in s.split(separator: ",") {
            let e = entry.trimmingCharacters(in: .whitespaces)
            guard e.hasSuffix("/tcp"), let arrow = e.range(of: "->") else { continue }
            let hostSide = e[..<arrow.lowerBound]
            let containerSide = e[arrow.upperBound...].dropLast(4)
            guard let colon = hostSide.lastIndex(of: ":"),
                  let host = UInt16(hostSide[hostSide.index(after: colon)...]),
                  let container = UInt16(containerSide),
                  seen.insert(host).inserted else { continue }
            out.append(DockerPortMapping(hostPort: host, containerPort: container))
        }
        return out
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
