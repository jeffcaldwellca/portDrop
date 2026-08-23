import XCTest
@testable import PortDrop

final class ProcessKillerTests: XCTestCase {
    func testKillsOwnedProcess() async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["60"]
        try p.run()
        XCTAssertTrue(p.isRunning)
        try await ProcessKiller.kill(pid: p.processIdentifier, force: false)
        p.waitUntilExit()
        XCTAssertFalse(p.isRunning)
        XCTAssertEqual(p.terminationReason, .uncaughtSignal)
    }

    func testAlreadyGoneIsSuccess() async throws {
        try await ProcessKiller.kill(pid: 999_999, force: false)
    }
}
