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

    /// `Process.waitUntilExit()` can miss a fast child's exit and park its thread forever, which froze the
    /// whole scan loop. Thousands of short-lived children, a few at a time like a scan, must all come back.
    /// The hang is rare, so this can pass by luck; `PORTDROP_SUBPROCESS_STRESS=<n>` runs more children.
    func testManyShortLivedChildrenAllReturn() async {
        let batches = (Int(ProcessInfo.processInfo.environment["PORTDROP_SUBPROCESS_STRESS"] ?? "") ?? 2000) / 4
        let done = expectation(description: "every child came back")
        // Unstructured, so a hung child cannot hold the test open: the expectation times out instead.
        Task.detached {
            for i in 0..<batches {
                let results = await withTaskGroup(of: String?.self) { batch in
                    for _ in 0..<4 {
                        batch.addTask {
                            guard let r = await Subprocess.run("/usr/bin/true", [], timeout: .seconds(5)) else { return "not launched" }
                            return r.status == 0 && !r.timedOut ? nil : "status \(r.status), timedOut \(r.timedOut)"
                        }
                    }
                    return await batch.compactMap { $0 }.reduce(into: []) { $0.append($1) }
                }
                if let failure = results.first {
                    XCTFail("batch \(i): \(failure)")
                    break
                }
            }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: Double(batches) * 0.01 + 5)   // ~0.3 ms a child when healthy
    }

    func testMissingExecutableIsNil() async {
        let r = await Subprocess.run("/nonexistent/portdrop-binary", [], timeout: .seconds(1))
        XCTAssertNil(r)
    }
}
