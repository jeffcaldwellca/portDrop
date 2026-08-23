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

    static func classify(port: UInt16, processName: String, bindAddress: String) -> ServiceInfo {
        let host = host(for: bindAddress)
        let name = processName.lowercased()

        func info(_ kind: ServiceKind, _ url: String?) -> ServiceInfo {
            ServiceInfo(kind: kind, url: url.flatMap(URL.init(string:)))
        }

        if name.contains("postgres") { return info(.postgres, "postgresql://\(host):\(port)") }
        if name.contains("mysqld") || name.contains("mariadb") { return info(.mysql, "mysql://\(host):\(port)") }
        if name.contains("redis") { return info(.redis, "redis://\(host):\(port)") }
        if name.contains("mongod") { return info(.mongo, "mongodb://\(host):\(port)") }
        if name == "sshd" { return info(.ssh, "ssh://\(host):\(port)") }
        if name.contains("ftpd") { return info(.ftp, "ftp://\(host):\(port)") }

        switch port {
        case 443, 8443: return info(.https, "https://\(host):\(port)")
        case 21: return info(.ftp, "ftp://\(host)")
        case 22: return info(.ssh, "ssh://\(host)")
        case 5432: return info(.postgres, "postgresql://\(host):5432")
        case 3306: return info(.mysql, "mysql://\(host):3306")
        case 6379: return info(.redis, "redis://\(host):6379")
        case 27017: return info(.mongo, "mongodb://\(host):27017")
        case 5900: return info(.vnc, "vnc://\(host)")
        case 445: return info(.smb, "smb://\(host)")
        case 548: return info(.afp, "afp://\(host)")
        default:
            if httpPorts.contains(port) { return info(.http, "http://\(host):\(port)") }
            return info(.tcp, nil)
        }
    }

    static func httpInfo(port: UInt16, bindAddress: String) -> ServiceInfo {
        ServiceInfo(kind: .http, url: URL(string: "http://\(host(for: bindAddress)):\(port)"))
    }
}
