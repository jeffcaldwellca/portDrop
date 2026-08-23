import SwiftUI

enum ServiceKind: String, Sendable, CaseIterable {
    case http, https, ftp, ssh, postgres, mysql, redis, mongo, vnc, smb, afp, tcp

    var label: String {
        switch self {
        case .http: "HTTP"
        case .https: "HTTPS"
        case .ftp: "FTP"
        case .ssh: "SSH"
        case .postgres: "Postgres"
        case .mysql: "MySQL"
        case .redis: "Redis"
        case .mongo: "MongoDB"
        case .vnc: "VNC"
        case .smb: "SMB"
        case .afp: "AFP"
        case .tcp: "TCP"
        }
    }

    var symbolName: String {
        switch self {
        case .http, .https: "globe"
        case .ftp: "folder.badge.gearshape"
        case .ssh: "terminal"
        case .postgres, .mysql, .redis, .mongo: "cylinder.split.1x2"
        case .vnc: "display"
        case .smb, .afp: "externaldrive.connected.to.line.below"
        case .tcp: "network"
        }
    }

    var tint: Color {
        switch self {
        case .http: .blue
        case .https: .green
        case .ftp: .orange
        case .ssh: .purple
        case .postgres: .indigo
        case .mysql: .teal
        case .redis: .red
        case .mongo: .mint
        case .vnc: .pink
        case .smb, .afp: .brown
        case .tcp: .gray
        }
    }
}

struct ServiceInfo: Hashable, Sendable {
    let kind: ServiceKind
    let url: URL?
}
