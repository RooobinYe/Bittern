import Foundation
import Testing
@testable import Bittern

extension NetworkTests {
    /// The whole load pipeline, with only the network replaced.
    @Suite struct PortfolioRepositoryTests {
        private let credentials = SnapTradeCredentials(
            clientId: "client",
            consumerKey: "key",
            userId: "user",
            userSecret: "secret"
        )
        private let now = marketTime(day: 6, hour: 11)

        private func position(
            symbol: String? = "AAPL",
            kind: String = "stock",
            units: String? = "10",
            cost: String? = "100",
            currency: String? = "USD"
        ) -> String {
            let symbolJSON = symbol.map { #","symbol":"\#($0)","id":"id-\#($0)""# } ?? ""
            let unitsJSON = units.map { "\"\($0)\"" } ?? "null"
            let costJSON = cost.map { "\"\($0)\"" } ?? "null"
            let currencyJSON = currency.map { "\"\($0)\"" } ?? "null"
            return #"{"instrument":{"kind":"\#(kind)"\#(symbolJSON)},"units":\#(unitsJSON),"cost_basis":\#(costJSON),"currency":\#(currencyJSON)}"#
        }

        private func quote(price: Double = 110, currency: String = "USD") -> [String: JSONValue] {
            FakeMarket.stockQuote(price: price, previousClose: 105, currency: currency)
        }

        /// One account at one broker, holding `positions`. `quotes` maps a
        /// TradingView symbol to its quote fields; TradingView rejects any
        /// other symbol.
        private func repository(
            positions: [String],
            quotes: [String: [String: JSONValue]],
            activities: String = #"{"data":[],"pagination":{"total":0}}"#,
            at date: Date? = nil
        ) -> LivePortfolioRepository {
            let positionsJSON = #"{"results":[\#(positions.joined(separator: ","))],"data_freshness":{"as_of":"2026-11-06T15:00:00Z"}}"#
            let session = StubURLProtocol.session { request in
                let path = request.url?.path ?? ""
                switch path {
                case "/api/v1/authorizations":
                    return (200, Data(#"[{"id":"c1","brokerage":{"display_name":"Broker"}}]"#.utf8))
                case "/api/v1/authorizations/c1/accounts":
                    return (200, Data(#"[{"id":"a1","name":"Main","balance":{"total":{"amount":1000,"currency":"USD"}}}]"#.utf8))
                case "/api/v1/accounts/a1/positions/all":
                    return (200, Data(positionsJSON.utf8))
                case "/api/v1/accounts/a1/activities":
                    return (200, Data(activities.utf8))
                default:
                    return (404, Data())
                }
            }
            let date = date ?? now
            return makeLiveRepository(
                session: session,
                marketData: FakeTradingViewServer(quotes: quotes),
                currentDate: { date }
            )
        }

        @Test func buildsHoldingsFromThePublishedShapes() async throws {
            let activities = #"{"data":[{"symbol":{"symbol":"AAPL"},"amount":5,"currency":{"code":"USD"}}],"pagination":{"total":1}}"#
            let repository = repository(
                positions: [position()],
                quotes: ["AAPL": quote()],
                activities: activities
            )

            let result = try await repository.loadPortfolio(credentials: credentials)
            let holding = try #require(result.snapshot.holdings.first)

            #expect(holding.id == "a1-id-AAPL")
            #expect(holding.quantity == 10)
            #expect(holding.averageCost == 100)
            #expect(holding.currentPrice == 110)
            #expect(holding.previousClose == 105)
            #expect(holding.dividendsReceived == 5)
            #expect(result.snapshot.totalMarketValue == 1_100)
            #expect(result.snapshot.lastUpdated == now)
            #expect(result.partialFailure == PortfolioLoadPartialFailure())
        }

        @Test(arguments: [
            (nil as String?, "10" as String?, "USD" as String?),
            ("AAPL", nil, "USD"),
            ("AAPL", "10", nil)
        ])
        func unreadablePositionFailsTheLoad(symbol: String?, units: String?, currency: String?) async throws {
            let repository = repository(
                positions: [
                    position(symbol: "MSFT"),
                    position(symbol: symbol, units: units, currency: currency)
                ],
                quotes: ["MSFT": quote(), "AAPL": quote()]
            )

            await #expect(throws: PortfolioDataError.unreadablePositions(count: 1, accountNames: ["Main"])) {
                try await repository.loadPortfolio(credentials: credentials)
            }
        }

        @Test func cashIsNotAHoldingAndNotAnError() async throws {
            let cash = #"{"instrument":{"kind":"cash","code":"USD"},"units":"500","currency":"USD"}"#
            let repository = repository(
                positions: [position(), cash],
                quotes: ["AAPL": quote()]
            )

            let result = try await repository.loadPortfolio(credentials: credentials)

            #expect(result.snapshot.holdings.map(\.symbol) == ["AAPL"])
            #expect(result.snapshot.totalMarketValue == 1_100)
        }

        /// London shares can be quoted in pence. Treating 7,250 pence as
        /// £7,250 would overstate the holding a hundredfold.
        @Test func quoteInAnotherCurrencyIsNotUsed() async throws {
            let repository = repository(
                positions: [position(symbol: "VOD", currency: "GBP")],
                quotes: ["VOD": quote(price: 7_250, currency: "GBp")]
            )

            let result = try await repository.loadPortfolio(credentials: credentials)
            let holding = try #require(result.snapshot.holdings.first)

            #expect(holding.currentPrice == nil)
            #expect(holding.previousClose == nil)
            #expect(result.snapshot.totalMarketValue == nil)
            #expect(result.snapshot.lastUpdated == nil)
            #expect(
                result.partialFailure.currencyMismatches
                    == [PortfolioCurrencyMismatch(symbol: "VOD", holdingCurrency: "GBP", quoteCurrency: "GBp")]
            )
            #expect(result.partialFailure.missingQuoteSymbols.isEmpty)
        }

        @Test func missingQuoteIsReportedAndHasNoUpdateTime() async throws {
            let repository = repository(
                positions: [position(), position(symbol: "MSFT")],
                quotes: ["AAPL": quote()]
            )

            let result = try await repository.loadPortfolio(credentials: credentials)

            #expect(result.snapshot.holdings.count == 2)
            #expect(result.partialFailure.missingQuoteSymbols == ["MSFT"])
            #expect(result.snapshot.totalMarketValue == nil)
            #expect(result.snapshot.lastUpdated == nil)
        }

        @Test func priceRefreshReportsTheSameProblems() async throws {
            let repository = repository(positions: [], quotes: ["AAPL": quote(), "VOD": quote(currency: "GBp")])
            let snapshot = PortfolioSnapshot.make(
                accounts: [makeAccount()],
                holdings: [
                    makeHolding(symbol: "AAPL"),
                    makeHolding(symbol: "MSFT"),
                    makeHolding(symbol: "VOD", currencyCode: "GBP")
                ],
                lastUpdated: Date(timeIntervalSince1970: 1_000)
            )

            let result = try await repository.refreshPrices(for: snapshot)

            #expect(result.partialFailure.missingQuoteSymbols == ["MSFT"])
            #expect(result.partialFailure.currencyMismatches.map(\.symbol) == ["VOD"])
            #expect(result.snapshot.lastUpdated == nil)
        }

        @Test func dividendInAnotherCurrencyMakesDividendsUnknown() async throws {
            let activities = #"{"data":[{"symbol":{"symbol":"AAPL"},"amount":5,"currency":{"code":"USD"}},{"symbol":{"symbol":"AAPL"},"amount":7,"currency":{"code":"CAD"}}],"pagination":{"total":2}}"#
            let repository = repository(
                positions: [position()],
                quotes: ["AAPL": quote()],
                activities: activities
            )

            let result = try await repository.loadPortfolio(credentials: credentials)

            #expect(result.snapshot.holdings.first?.dividendsReceived == nil)
            #expect(result.snapshot.allTimeGainAmount == nil)
        }

        /// Losing the extended-hours quote is a partial failure, reported in
        /// the result next to the regular prices it leaves intact.
        @Test func extendedHoursFailureIsReportedWithRegularPrices() async throws {
            var fields = quote(price: 108.5)
            fields["subsessions"] = .null
            let repository = repository(
                positions: [position()],
                quotes: ["AAPL": fields],
                at: marketTime(day: 6, hour: 17, minute: 30)
            )

            let result = try await repository.loadPortfolio(credentials: credentials)
            let holding = try #require(result.snapshot.holdings.first)

            #expect(result.partialFailure.extendedHoursFailed)
            #expect(holding.currentPrice == 108.5)
            #expect(holding.postMarketChange == nil)
            #expect(try #require(result.partialFailure.message(hasMixedCurrencies: false)).contains("Extended-hours"))
        }

        @Test func positionsInTwoCurrenciesKeepEveryHoldingButNoTotal() async throws {
            let repository = repository(
                positions: [position(), position(symbol: "SHOP.TO", currency: "CAD")],
                quotes: ["AAPL": quote(), "SHOP.TO": quote(currency: "CAD")]
            )

            let result = try await repository.loadPortfolio(credentials: credentials)

            #expect(result.snapshot.holdings.count == 2)
            #expect(result.snapshot.hasMixedCurrencies)
            #expect(result.snapshot.totalMarketValue == nil)
            // Mixed isn't a failed price, so the update time still advances.
            #expect(result.snapshot.lastUpdated == now)
        }
    }
}
