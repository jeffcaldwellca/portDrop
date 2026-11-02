import Foundation

enum Subprocess {
    struct Result: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        /// The deadline fired and the process was killed; `status` is then meaningless.
        let timedOut: Bool
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// Runs `executable` and collects its output. Returns nil when it cannot be launched. Both pipes are
    /// drained concurrently so a chatty child cannot fill one and stall; at `timeout` the process gets
    /// SIGTERM and, two seconds later, SIGKILL.
    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                    currentDirectory: URL? = nil, timeout: Duration) async -> Result? {
        let seconds = Int(timeout.components.seconds)
        return await Task.detached(priority: .userInitiated) { () -> Result? in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = arguments
            if let environment { p.environment = environment }
            if let currentDirectory { p.currentDirectoryURL = currentDirectory }
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            let exited = p.exitSignal()
            do { try p.run() } catch { return nil }
            let timedOut = Flag()
            let pid = p.processIdentifier
            // Weak: the timer keeps this item until it fires even when cancelled, and holding `p` would hold
            // its pipes' descriptors open that long.
            let deadline = DispatchWorkItem { [weak p] in
                guard let p, p.isRunning else { return }
                timedOut.set()
                p.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(2)) { if p.isRunning { kill(pid, SIGKILL) } }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds), execute: deadline)
            let errTask = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = await errTask.value
            for await _ in exited {}
            deadline.cancel()
            return Result(status: p.terminationStatus,
                          stdout: String(decoding: outData, as: UTF8.self),
                          stderr: String(decoding: errData, as: UTF8.self),
                          timedOut: timedOut.isSet)
        }.value
    }
}

extension Process {
    /// Finishes when the process exits; call before `run()`. Used instead of `waitUntilExit()`, which spins the
    /// calling thread's run loop and, on a Swift-concurrency thread, can miss a fast child's exit and block forever.
    func exitSignal() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        terminationHandler = { _ in continuation.finish() }
        return stream
    }
}
