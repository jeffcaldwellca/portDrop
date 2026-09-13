import XCTest
@testable import PortDrop

final class DockerInspectorTests: XCTestCase {
    static let compose = #"{"ID":"abc123","Labels":"com.docker.compose.config-hash=72b,com.docker.compose.project=can-railway,com.docker.compose.service=postgres,com.docker.compose.version=2.39.4","Names":"can-railway-postgres-1","Ports":"0.0.0.0:5433->5432/tcp, [::]:5433->5432/tcp","State":"running"}"#
    static let k3d = #"{"ID":"def456","Labels":"app=k3d,k3d.role=loadbalancer,maintainer=NGINX Docker Maintainers <docker-maint@nginx.com>","Names":"k3d-canrail-serverlb","Ports":"0.0.0.0:80->80/tcp, [::]:80->80/tcp, 0.0.0.0:443->443/tcp, [::]:443->443/tcp, 0.0.0.0:51130->6443/tcp","State":"running"}"#
    static let noPorts = #"{"ID":"ghi789","Labels":"","Names":"k3d-canrail-agent-0","Ports":"","State":"running"}"#
    static let exposedOnly = #"{"ID":"jkl012","Labels":"","Names":"redis","Ports":"6379/tcp","State":"running"}"#

    func testComposeContainer() {
        let c = DockerInspector.parse(Self.compose)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].id, "abc123")
        XCTAssertEqual(c[0].name, "can-railway-postgres-1")
        XCTAssertEqual(c[0].project, "can-railway")
        XCTAssertEqual(c[0].service, "postgres")
        XCTAssertEqual(c[0].ports, [DockerPortMapping(hostPort: 5433, containerPort: 5432)])
    }

    func testPlainContainerWithManyPorts() {
        let c = DockerInspector.parse(Self.k3d)
        XCTAssertEqual(c.count, 1)
        XCTAssertNil(c[0].project)
        XCTAssertNil(c[0].service)
        XCTAssertEqual(Set(c[0].ports.map(\.hostPort)), [80, 443, 51130])
        XCTAssertEqual(c[0].ports.first { $0.hostPort == 51130 }?.containerPort, 6443)
    }

    func testNoPortsAndExposedOnlyYieldEmptyMappings() {
        let c = DockerInspector.parse([Self.noPorts, Self.exposedOnly].joined(separator: "\n"))
        XCTAssertEqual(c.count, 2)
        XCTAssertTrue(c[0].ports.isEmpty)
        XCTAssertTrue(c[1].ports.isEmpty)
    }

    func testMalformedLineSkipped() {
        let c = DockerInspector.parse("not json\n" + Self.compose + "\n\n")
        XCTAssertEqual(c.map(\.name), ["can-railway-postgres-1"])
    }

    func testBindingsKeyedByHostPortFirstWins() {
        let dup = #"{"ID":"zzz","Labels":"","Names":"other","Ports":"0.0.0.0:5433->1/tcp","State":"running"}"#
        let b = DockerInspector.bindings(from: DockerInspector.parse([Self.compose, Self.k3d, dup].joined(separator: "\n")))
        XCTAssertEqual(Set(b.keys), [5433, 80, 443, 51130])
        XCTAssertEqual(b[5433]?.container.name, "can-railway-postgres-1")
        XCTAssertEqual(b[5433]?.containerPort, 5432)
        XCTAssertEqual(b[5433]?.displayName, "postgres")
        XCTAssertTrue(b[5433]!.isCompose)
        XCTAssertEqual(b[80]?.displayName, "k3d-canrail-serverlb")
        XCTAssertFalse(b[80]!.isCompose)
    }

    func testHostProcessNames() {
        XCTAssertTrue(DockerInspector.isHostProcess("com.docker.backend"))
        XCTAssertTrue(DockerInspector.isHostProcess("com.docke"))   // lsof truncates command names in some modes
        XCTAssertTrue(DockerInspector.isHostProcess("OrbStack Helper"))
        XCTAssertFalse(DockerInspector.isHostProcess("postgres"))
        XCTAssertFalse(DockerInspector.isHostProcess("com"))
    }
}
