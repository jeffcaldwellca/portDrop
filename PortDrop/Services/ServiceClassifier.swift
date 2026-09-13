import Foundation

enum ServiceClassifier {
    static let httpPorts: Set<UInt16> = {
        var s: Set<UInt16> = [80, 4000, 4200, 5000, 5173, 5174, 8888, 9000, 1313, 4321, 3000]
        s.formUnion(3000...3010); s.formUnion(8000...8010); s.formUnion(8080...8090)
        return s
    }()

    static func host(for bindAddress: String) -> String {
        switch bindAddress {
        case "*", "", "127.0.0.1", "::1", "0.0.0.0", "::", "localhost": "localhost"
        default: bindAddress.contains(":") ? "[\(bindAddress)]" : bindAddress
        }
    }

    /// `port` is the port on this Mac and is what every URL uses. `servicePort` is the port the service itself
    /// thinks it is on (a container's internal port); when given, it decides the kind instead of `port`.
    static func classify(port: UInt16, processName: String, bindAddress: String, servicePort: UInt16? = nil) -> ServiceInfo {
        let host = host(for: bindAddress)
        let name = processName.lowercased()

        func info(_ kind: ServiceKind, _ scheme: String?, omitPortWhen defaultPort: UInt16? = nil) -> ServiceInfo {
            let url = scheme.map { "\($0)://\(host)" + (port == defaultPort ? "" : ":\(port)") }
            return ServiceInfo(kind: kind, url: url.flatMap(URL.init(string:)))
        }

        func byName() -> ServiceInfo? {
            if name.contains("postgres") { return info(.postgres, "postgresql") }
            if name.contains("mysqld") || name.contains("mariadb") { return info(.mysql, "mysql") }
            if name.contains("redis") { return info(.redis, "redis") }
            if name.contains("mongod") { return info(.mongo, "mongodb") }
            if name == "sshd" { return info(.ssh, "ssh", omitPortWhen: 22) }
            if name.contains("ftpd") { return info(.ftp, "ftp", omitPortWhen: 21) }
            return nil
        }
        // A real process name is definitive. A compose service name is whatever the author typed
        // ("postgrest", "redis-commander"), so with a container port available that port goes first.
        if servicePort == nil, let named = byName() { return named }

        let wellKnown = servicePort ?? port
        switch wellKnown {
        case 443, 8443: return info(.https, "https")
        case 21: return info(.ftp, "ftp", omitPortWhen: 21)
        case 22: return info(.ssh, "ssh", omitPortWhen: 22)
        case 5432: return info(.postgres, "postgresql")
        case 3306: return info(.mysql, "mysql")
        case 6379: return info(.redis, "redis")
        case 27017: return info(.mongo, "mongodb")
        case 5900: return info(.vnc, "vnc", omitPortWhen: 5900)
        case 445: return info(.smb, "smb", omitPortWhen: 445)
        case 548: return info(.afp, "afp", omitPortWhen: 548)
        default:
            if httpPorts.contains(wellKnown) { return info(.http, "http") }
            return byName() ?? info(.tcp, nil)
        }
    }

    /// Classifies a scanned port, letting a Docker binding stand in for the opaque backend process:
    /// the compose service name and the container-side port are far better hints than "com.docker.backend:5433".
    static func classify(_ p: ListeningPort, docker: DockerBinding?) -> ServiceInfo {
        classify(port: p.port, processName: docker?.displayName ?? p.processName,
                 bindAddress: p.bindAddress, servicePort: docker?.containerPort)
    }

    static func httpInfo(port: UInt16, bindAddress: String) -> ServiceInfo {
        ServiceInfo(kind: .http, url: URL(string: "http://\(host(for: bindAddress)):\(port)"))
    }
}
