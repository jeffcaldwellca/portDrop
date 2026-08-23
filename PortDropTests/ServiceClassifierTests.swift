import XCTest
@testable import PortDrop

final class ServiceClassifierTests: XCTestCase {
    func c(_ port: UInt16, _ name: String = "x", _ bind: String = "*") -> ServiceInfo {
        ServiceClassifier.classify(port: port, processName: name, bindAddress: bind)
    }
    func testHTTP() { XCTAssertEqual(c(3000), ServiceInfo(kind: .http, url: URL(string: "http://localhost:3000"))) }
    func testHTTPS() { XCTAssertEqual(c(443).kind, .https) }
    func testFTP() { XCTAssertEqual(c(21).url?.absoluteString, "ftp://localhost") }
    func testPostgres() { XCTAssertEqual(c(5432).url?.absoluteString, "postgresql://localhost:5432") }
    func testProcessNameTiebreak() { XCTAssertEqual(c(6380, "redis-server").kind, .redis) }
    func testUnknown() { XCTAssertEqual(c(9999), ServiceInfo(kind: .tcp, url: nil)) }
    func testSpecificBind() { XCTAssertEqual(c(3000, "x", "192.168.1.5").url?.host, "192.168.1.5") }
    func testLoopbackV6() { XCTAssertEqual(ServiceClassifier.host(for: "::1"), "localhost") }
}
