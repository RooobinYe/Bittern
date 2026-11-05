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
            lastUpdated: Date(timeIntervalSince1970: 1_000),
            isDemo: false
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
