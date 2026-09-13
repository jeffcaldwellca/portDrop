import XCTest
@testable import PortDrop

/// Exercises the real docker CLI against a throwaway compose project. Skipped unless
/// `PORTDROP_DOCKER_E2E=1` (pass it to xcodebuild as `TEST_RUNNER_PORTDROP_DOCKER_E2E=1`).
final class DockerIntegrationTests: XCTestCase {
    static let project = "portdrop-e2e"
    static let compose = """
    services:
      web:
        image: alpine
        command: ["sh", "-c", "while :; do nc -l -p 80 </dev/null; done"]
        ports: ["18081:80"]
      side:
        image: alpine
        command: ["sh", "-c", "trap exit TERM; while :; do sleep 1; done"]
    """

    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PORTDROP_DOCKER_E2E"] == "1", "set PORTDROP_DOCKER_E2E=1 to run")
        try XCTSkipUnless(DockerInspector.locateDocker() != nil, "docker CLI not installed")
    }

    func testComposeLifecycle() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(Self.project)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("compose.yml")
        try Self.compose.write(to: file, atomically: true, encoding: .utf8)
        addTeardownBlock {
            // Awaited, so an early failure above still leaves nothing running on the developer's machine.
            _ = await DockerInspector.run(["compose", "-p", Self.project, "down"], timeout: .seconds(60))
            try? FileManager.default.removeItem(at: dir)
        }

        let up = await DockerInspector.run(["compose", "-p", Self.project, "-f", file.path, "up", "-d"], timeout: .seconds(120))
        XCTAssertEqual(up?.status, 0, up?.stderr ?? "no result")

        var bindings = DockerInspector.bindings(from: await DockerInspector.scan())
        let web = try XCTUnwrap(bindings[18081])
        XCTAssertEqual(web.displayName, "web")
        XCTAssertEqual(web.container.project, Self.project)
        XCTAssertEqual(web.containerPort, 80)
        XCTAssertEqual(DockerAction.primary(for: web), .downService(project: Self.project, service: "web"))

        try await DockerController.run(DockerAction.primary(for: web))
        var containers = await DockerInspector.scan()
        bindings = DockerInspector.bindings(from: containers)
        XCTAssertNil(bindings[18081], "web should be gone")
        XCTAssertEqual(containers.filter { $0.project == Self.project }.map(\.service), ["side"], "side should survive a service-level down")

        try await DockerController.run(.downProject(project: Self.project))
        containers = await DockerInspector.scan()
        XCTAssertTrue(containers.filter { $0.project == Self.project }.isEmpty)
    }

    func testFailedActionThrowsLastStderrLine() async {
        do {
            try await DockerController.run(.stopContainer(id: "no-such-container-portdrop", name: "x"))
            XCTFail("expected an error")
        } catch let DockerError.failed(msg) {
            XCTAssertTrue(msg.contains("No such container"), msg)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
