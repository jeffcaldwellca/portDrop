import Network
import XCTest
@testable import PortDrop

/// A one-shot local TCP server that answers every connection with a fixed response and counts them.
final class CannedServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var count = 0

    var connections: Int { lock.lock(); defer { lock.unlock() }; return count }

    init(response: String) throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] c in
            guard let self else { return }
            self.lock.lock(); self.count += 1; self.lock.unlock()
            c.start(queue: .global())
            c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                c.send(content: Data(response.utf8), completion: .contentProcessed { _ in c.cancel() })
            }
        }
    }

    func start() async -> UInt16 {
        await withCheckedContinuation { cont in
            listener.stateUpdateHandler = { [listener] state in
                guard case .ready = state else { return }
                listener.stateUpdateHandler = nil
                cont.resume(returning: listener.port?.rawValue ?? 0)
            }
            listener.start(queue: .global())
        }
    }

    func stop() { listener.cancel() }
}

final class HTTPProbeTests: XCTestCase {
    func testPlainResponseCountsAsHTTP() async throws {
        let server = try CannedServer(response: "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        let port = await server.start()
        defer { server.stop() }
        let ok = await HTTPProbe.respondsToHTTP(host: "127.0.0.1", port: port)
        XCTAssertTrue(ok)
    }

    func testRedirectIsNotFollowed() async throws {
        let target = try CannedServer(response: "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        let targetPort = await target.start()
        let redirector = try CannedServer(response: "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:\(targetPort)/\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        let port = await redirector.start()
        defer { target.stop(); redirector.stop() }

        let ok = await HTTPProbe.respondsToHTTP(host: "127.0.0.1", port: port)
        XCTAssertTrue(ok, "a redirect is still an HTTP answer")
        XCTAssertEqual(redirector.connections, 1)
        XCTAssertEqual(target.connections, 0, "the probe must not contact the redirect target")
    }
}
