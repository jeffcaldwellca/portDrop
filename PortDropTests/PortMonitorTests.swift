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

    @MainActor func testDockerBindingRequiresHostProcess() {
        let m = PortMonitor(autoStart: false)
        let c = DockerContainer(id: "a", name: "p-postgres-1", project: "p", service: "postgres", ports: [.init(hostPort: 5432, containerPort: 5432)])
        m.dockerContainers = [c]
        m.docker = DockerInspector.bindings(from: [c])
        let native = ListeningPort(pid: 1, processName: "postgres", user: "u", port: 5432, bindAddress: "*", ipVersions: [.v4])
        let backend = ListeningPort(pid: 2, processName: "com.docker.backend", user: "u", port: 5432, bindAddress: "*", ipVersions: [.v6])
        XCTAssertNil(m.dockerBinding(for: native))
        XCTAssertEqual(m.dockerBinding(for: backend)?.displayName, "postgres")
    }

    @MainActor func testSearchMatchesDockerNames() {
        let m = PortMonitor(autoStart: false)
        let c = DockerContainer(id: "a", name: "can-railway-postgres-1", project: "can-railway", service: "postgres", ports: [.init(hostPort: 5433, containerPort: 5432)])
        m.dockerContainers = [c]
        m.docker = DockerInspector.bindings(from: [c])
        m.ports = [ListeningPort(pid: 2, processName: "com.docker.backend", user: "u", port: 5433, bindAddress: "*", ipVersions: [.v6]), p(1, 80)]
        m.searchText = "railway"
        XCTAssertEqual(m.filteredPorts.map(\.port), [5433])
        m.searchText = "postgres"
        XCTAssertEqual(m.filteredPorts.map(\.port), [5433])
    }

    @MainActor func testProjectContainerCount() {
        let m = PortMonitor(autoStart: false)
        m.dockerContainers = [
            DockerContainer(id: "a", name: "x-db-1", project: "x", service: "db", ports: []),
            DockerContainer(id: "b", name: "x-web-1", project: "x", service: "web", ports: []),
            DockerContainer(id: "c", name: "loose", project: nil, service: nil, ports: []),
        ]
        XCTAssertEqual(m.projectContainerCount("x"), 2)
        XCTAssertEqual(m.projectContainerCount("nope"), 0)
    }
}
