import XCTest
@testable import PortDrop

final class ProcessInfoResolverTests: XCTestCase {
    @MainActor func testFallbackIconFollowsTheKind() {
        // No process has this pid, so the resolver falls back to the kind's SF Symbol.
        let port = ListeningPort(pid: 999_999, processName: "x", user: "u", port: 9999, bindAddress: "*", ipVersions: [.v4])
        let resolver = ProcessInfoResolver()
        XCTAssertEqual(resolver.presentation(for: port, kind: .tcp).icon.accessibilityDescription, "TCP")
        XCTAssertEqual(resolver.presentation(for: port, kind: .http).icon.accessibilityDescription, "HTTP")
    }
}
