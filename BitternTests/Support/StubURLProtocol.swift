import Foundation

/// Answers every request from a test-supplied handler. The handler is global,
/// so every suite that uses it is nested under the serialized `NetworkTests`.
nonisolated final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (status: Int, body: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    nonisolated(unsafe) private static var responseDelay: TimeInterval = 0
    nonisolated(unsafe) private static var inFlight = 0
    nonisolated(unsafe) private static var peak = 0

    /// `responseDelay` keeps requests open long enough to overlap. All loading
    /// starts on one CFNetwork thread, so a handler that blocks can't measure it.
    static func session(
        responseDelay: TimeInterval = 0,
        handler: @escaping Handler
    ) -> URLSession {
        lock.withLock {
            self.handler = handler
            self.responseDelay = responseDelay
            recorded = []
            inFlight = 0
            peak = 0
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    /// The most requests that were open at the same moment.
    static var peakInFlight: Int {
        lock.withLock { peak }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (handler, delay) = Self.lock.withLock {
            Self.recorded.append(request)
            Self.inFlight += 1
            Self.peak = max(Self.peak, Self.inFlight)
            return (Self.handler, Self.responseDelay)
        }
        guard delay > 0 else {
            respond(using: handler)
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            self.respond(using: handler)
        }
    }

    private func respond(using handler: Handler?) {
        Self.lock.withLock { Self.inFlight -= 1 }
        do {
            guard let handler, let url = request.url else {
                throw URLError(.badURL)
            }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    nonisolated func queryValue(_ name: String) -> String? {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
