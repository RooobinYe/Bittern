import Foundation
import Testing
@testable import Bittern

@Suite
struct PortfolioHoldingTests {
    @Test func derivesValuesFromPriceAndCost() {
        let holding = makeHolding(dividendsReceived: 5)

        #expect(holding.marketValue == 1_100)
        #expect(holding.costBasis == 1_000)
        #expect(holding.dayGainAmount == 50)
        #expect(holding.allTimeGainAmount == 100)
        #expect(holding.totalReturnAmount == 105)
    }

    @Test func missingPricePropagatesNil() {
        let holding = makeHolding(currentPrice: nil)

        #expect(holding.marketValue == nil)
        #expect(holding.dayGainAmount == nil)
        #expect(holding.allTimeGainAmount == nil)
        #expect(holding.totalReturnAmount == nil)
    }

    @Test func missingPreviousClosePropagatesNil() {
        let holding = makeHolding(previousClose: nil)

        #expect(holding.dayGainAmount == nil)
        #expect(holding.dayGainPercent == nil)
    }

    /// A zero cost is how brokers report "unknown" (for example after a
    /// transfer), not a free purchase: the whole value would read as profit.
    @Test func zeroCostIsUnknown() {
        let holding = makeHolding(averageCost: 0)

        #expect(holding.costBasis == nil)
        #expect(holding.allTimeGainAmount == nil)
        #expect(holding.allTimeGainPercent == nil)
        #expect(holding.totalReturnAmount == nil)
    }
}

@Suite
struct PortfolioSnapshotTests {
    @Test func sumsHoldingsInOneCurrency() {
        let snapshot = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [makeHolding(), makeHolding(symbol: "MSFT")]
        )

        #expect(snapshot.totalMarketValue == 2_200)
        #expect(snapshot.dayGainAmount == 100)
        #expect(snapshot.allTimeGainAmount == 200)
        #expect(!snapshot.hasMixedCurrencies)
        #expect(snapshot.currencyCode == "USD")
    }

    @Test func oneMissingPriceMakesTotalsUnknown() {
        let snapshot = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [makeHolding(), makeHolding(symbol: "MSFT", currentPrice: nil)]
        )

        #expect(snapshot.totalMarketValue == nil)
        #expect(snapshot.dayGainAmount == nil)
        #expect(snapshot.dayGainPercent == nil)
        #expect(snapshot.allTimeGainAmount == nil)
    }

    @Test func oneZeroCostMakesAllTimeTotalsUnknown() {
        let snapshot = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [makeHolding(), makeHolding(symbol: "MSFT", averageCost: 0)]
        )

        #expect(snapshot.totalMarketValue == 2_200)
        #expect(snapshot.allTimeGainAmount == nil)
        #expect(snapshot.allTimeGainPercent == nil)
    }

    @Test func mixedCurrenciesAreNeverSummed() {
        let snapshot = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [makeHolding(), makeHolding(symbol: "SHOP", currencyCode: "CAD")]
        )

        #expect(snapshot.hasMixedCurrencies)
        #expect(snapshot.holdings.count == 2)
        #expect(snapshot.totalMarketValue == nil)
        #expect(snapshot.dayGainAmount == nil)
        #expect(snapshot.dayGainPercent == nil)
        #expect(snapshot.allTimeGainAmount == nil)
        #expect(snapshot.allTimeGainPercent == nil)
    }

    /// Only holdings are summed, so an account's balance currency must not
    /// hide totals of holdings that all share one currency.
    @Test func accountBalanceCurrencyDoesNotCountAsMixed() {
        let snapshot = PortfolioSnapshot.make(
            accounts: [makeAccount(currencyCode: "CAD")],
            holdings: [makeHolding()]
        )

        #expect(!snapshot.hasMixedCurrencies)
        #expect(snapshot.totalMarketValue == 1_100)
    }

    @Test func noHoldingsHasNoTotalsRatherThanZero() {
        let snapshot = PortfolioSnapshot.make(accounts: [makeAccount()], holdings: [])

        #expect(snapshot.totalMarketValue == nil)
        #expect(snapshot.dayGainAmount == nil)
        #expect(snapshot.dayGainPercent == nil)
        #expect(snapshot.allTimeGainAmount == nil)
        #expect(snapshot.allTimeGainPercent == nil)
    }

    @Test func zeroPreviousValueHasNoPercentRatherThanZero() {
        let snapshot = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [
                makeHolding(quantity: 10, currentPrice: 110, previousClose: 105),
                makeHolding(symbol: "SHORT", quantity: -10, currentPrice: 105, previousClose: 105)
            ]
        )

        // Market value 50 minus day gain 50: nothing to measure a percent against.
        #expect(snapshot.dayGainAmount == 50)
        #expect(snapshot.dayGainPercent == nil)
    }
}

