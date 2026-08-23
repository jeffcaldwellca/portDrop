import Foundation

enum IPVersion: Hashable, Sendable {
    case v4, v6
}

struct ListeningPort: Identifiable, Hashable, Sendable {
    let pid: pid_t
    let processName: String
    let user: String
    let port: UInt16
    let bindAddress: String
    var ipVersions: Set<IPVersion>

    var id: String { "\(pid):\(port)" }
}
