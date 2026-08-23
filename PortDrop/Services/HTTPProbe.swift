import Foundation

enum HTTPProbe {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 0.3
        c.timeoutIntervalForResource = 0.5
        return URLSession(configuration: c)
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
