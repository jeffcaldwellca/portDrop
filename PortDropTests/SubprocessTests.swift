import XCTest
@testable import PortDrop

final class SubprocessTests: XCTestCase {
    func testCapturesBothStreamsAndStatus() async {
        let r = await Subprocess.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], timeout: .seconds(5))
        XCTAssertEqual(r?.status, 3)
        XCTAssertEqual(r?.stdout, "out\n")
        XCTAssertEqual(r?.stderr, "err\n")
        XCTAssertEqual(r?.timedOut, false)
    }

    func testTimeoutKillsTheChild() async {
        let start = ContinuousClock.now
        let r = await Subprocess.run("/bin/sleep", ["30"], timeout: .seconds(1))
        XCTAssertEqual(r?.timedOut, true)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(10))
    }

    func testMissingExecutableIsNil() async {
        let r = await Subprocess.run("/nonexistent/portdrop-binary", [], timeout: .seconds(1))
        XCTAssertNil(r)
    }
}
