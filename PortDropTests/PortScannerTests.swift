import XCTest
@testable import PortDrop

final class PortScannerTests: XCTestCase {
    func testSingleIPv4Listener() {
        let out = "p123\ncnode\nLjeff\nn*:3000\nTST=LISTEN\n"
        let ports = PortScanner.parse(out)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].pid, 123)
        XCTAssertEqual(ports[0].processName, "node")
        XCTAssertEqual(ports[0].user, "jeff")
        XCTAssertEqual(ports[0].port, 3000)
        XCTAssertEqual(ports[0].bindAddress, "*")
        XCTAssertEqual(ports[0].ipVersions, [.v4])
    }

    func testIPv4AndIPv6TwinsMerge() {
        let out = "p5\ncpython\nLjeff\nn127.0.0.1:8000\nTST=LISTEN\nn[::1]:8000\nTST=LISTEN\n"
        let ports = PortScanner.parse(out)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].ipVersions, [.v4, .v6])
        XCTAssertEqual(ports[0].bindAddress, "127.0.0.1")
    }

    func testTwoProcessesSortedByPort() {
        let out = "p900\ncsshd\nLroot\nn*:22\nTST=LISTEN\np5\ncpython\nLjeff\nn*:8000\nTST=LISTEN\n"
        let ports = PortScanner.parse(out)
        XCTAssertEqual(ports.map(\.port), [22, 8000])
        XCTAssertEqual(ports[0].user, "root")
    }

    func testOneProcessManyPorts() {
        let out = "p7\ncpostgres\nLjeff\nn127.0.0.1:5432\nTST=LISTEN\nn127.0.0.1:5433\nTST=LISTEN\n"
        XCTAssertEqual(PortScanner.parse(out).count, 2)
    }

    func testEmpty() {
        XCTAssertEqual(PortScanner.parse("").count, 0)
    }
}
