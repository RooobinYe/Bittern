import Foundation
import Testing
import UIKit
@testable import Bittern

extension NetworkTests {
    @Suite(.serialized)
    struct LogoClientTests {
        private nonisolated static let validSVGData = Data(
            """
            <svg width="18" height="18" xmlns="http://www.w3.org/2000/svg">
              <path fill="#112233" d="M0 0h18v18H0z"/>
            </svg>
            """.utf8
        )

        private nonisolated static let samplePNGData: Data = {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24), format: format).pngData { ctx in
                UIColor.systemBlue.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
            }
        }()

        private func makeStore(host: String? = nil) throws -> TradingViewServerStore {
            let suite = "LogoClientTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            let store = TradingViewServerStore(defaults: defaults)
            if let host {
                let server = try #require(TradingViewServer(host))
                store.save(server)
            }
            return store
        }

        private func makeClient(
            host: String? = nil,
            diskCache: LogoDiskCache = .disabled,
            handler: @escaping LogoStubURLProtocol.Handler
        ) throws -> LogoClient {
            let session = LogoStubURLProtocol.session(handler: handler)
            let store = try makeStore(host: host)
            return LogoClient(
                session: session,
                serverStore: store,
                diskCache: diskCache,
                userAgent: "BitternTests/1.0"
            )
        }

        private func makeTempDirectory() throws -> URL {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("LogoClientTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        @Test func svgLogoIsRasterizedTo256Pixels() async throws {
            let url = try #require(URL(string: "https://s3-symbol-logo.tradingview.com/apple.svg"))
            let client = try makeClient { _ in
                (200, "image/svg+xml", Self.validSVGData)
            }

            let image = try await client.image(for: "AAPL", at: url)

            #expect(image.cgImage?.width == 256)
            #expect(image.cgImage?.height == 256)
        }

        @Test func rasterBrokerageLogoBypassesRelayRewrite() async throws {
            let url = try #require(URL(string: "https://snaptrade.example.com/broker.png"))
            let client = try makeClient(host: "proxy.example.com") { _ in
                (200, "image/png", Self.samplePNGData)
            }

            let image = try await client.image(for: "Broker", at: url)

            #expect(image.cgImage?.width == 24)
            #expect(LogoStubURLProtocol.requestedURLs == [url])
        }

        @Test func customServerRoutesTradingViewLogosThroughSymbolLogoRelay() async throws {
            let canonical = try #require(URL(string: "https://s3-symbol-logo.tradingview.com/crypto/XTVCBTC.svg"))
            let expectedRelay = try #require(URL(string: "https://proxy.example.com/symbol-logo/crypto/XTVCBTC.svg"))
            let client = try makeClient(host: "proxy.example.com") { _ in
                (200, "image/svg+xml", Self.validSVGData)
            }

            let image = try await client.image(for: "BTC", at: canonical)

            #expect(image.cgImage?.width == 256)
            #expect(LogoStubURLProtocol.requestedURLs == [expectedRelay])
        }

        @Test(arguments: [403, 404, 405])
        func relayFailureDoesNotFallBackToTradingViewCDN(statusCode: Int) async throws {
            let canonical = try #require(URL(string: "https://s3-symbol-logo.tradingview.com/apple.svg"))
            let expectedRelay = try #require(URL(string: "https://proxy.example.com/symbol-logo/apple.svg"))
            let client = try makeClient(host: "proxy.example.com") { request in
                if request.url == expectedRelay {
                    return (statusCode, "application/json", Data(#"{"error":"Not found"}"#.utf8))
                }
                return (200, "image/svg+xml", Self.validSVGData)
            }

            await #expect(throws: LogoClientError.httpStatus(statusCode, "application/json")) {
                try await client.image(for: "AAPL", at: canonical)
            }
            #expect(LogoStubURLProtocol.requestedURLs == [expectedRelay])
        }

        @Test func memoryCacheAvoidsDuplicateNetworkRequests() async throws {
            let url = try #require(URL(string: "https://s3-symbol-logo.tradingview.com/apple.svg"))
            let client = try makeClient { _ in
                (200, "image/svg+xml", Self.validSVGData)
            }

            _ = try await client.image(for: "AAPL", at: url)
            _ = try await client.image(for: "AAPL", at: url)

            #expect(LogoStubURLProtocol.requestedURLs.count == 1)
        }

        @Test func malformedSVGThrowsInvalidImageData() async throws {
            let url = try #require(URL(string: "https://s3-symbol-logo.tradingview.com/bad.svg"))
            let client = try makeClient { _ in
                (200, "image/svg+xml", Data("not valid svg".utf8))
            }

            await #expect(throws: LogoClientError.invalidImageData) {
                try await client.image(for: "BAD", at: url)
            }
        }

        @Test func diskCachePersistsAcrossClientInstancesWithoutNetwork() async throws {
            let dir = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }

            let diskCache = LogoDiskCache(directoryURL: dir)
            let url = try #require(URL(string: "https://s3-symbol-logo.tradingview.com/apple.svg"))
            let firstClient = try makeClient(diskCache: diskCache) { _ in
                (200, "image/svg+xml", Self.validSVGData)
            }

            let firstImage = try await firstClient.image(for: "AAPL", at: url)
            #expect(firstImage.cgImage?.width == 256)
            #expect(LogoStubURLProtocol.requestedURLs == [url])

            let secondClient = try makeClient(diskCache: diskCache) { _ in
                Issue.record("Unexpected network request on disk cache hit")
                return (500, "text/plain", Data())
            }
            #expect(secondClient.cachedImage(for: url) == nil)

            let secondImage = try await secondClient.image(for: "AAPL", at: url)
            #expect(secondImage.cgImage?.width == 256)
            #expect(secondClient.cachedImage(for: url) != nil)
            #expect(LogoStubURLProtocol.requestedURLs.isEmpty)
        }

        @Test func warmFromDiskPopulatesMemoryCacheAndIgnoresMissingURLs() async throws {
            let dir = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: dir) }

            let diskCache = LogoDiskCache(directoryURL: dir)
            let apple = try #require(URL(string: "https://s3-symbol-logo.tradingview.com/apple.svg"))
            let missing = try #require(URL(string: "https://s3-symbol-logo.tradingview.com/missing.svg"))

            let writer = try makeClient(diskCache: diskCache) { _ in
                (200, "image/svg+xml", Self.validSVGData)
            }
            _ = try await writer.image(for: "AAPL", at: apple)

            let warmed = try makeClient(diskCache: diskCache) { _ in
                Issue.record("Unexpected network request during disk warmup")
                return (500, "text/plain", Data())
            }
            await warmed.warmFromDisk(urls: [apple, apple, missing])

            #expect(warmed.cachedImage(for: apple)?.cgImage?.width == 256)
            #expect(warmed.cachedImage(for: missing) == nil)
            #expect(LogoStubURLProtocol.requestedURLs.isEmpty)
        }
    }
}

private nonisolated final class LogoStubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (status: Int, contentType: String, body: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var recorded: [URL] = []

    static func session(handler: @escaping Handler) -> URLSession {
        lock.withLock {
            self.handler = handler
            recorded = []
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LogoStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static var requestedURLs: [URL] {
        lock.withLock { recorded }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock {
            if let url = request.url {
                Self.recorded.append(url)
            }
            return Self.handler
        }
        do {
            guard let handler, let url = request.url else {
                throw URLError(.badURL)
            }
            let (status, contentType, body) = try handler(request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType]
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
