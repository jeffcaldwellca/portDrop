import XCTest
@testable import PortDrop

final class DockerControllerTests: XCTestCase {
    func testDownServiceArguments() {
        XCTAssertEqual(DockerController.arguments(for: .downService(project: "can-railway", service: "postgres")),
                       ["compose", "-p", "can-railway", "down", "postgres"])
    }
    func testDownProjectArguments() {
        XCTAssertEqual(DockerController.arguments(for: .downProject(project: "can-railway")),
                       ["compose", "-p", "can-railway", "down"])
    }
    func testStopContainerArguments() {
        XCTAssertEqual(DockerController.arguments(for: .stopContainer(id: "abc123", name: "redis")), ["stop", "abc123"])
    }
    func testActionsForBindings() {
        let compose = DockerContainer(id: "a", name: "p-postgres-1", project: "p", service: "postgres", ports: [])
        let plain = DockerContainer(id: "b", name: "redis", project: nil, service: nil, ports: [])
        XCTAssertEqual(DockerAction.primary(for: DockerBinding(container: compose, containerPort: 1)),
                       .downService(project: "p", service: "postgres"))
        XCTAssertEqual(DockerAction.project(for: DockerBinding(container: compose, containerPort: 1)), .downProject(project: "p"))
        XCTAssertEqual(DockerAction.primary(for: DockerBinding(container: plain, containerPort: 1)),
                       .stopContainer(id: "b", name: "redis"))
        XCTAssertNil(DockerAction.project(for: DockerBinding(container: plain, containerPort: 1)))
    }
    func testVerbs() {
        XCTAssertEqual(DockerAction.downService(project: "p", service: "s").verb, "Down")
        XCTAssertEqual(DockerAction.stopContainer(id: "a", name: "n").verb, "Stop")
    }
}
