import XCTest
@testable import PortDrop

final class PortMonitorTests: XCTestCase {
    func p(_ pid: pid_t, _ port: UInt16) -> ListeningPort {
        ListeningPort(pid: pid, processName: "x", user: "u", port: port, bindAddress: "*", ipVersions: [.v4])
    }
    func testNewIDs() {
        let old = [p(1, 80), p(2, 443)]
        let new = [p(2, 443), p(3, 3000)]
        XCTAssertEqual(PortMonitor.newIDs(old: old, new: new), ["3:3000"])
    }
    func testNoNewIDsWhenUnchanged() {
        let a = [p(1, 80)]
        XCTAssertEqual(PortMonitor.newIDs(old: a, new: a), [])
    }
    @MainActor func testFilter() {
        let m = PortMonitor(autoStart: false)
        m.ports = [p(1, 80), p(2, 5432)]
        m.services = ["1:80": ServiceInfo(kind: .http, url: nil), "2:5432": ServiceInfo(kind: .postgres, url: nil)]
        m.searchText = "postg"
        XCTAssertEqual(m.filteredPorts.map(\.port), [5432])
        m.searchText = "80"
        XCTAssertEqual(m.filteredPorts.map(\.port), [80])
        m.searchText = ""
        XCTAssertEqual(m.filteredPorts.count, 2)
    }
}
