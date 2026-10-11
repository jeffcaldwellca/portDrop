import AppKit
import XCTest
@testable import PortDrop

final class RowTextTests: XCTestCase {
    func port(user: String = "jeff", bind: String = "*") -> ListeningPort {
        ListeningPort(pid: 42, processName: "node", user: user, port: 3000, bindAddress: bind, ipVersions: [.v4])
    }
    func presentation(cwd: String?) -> ProcessPresentation {
        ProcessPresentation(displayName: "node", icon: NSImage(), bundlePath: nil, executablePath: nil,
                            workingDirectory: cwd, commandLine: nil)
    }

    func testProjectNameIsTheFolder() {
        XCTAssertEqual(ProcessPresentation.projectName(workingDirectory: "/Users/jeff/Dev/shop", home: "/Users/jeff"), "shop")
    }
    func testRootAndHomeAreNotProjects() {
        XCTAssertNil(ProcessPresentation.projectName(workingDirectory: "/", home: "/Users/jeff"))
        XCTAssertNil(ProcessPresentation.projectName(workingDirectory: "/Users/jeff", home: "/Users/jeff"))
        XCTAssertNil(ProcessPresentation.projectName(workingDirectory: nil, home: "/Users/jeff"))
    }

    func testSubtitleNamesTheProjectForYourOwnProcess() {
        XCTAssertEqual(PortRowView.subtitle(port: port(), projectName: "shop", docker: nil, currentUser: "jeff"), "shop · PID 42")
    }
    func testSubtitleFallsBackToUser() {
        XCTAssertEqual(PortRowView.subtitle(port: port(), projectName: nil, docker: nil, currentUser: "jeff"), "jeff · PID 42")
    }
    func testSubtitleKeepsAnotherUsersName() {
        XCTAssertEqual(PortRowView.subtitle(port: port(user: "root"), projectName: "db", docker: nil, currentUser: "jeff"), "root · PID 42")
    }
    func testSubtitleForDockerIsTheComposeProject() {
        let c = DockerContainer(id: "a", name: "shop-db-1", project: "shop", service: "db", ports: [])
        XCTAssertEqual(PortRowView.subtitle(port: port(), projectName: "x", docker: DockerBinding(container: c, containerPort: 1), currentUser: "jeff"), "shop")
    }

    func testLoopbackOnly() {
        XCTAssertTrue(port(bind: "127.0.0.1").isLoopbackOnly)
        XCTAssertTrue(port(bind: "::1").isLoopbackOnly)
        XCTAssertTrue(port(bind: "127.0.0.53").isLoopbackOnly)
        XCTAssertFalse(port(bind: "*").isLoopbackOnly)
        XCTAssertFalse(port(bind: "192.168.1.5").isLoopbackOnly)
        XCTAssertFalse(port(bind: "::").isLoopbackOnly)
    }

    func testSelectionMovesAndClamps() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(PanelView.nextSelection(current: nil, by: 1, in: ids), "a")
        XCTAssertEqual(PanelView.nextSelection(current: nil, by: -1, in: ids), "c")
        XCTAssertEqual(PanelView.nextSelection(current: "a", by: 1, in: ids), "b")
        XCTAssertEqual(PanelView.nextSelection(current: "c", by: 1, in: ids), "c")
        XCTAssertEqual(PanelView.nextSelection(current: "a", by: -1, in: ids), "a")
        XCTAssertEqual(PanelView.nextSelection(current: "gone", by: 1, in: ids), "a")
        XCTAssertNil(PanelView.nextSelection(current: "a", by: 1, in: []))
    }
}
