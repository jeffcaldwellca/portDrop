import Darwin
import Foundation

/// Facts about a pid that the kernel hands out without root, including for other users' processes.
enum ProcessLookup {
    static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(len)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func executableName(pid: pid_t) -> String? {
        executablePath(pid: pid).map { ($0 as NSString).lastPathComponent }
    }

    /// Login name of the process owner, or the numeric uid when it has no passwd entry.
    static func user(pid: pid_t) -> String? {
        guard let uid = info(pid: pid)?.kp_eproc.e_ucred.cr_uid else { return nil }
        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 1024)
        guard getpwuid_r(uid, &pwd, &buffer, buffer.count, &result) == 0, result != nil else { return String(uid) }
        return String(cString: pwd.pw_name)
    }

    /// False once the process is gone or is only a zombie waiting to be reaped.
    static func isRunning(pid: pid_t) -> Bool {
        guard let info = info(pid: pid) else { return false }
        return info.kp_proc.p_stat != SZOMB
    }

    private static func info(pid: pid_t) -> kinfo_proc? {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
