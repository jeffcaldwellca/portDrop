import Foundation
import Darwin

enum KillError: LocalizedError {
    case cancelled
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .cancelled: "Authentication cancelled"
        case .failed(let m): m
        }
    }
}

enum ProcessKiller {
    /// Sends SIGTERM (or SIGKILL when `force`) to `pid`, escalating to an admin auth dialog when not permitted.
    static func kill(pid: pid_t, force: Bool) async throws {
        let signal = force ? SIGKILL : SIGTERM
        if Darwin.kill(pid, signal) == 0 { return }
        switch errno {
        case ESRCH: return // already gone
        case EPERM: try await killAsAdmin(pid: pid, signal: force ? "KILL" : "TERM")
        default: throw KillError.failed(String(cString: strerror(errno)))
        }
    }

    private static func killAsAdmin(pid: pid_t, signal: String) async throws {
        let script = "do shell script \"/bin/kill -\(signal) \(pid)\" with administrator privileges"
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = Pipe()
            do { try p.run() } catch { throw KillError.failed(error.localizedDescription) }
            let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            guard p.terminationStatus != 0 else { return }
            if errText.contains("-128") { throw KillError.cancelled }
            if errText.contains("No such process") { return }
            throw KillError.failed(errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }
}
