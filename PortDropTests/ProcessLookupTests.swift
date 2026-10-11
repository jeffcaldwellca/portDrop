import XCTest
@testable import PortDrop

final class ProcessLookupTests: XCTestCase {
    func testWorkingDirectoryOfThisProcess() {
        XCTAssertEqual(ProcessLookup.workingDirectory(pid: getpid()), FileManager.default.currentDirectoryPath)
    }

    func testWorkingDirectoryOfMissingPidIsNil() {
        XCTAssertNil(ProcessLookup.workingDirectory(pid: 999_999))
    }

    func testArgumentsOfThisProcess() {
        XCTAssertEqual(ProcessLookup.arguments(pid: getpid()), ProcessInfo.processInfo.arguments)
    }

    /// KERN_PROCARGS2: argc, the exec path, NUL padding, then argc NUL-terminated arguments, then the environment.
    func testParseProcArgsStopsAtArgc() {
        var buf: [UInt8] = withUnsafeBytes(of: Int32(3)) { Array($0) }
        buf += Array("/usr/local/bin/node".utf8) + [0, 0, 0, 0]
        for s in ["node", "server.js", "--port=3000", "SECRET=1", "HOME=/Users/x"] { buf += Array(s.utf8) + [0] }
        XCTAssertEqual(ProcessLookup.parseProcArgs(buf), ["node", "server.js", "--port=3000"])
    }

    func testParseProcArgsRejectsGarbage() {
        XCTAssertNil(ProcessLookup.parseProcArgs([1, 2]))
        XCTAssertNil(ProcessLookup.parseProcArgs([0, 0, 0, 0]))
    }
}
