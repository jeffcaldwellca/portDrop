import Foundation

enum HTTPProbe {
    /// A redirect is already proof of HTTP, and following one could send a request off this Mac.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 0.3
        c.timeoutIntervalForResource = 0.5
        return URLSession(configuration: c, delegate: NoRedirects(), delegateQueue: nil)
    }()

    /// True if anything speaking HTTP answers on host:port (any status code counts).
    static func respondsToHTTP(host: String, port: UInt16) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: req)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }
}
