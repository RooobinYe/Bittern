//
//  TradingViewClient.swift
//  Bittern
//
//  Market data from TradingView's chart WebSocket, as an anonymous user:
//  quotes from a quote session that streams every change, and price
//  history from chart sessions. Real-time for US stocks (from Cboe One) and
//  for crypto.
//

import Foundation
import OSLog

struct TradingViewClient {
    /// How long a request waits for quotes of symbols the stream hasn't
    /// delivered yet.
    static let quoteTimeout: Duration = .seconds(8)
    static let chartTimeout: Duration = .seconds(10)

    typealias SocketFactory = @Sendable (TradingViewServer) async throws -> any TradingViewSocket
    typealias LogoRouteCheck = @Sendable (TradingViewServer, Duration) async -> Bool

    let currentDate: @Sendable () -> Date
    let serverStore: TradingViewServerStore
    let makeSocket: SocketFactory
    let checkLogoRoute: LogoRouteCheck
    let connection: TradingViewConnection
    let quoteFeed: TradingViewQuoteFeed

    /// - Parameter makeSocket: Opens a socket to a server. Each new
    ///   connection goes to the server saved in `serverStore` at that time.
    init(
        serverStore: TradingViewServerStore,
        makeSocket: @escaping SocketFactory,
        checkLogoRoute: @escaping LogoRouteCheck = { _, _ in true },
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.currentDate = currentDate
        self.serverStore = serverStore
        self.makeSocket = makeSocket
        self.checkLogoRoute = checkLogoRoute
        connection = TradingViewConnection(makeSocket: { try await makeSocket(serverStore.server) })
        quoteFeed = TradingViewQuoteFeed(connection: connection)
    }

    init(
        session: URLSession = .shared,
        serverStore: TradingViewServerStore = TradingViewServerStore(),
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            serverStore: serverStore,
            makeSocket: { server in
                guard let url = server.socketURL else { throw URLError(.badURL) }
                return URLSessionTradingViewSocket(session: session, url: url)
            },
            checkLogoRoute: { server, timeout in
                await Self.checkLogoRoute(on: server, using: session, timeout: timeout)
            },
            currentDate: currentDate
        )
    }

    var server: TradingViewServer {
        serverStore.server
    }

    /// Whether the connection market data comes through is live. See
    /// `TradingViewConnection.isLive`.
    func isConnected() async -> Bool {
        await connection.isLive
    }

    /// Saves `server` and drops the open connection, so every request from
    /// now on goes through it.
    func use(_ server: TradingViewServer) async {
        serverStore.save(server)
        await connection.disconnect()
        AppLog.marketData.debug("Market data server changed tradingView=\(server.isTradingView, privacy: .public)")
    }

    /// Whether `server` answers like TradingView: a connection of its own
    /// that has to deliver a live Bitcoin quote within `timeout`, plus a
    /// concurrent `HEAD` probe for symbol logos. The connection in use is left
    /// alone.
    func check(_ server: TradingViewServer, timeout: Duration = .seconds(10)) async throws -> TradingViewServerCheck {
        let symbol = "CRYPTO:BTCUSD"
        let connection = TradingViewConnection(makeSocket: { [makeSocket] in try await makeSocket(server) })
        let feed = TradingViewQuoteFeed(connection: connection)
        let clock = ContinuousClock()
        let startedAt = clock.now
        defer { Task { await connection.disconnect() } }

        async let logosAvailable = checkLogoRoute(server, timeout)
        let states = try await feed.quotes(for: [symbol], timeout: timeout)
        let duration = clock.now - startedAt
        switch states[symbol] {
        case .ready(let fields):
            guard let price = fields["lp"]?.number, price.isFinite, price > 0 else {
                throw TradingViewError.noMarketData
            }
            return TradingViewServerCheck(
                server: server,
                duration: duration,
                symbol: symbol,
                price: price,
                currencyCode: fields["currency_code"]?.string,
                isRealTime: fields["update_mode"]?.string == "streaming",
                logosAvailable: await logosAvailable
            )
        case .failed(let reason):
            throw TradingViewError.invalidSymbol(symbol: symbol, reason: reason)
        case .pending, nil:
            throw TradingViewError.timedOut("a Bitcoin quote")
        }
    }

    nonisolated static func checkLogoRoute(
        on server: TradingViewServer,
        using session: URLSession,
        timeout: Duration = .seconds(10)
    ) async -> Bool {
        guard let canonicalURL = TradingViewServer.canonicalLogoURL(forLogoID: "crypto/XTVCBTC") else {
            return false
        }
        let targetURL = server.logoRequestURL(for: canonicalURL) ?? canonicalURL
        let components = timeout.components
        let timeoutSeconds = max(
            Double(components.seconds) + Double(components.attoseconds) / 1e18,
            1
        )

        var request = URLRequest(
            url: targetURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeoutSeconds
        )
        request.httpMethod = "HEAD"
        request.setValue("image/svg+xml,image/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let mimeType = httpResponse.mimeType,
                  mimeType.lowercased().hasPrefix("image/")
            else {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    /// The TradingView symbol for a holding. Crypto is TradingView's own
    /// index against the dollar ("CRYPTO:BTCUSD"); anything else is the
    /// bare ticker, which TradingView resolves to its primary listing. The
    /// kind comes from SnapTrade, never from the ticker's length: short ETF
    /// symbols such as IAUM and QQQM would otherwise read as crypto.
    func tradingViewSymbol(
        for rawSymbol: String,
        instrumentKind: PortfolioInstrumentKind?
    ) -> String? {
        let upper = normalizedSymbol(rawSymbol)
        guard !upper.isEmpty else { return nil }
        guard instrumentKind == .crypto, !upper.contains(":") else {
            return upper
        }
        if upper.contains("-") {
            return "CRYPTO:" + upper.replacingOccurrences(of: "-", with: "")
        }
        return "CRYPTO:\(upper)USD"
    }

    func normalizedSymbol(_ symbol: String) -> String {
        symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func logKind(_ instrumentKind: PortfolioInstrumentKind?) -> String {
        instrumentKind?.rawValue ?? "unknown"
    }
}
