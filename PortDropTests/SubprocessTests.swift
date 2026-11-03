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
    /// It fails on a stall, not on slowness: CI runners launch processes far slower than a Mac does.
    func testManyShortLivedChildrenAllReturn() async throws {
        let batches = (Int(ProcessInfo.processInfo.environment["PORTDROP_SUBPROCESS_STRESS"] ?? "") ?? 2000) / 4
        let progress = BatchProgress()
        // Unstructured, so a hung child cannot hold the test open: the watchdog below gives up on it instead.
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
                if let failure = results.first { progress.finish(failure: "batch \(i): \(failure)"); return }
                progress.completedUnitCount = Int64(i + 1)
            }
            progress.finish(failure: nil)
        }
        var seen: Int64 = -1, lastChange = ContinuousClock.now
        while !progress.isFinished {
            if progress.completedUnitCount != seen { seen = progress.completedUnitCount; lastChange = .now }
            if ContinuousClock.now - lastChange > .seconds(15) {
                return XCTFail("stalled after \(seen) of \(batches) batches: a child's exit was never seen")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        if let failure = progress.failure { XCTFail(failure) }
    }

    private final class BatchProgress: @unchecked Sendable {
        private let lock = NSLock()
        private var count: Int64 = 0, done = false, message: String?
        var completedUnitCount: Int64 {
            get { lock.withLock { count } }
            set { lock.withLock { count = newValue } }
        }
        var isFinished: Bool { lock.withLock { done } }
        var failure: String? { lock.withLock { message } }
        func finish(failure: String?) { lock.withLock { done = true; message = failure } }
    }

    func testMissingExecutableIsNil() async {
        let r = await Subprocess.run("/nonexistent/portdrop-binary", [], timeout: .seconds(1))
        XCTAssertNil(r)
    }
}