@Suite
struct PortfolioSnapshotPersistenceTests {
    /// A cache written before these rules holds a zero cost and a total built
    /// from it. Loading must not bring those numbers back.
    @Test func recomputingAppliesCurrentRulesToOldData() throws {
        let holding = makeHolding(averageCost: 0)
        let stale = PortfolioSnapshot(
            accounts: [makeAccount()],
            holdings: [holding],
            totalMarketValue: 1_100,
            dayGainAmount: 50,
            dayGainPercent: 0.05,
            allTimeGainAmount: 1_100,
            allTimeGainPercent: 0,
            currencyCode: "USD",
            hasMixedCurrencies: false,
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )

        let data = try JSONEncoder().encode(stale)
        let decoded = try JSONDecoder().decode(PortfolioSnapshot.self, from: data).recomputed()

        #expect(decoded.allTimeGainAmount == nil)
        #expect(decoded.totalMarketValue == 1_100)
        #expect(decoded.lastUpdated == Date(timeIntervalSince1970: 1_000))
    }

    @Test func partialSnapshotKeepsThePreviousUpdateTime() {
        let previous = PortfolioSnapshot.make(
            accounts: [],
            holdings: [makeHolding()],
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )
        let partial = PortfolioSnapshot.make(
            accounts: [],
            holdings: [makeHolding(currentPrice: nil)],
            lastUpdated: nil
        )

        #expect(partial.inheritingLastUpdated(from: previous).lastUpdated == previous.lastUpdated)
        #expect(partial.inheritingLastUpdated(from: nil).lastUpdated == nil)
        #expect(partial.unpricedSymbols == ["AAPL"])
    }
}

@Suite
struct LivePricingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(opensIn seconds: TimeInterval) -> HoldingMarketSession {
        HoldingMarketSession(
            start: now.addingTimeInterval(seconds),
            regularStart: now.addingTimeInterval(seconds + 19_800),
            regularEnd: now.addingTimeInterval(seconds + 43_200),
            end: now.addingTimeInterval(seconds + 57_600)
        )
    }

    @Test func cryptoAlwaysTradesAndStocksOnlyWithinTheirTradingDay() {
        let snapshot = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [
                makeHolding(symbol: "BTC", instrumentKind: .crypto),
                makeHolding(symbol: "OPEN", marketSession: session(opensIn: -60)),
                makeHolding(symbol: "LATER", marketSession: session(opensIn: 600)),
                makeHolding(symbol: "UNKNOWN")
            ]
        )

        #expect(snapshot.activeHoldings(at: now).map(\.symbol) == ["BTC", "OPEN"])
        #expect(snapshot.nextSessionStart(after: now) == now.addingTimeInterval(600))
    }

    /// Between post-market and the next pre-market a stock still trades
    /// overnight, so its price can move; it waits for the overnight session
    /// like for a trading day.
    @Test func theOvernightSessionKeepsAStockInSession() {
        var ended = session(opensIn: -60_000)
        ended.overnight = DateInterval(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(3_600))
        var endedLater = session(opensIn: -60_000)
        endedLater.overnight = DateInterval(start: now.addingTimeInterval(300), end: now.addingTimeInterval(3_600))
        let snapshot = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [
                makeHolding(symbol: "NIGHT", marketSession: ended),
                makeHolding(symbol: "SOON", marketSession: endedLater)
            ]
        )

        #expect(snapshot.activeHoldings(at: now).map(\.symbol) == ["NIGHT"])
        #expect(snapshot.nextSessionStart(after: now) == now.addingTimeInterval(300))
    }

    @Test func partOfThePortfolioTakesNewPricesAndTheRestKeepsTheirs() {
        let earlier = Date(timeIntervalSince1970: 1_000)
        let snapshot = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [makeHolding(symbol: "BTC", instrumentKind: .crypto), makeHolding(symbol: "AAPL")],
            lastUpdated: earlier
        )
        let btc = snapshot.holdings[0].repriced(
            currentPrice: 120,
            previousClose: 105,
            preMarketChange: nil,
            postMarketChange: nil,
            overnightChange: nil,
            marketSession: nil,
            regularPriceTime: now
        )

        let merged = snapshot.merging(prices: [btc], pricedAt: now)

        #expect(merged.holdings.map(\.currentPrice) == [120, 110])
        #expect(merged.holdings.map(\.symbol) == ["BTC", "AAPL"])
        #expect(merged.totalMarketValue == 2_300)
        #expect(merged.lastUpdated == now)

        // A missing price makes it incomplete: it keeps the last complete time.
        let unpriced = btc.repriced(
            currentPrice: nil,
            previousClose: nil,
            preMarketChange: nil,
            postMarketChange: nil,
            overnightChange: nil,
            marketSession: nil,
            regularPriceTime: nil
        )
        let incomplete = snapshot.merging(prices: [unpriced], pricedAt: nil)
        #expect(incomplete.lastUpdated == earlier)
        #expect(incomplete.totalMarketValue == nil)
    }
}
