import Foundation
import Testing
@testable import Bittern

@Suite
struct TradingViewServerTests {
    @Test(arguments: [
        ("proxy.example.com", "proxy.example.com"),
        ("  Proxy.Example.COM ", "proxy.example.com"),
        ("wss://proxy.example.com/socket.io/websocket?from=chart%2F&type=chart", "proxy.example.com"),
        ("https://data.example.com:8443/", "data.example.com:8443")
    ])
    func aHostIsReadFromWhatIsTypedOrPasted(text: String, host: String) throws {
        let server = try #require(TradingViewServer(text))

        #expect(server.host == host)
        #expect(server.socketURL?.absoluteString == "wss://\(host)/socket.io/websocket?from=chart%2F&type=chart")
    }

    @Test(arguments: ["", "   ", "not a host", "localhost", "ftp://data.example.com", "wss://user:pass@data.example.com"])
    func textWithoutAUsableHostIsNoServer(text: String) {
        #expect(TradingViewServer(text) == nil)
    }

    @Test func theStoreKeepsOnlyAServerOfTheUsers() throws {
        let defaults = try #require(UserDefaults(suiteName: "TradingViewServerTests-\(UUID().uuidString)"))
        let store = TradingViewServerStore(defaults: defaults)
        #expect(store.server == .tradingView)

        let custom = try #require(TradingViewServer("proxy.example.com"))
        store.save(custom)
        #expect(store.server == custom)

        store.save(.tradingView)
        #expect(store.server == .tradingView)
        #expect(defaults.object(forKey: AppSettingKey.marketDataServer) == nil)
    }
}

@Suite
struct MarketDataServerSwitchTests {
    private let custom = TradingViewServer("proxy.example.com")!
    private let request = [MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock)]

    @Test func usingAServerMovesTheConnectionToIt() async throws {
        let server = FakeTradingViewServer(quotes: ["AAPL": FakeMarket.stockQuote()])
        let client = server.client(at: marketTime(day: 6, hour: 11))
        _ = try await client.quotes(for: request)

        await client.use(custom)

        #expect(client.server == custom)
        _ = try await client.quotes(for: request)
        #expect(server.hosts == ["data.tradingview.com", "proxy.example.com"])
        #expect(server.messages(named: "quote_add_symbols").count == 2)
    }

    @Test func aCheckUsesAConnectionOfItsOwn() async throws {
        let server = FakeTradingViewServer(quotes: [
            "AAPL": FakeMarket.stockQuote(),
            "CRYPTO:BTCUSD": FakeMarket.cryptoQuote(price: 75_000, previousClose: 74_000)
        ])
        let client = server.client(at: marketTime(day: 6, hour: 11))
        _ = try await client.quotes(for: request)

        let check = try await client.check(custom)

        #expect(check.price == 75_000)
        #expect(check.server == custom)
        #expect(client.server == .tradingView)
        _ = try await client.quotes(for: request)
        #expect(server.hosts == ["data.tradingview.com", "proxy.example.com"])
    }

    @Test func aServerThatSendsNoQuoteFailsItsCheck() async throws {
        let server = FakeTradingViewServer(quotes: [:])
        let client = server.client(at: marketTime(day: 6, hour: 11))

        await #expect(throws: TradingViewError.self) {
            try await client.check(custom)
        }
    }

    @Test func aServerThatCanNotBeReachedFailsItsCheck() async throws {
        let server = FakeTradingViewServer(quotes: [:])
        server.setRefusesConnections(true)

        await #expect(throws: URLError.self) {
            try await server.client(at: marketTime(day: 6, hour: 11)).check(custom)
        }
    }
}

@Suite
struct MarketDataServerModelTests {
    /// Answers server checks with `check`; nothing else.
    private struct CheckingRepository: PortfolioRepository {
        let check: @Sendable (TradingViewServer) throws -> TradingViewServerCheck
        let used: UsedServers
        private let offline = UnavailablePortfolioRepository()

        func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult {
            try await offline.loadPortfolio(credentials: credentials)
        }
        func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult {
            try await offline.refreshPrices(for: snapshot)
        }
        func priceHistory(for holding: PortfolioHolding, range: HoldingChartRange) async throws -> HoldingPriceSeries {
            try await offline.priceHistory(for: holding, range: range)
        }
        func portfolioHistory(credentials: SnapTradeCredentials, accountIDs: [String]) async throws -> PortfolioHistory {
            try await offline.portfolioHistory(credentials: credentials, accountIDs: accountIDs)
        }
        func registerUser(apiKey: SnapTradeCredentials) async throws -> SnapTradeCredentials {
            try await offline.registerUser(apiKey: apiKey)
        }
        func connectionPortalURL(credentials: SnapTradeCredentials, darkMode: Bool) async throws -> URL {
            try await offline.connectionPortalURL(credentials: credentials, darkMode: darkMode)
        }
        func checkMarketDataServer(_ server: TradingViewServer) async throws -> TradingViewServerCheck {
            try check(server)
        }
        func useMarketDataServer(_ server: TradingViewServer) async {
            used.servers.append(server)
        }
    }

    private final class UsedServers: @unchecked Sendable {
        var servers: [TradingViewServer] = []
    }

    private nonisolated static func passing(_ server: TradingViewServer) -> TradingViewServerCheck {
        TradingViewServerCheck(server: server, duration: .milliseconds(300), symbol: "CRYPTO:BTCUSD", price: 75_000, currencyCode: "USD", isRealTime: true)
    }

    @Test func aServerIsUsedOnlyAfterItsCheckPasses() async {
        let used = UsedServers()
        let model = MarketDataServerModel(current: .tradingView)
        model.draft = "proxy.example.com"

        let failing = CheckingRepository(check: { _ in throw URLError(.cannotFindHost) }, used: used)
        #expect(await model.save(using: failing) == false)
        #expect(model.current == .tradingView)
        #expect(model.checkState == .failed("The host couldn’t be found."))
        #expect(used.servers.isEmpty)

        let working = CheckingRepository(check: Self.passing, used: used)
        #expect(await model.save(using: working))
        #expect(model.current.host == "proxy.example.com")
        #expect(used.servers.map(\.host) == ["proxy.example.com"])
    }

    @Test func anEmptyDraftMeansTradingViewAndAnUnreadableOneCanNotBeSaved() {
        let model = MarketDataServerModel(current: TradingViewServer("proxy.example.com")!)
        #expect(model.draft == "proxy.example.com")

        model.draft = ""
        #expect(model.draftServer == .tradingView)
        #expect(model.canSave)

        model.draft = "not a host"
        #expect(model.draftServer == nil)
        #expect(!model.canSave)
    }

    @Test func editingTheDraftClearsAnEarlierResult() async {
        let model = MarketDataServerModel(current: .tradingView)
        model.draft = "proxy.example.com"
        await model.test(using: CheckingRepository(check: Self.passing, used: UsedServers()))
        #expect(model.checkState != .idle)

        model.draft = "other.example.com"

        #expect(model.checkState == .idle)
    }
}
