import XCTest
@testable import PortDrop

final class SystemPortScannerTests: XCTestCase {
    static let header = """
    Active Internet connections (including servers)
    Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)          rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options           gencnt    flags   flags1 usecnt rtncnt fltrs
    """
    static func row(_ proto: String, _ local: String, _ process: String, state: String = "LISTEN") -> String {
        "\(proto)       0      0  \(local)        *.*                    \(state)                 0            0  131072  131072 \(process)  00180 00000206 00000000020153a5 00000001 00000800      1      0 000000"
    }
    func parse(_ rows: String...) -> [ListeningPort] {
        SystemPortScanner.parse(([Self.header] + rows).joined(separator: "\n"),
                                user: { $0 == 77960 ? "root" : "jeff" }, name: { _ in nil })
    }

    func testLoopbackTwinsMergeIntoOneRootListener() {
        let ports = parse(Self.row("tcp4", "127.0.0.1.53907", "EABackgroundServ:77960"),
                          Self.row("tcp6", "::1.53907", "EABackgroundServ:77960"))
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].pid, 77960)
        XCTAssertEqual(ports[0].processName, "EABackgroundServ")
        XCTAssertEqual(ports[0].user, "root")
        XCTAssertEqual(ports[0].port, 53907)
        XCTAssertEqual(ports[0].bindAddress, "127.0.0.1")
        XCTAssertEqual(ports[0].ipVersions, [.v4, .v6])
    }

    func testWildcardDualStackSocket() {
        let ports = parse(Self.row("tcp46", "*.5000", "ControlCenter:612"))
        XCTAssertEqual(ports.map(\.bindAddress), ["*"])
        XCTAssertEqual(ports[0].ipVersions, [.v4, .v6])
    }

    func testProcessNameWithSpaces() {
        let ports = parse(Self.row("tcp4", "127.0.0.1.42050", "OneDrive Sync Se:901"))
        XCTAssertEqual(ports.map(\.processName), ["OneDrive Sync Se"])
        XCTAssertEqual(ports.map(\.pid), [901])
    }

    func testFullNameFromLookupBeatsTruncatedColumn() {
        let out = [Self.header, Self.row("tcp4", "*.22", "EABackgroundServ:77960")].joined(separator: "\n")
        let ports = SystemPortScanner.parse(out, user: { _ in nil }, name: { _ in "EABackgroundService" })
        XCTAssertEqual(ports.map(\.processName), ["EABackgroundService"])
        XCTAssertEqual(ports.map(\.user), ["?"])
    }

    func testConnectedSocketsAndGarbageAreIgnored() {
        let ports = parse(Self.row("tcp4", "127.0.0.1.50000", "node:5", state: "ESTABLISHED"),
                          "udp4       0      0  *.5353      *.*      0 0 1 1 mDNSResponder:400",
                          "nonsense")
        XCTAssertTrue(ports.isEmpty)
    }

    func testSortedByPort() {
        let ports = parse(Self.row("tcp4", "*.8080", "b:2"), Self.row("tcp4", "*.22", "a:1"))
        XCTAssertEqual(ports.map(\.port), [22, 8080])
    }
}
