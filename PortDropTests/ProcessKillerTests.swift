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

    func testWaitForExitReportsASurvivor() async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "trap '' TERM; echo ready; while :; do sleep 1; done"]
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        addTeardownBlock { if p.isRunning { Darwin.kill(p.processIdentifier, SIGKILL) } }
        _ = out.fileHandleForReading.availableData   // blocks until the trap is installed

        try await ProcessKiller.kill(pid: p.processIdentifier, force: false)
        let exitedAfterTerm = await ProcessKiller.waitForExit(pid: p.processIdentifier, timeout: .milliseconds(500))
        XCTAssertFalse(exitedAfterTerm, "the shell ignores SIGTERM")

        try await ProcessKiller.kill(pid: p.processIdentifier, force: true)
        let exitedAfterKill = await ProcessKiller.waitForExit(pid: p.processIdentifier, timeout: .seconds(3))
        XCTAssertTrue(exitedAfterKill)
    }

    func testWaitForExitOnMissingPidIsImmediate() async {
        let exited = await ProcessKiller.waitForExit(pid: 999_999, timeout: .seconds(3))
        XCTAssertTrue(exited)
    }
}
