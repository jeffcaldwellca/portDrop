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

    /// Only readable for the caller's own processes; nil for everyone else's.
    static func workingDirectory(pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    /// argv of the process (own processes only).
    static func arguments(pid: pid_t) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return parseProcArgs(Array(buffer.prefix(size)))
    }

    /// KERN_PROCARGS2 layout: argc, the exec path, NUL padding, argc NUL-terminated arguments, then the
    /// environment — which is deliberately left unread.
    static func parseProcArgs(_ buffer: [UInt8]) -> [String]? {
        let header = MemoryLayout<Int32>.size
        guard buffer.count > header else { return nil }
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var i = header
        while i < buffer.count, buffer[i] != 0 { i += 1 }
        while i < buffer.count, buffer[i] == 0 { i += 1 }
        var args: [String] = []
        while args.count < Int(argc), i < buffer.count {
            let start = i
            while i < buffer.count, buffer[i] != 0 { i += 1 }
            args.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        return args.isEmpty ? nil : args
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
