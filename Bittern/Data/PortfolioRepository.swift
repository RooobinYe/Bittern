//
//  PortfolioRepository.swift
//  Bittern
//

import Foundation

/// Everything the features need from SnapTrade, TradingView and Brandfetch. Views
/// and models talk to this instead of creating clients.
protocol PortfolioRepository {
    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult
    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult
    func priceHistory(for holding: PortfolioHolding, range: HoldingChartRange) async throws -> HoldingPriceSeries
    /// The combined balance history of `accountIDs`, or of every account the
    /// user has when there are none.
    func portfolioHistory(credentials: SnapTradeCredentials, accountIDs: [String]) async throws -> PortfolioHistory
    /// Registers this device's SnapTrade user for `apiKey` and returns the
    /// complete credentials.
    func registerUser(apiKey: SnapTradeCredentials) async throws -> SnapTradeCredentials
    func connectionPortalURL(credentials: SnapTradeCredentials, darkMode: Bool) async throws -> URL

    /// The server market data comes through.
    var marketDataServer: TradingViewServer { get }
    /// Tests `server` on a connection of its own, leaving the one in use
    /// alone.
    func checkMarketDataServer(_ server: TradingViewServer) async throws -> TradingViewServerCheck
    /// Sends market data through `server` from now on.
    func useMarketDataServer(_ server: TradingViewServer) async
    /// Whether the Market Data Connection is live: the server has been heard
    /// from lately. Opens nothing.
    func isMarketDataConnected() async -> Bool
}

/// Repositories without live market data, such as previews and the demo,
/// stay on TradingView and can't test a server. They have no connection to
/// lose: a network path is all their prices need.
extension PortfolioRepository {
    var marketDataServer: TradingViewServer { .tradingView }

    func checkMarketDataServer(_ server: TradingViewServer) async throws -> TradingViewServerCheck {
        throw URLError(.notConnectedToInternet)
    }

    func useMarketDataServer(_ server: TradingViewServer) async {}

    func isMarketDataConnected() async -> Bool { true }
}

struct PortfolioCurrencyMismatch: Equatable, Sendable {
    let symbol: String
    let holdingCurrency: String
    let quoteCurrency: String?
}

/// What loaded but isn't whole. A load with partial failures still returns
/// its snapshot; only a load with nothing usable throws.
struct PortfolioLoadPartialFailure: Equatable, Sendable {
    var dividendsFailed = false
    /// Holdings the market data provider returned no usable price for.
    var missingQuoteSymbols: [String] = []
    /// Holdings whose price can't be used because it's in another currency.
    var currencyMismatches: [PortfolioCurrencyMismatch] = []
    /// Extended-hours quotes couldn't be refreshed; regular prices are fine.
    var extendedHoursFailed = false

    /// What the user needs to know about data that loaded but isn't whole.
    func message(hasMixedCurrencies: Bool) -> String? {
        var parts: [String] = []
        if !missingQuoteSymbols.isEmpty {
            parts.append(
                "No price for \(missingQuoteSymbols.joined(separator: ", ")), so totals aren’t shown."
            )
        }
        for mismatch in currencyMismatches {
            parts.append(
                "\(mismatch.symbol) is held in \(mismatch.holdingCurrency) but quoted in \(mismatch.quoteCurrency ?? "an unknown currency"), so its price isn’t shown."
            )
        }
        if hasMixedCurrencies {
            parts.append("Holdings use more than one currency, so totals aren’t shown.")
        }
        if dividendsFailed {
            parts.append("Some dividend data couldn’t be loaded.")
        }
        if extendedHoursFailed {
            parts.append("Extended-hours data couldn’t be refreshed. Regular prices are still available.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

enum PortfolioDataError: LocalizedError, Equatable {
    case unreadablePositions(count: Int, accountNames: [String])

    var errorDescription: String? {
        switch self {
        case .unreadablePositions(let count, let accountNames):
            let subject = count == 1 ? "1 position" : "\(count) positions"
            return "\(subject) in \(accountNames.joined(separator: ", ")) came back without a symbol, quantity or currency, so the portfolio can’t be shown completely."
        }
    }
}

struct PortfolioLoadResult: Sendable {
    let snapshot: PortfolioSnapshot
    let partialFailure: PortfolioLoadPartialFailure
}
