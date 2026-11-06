//
//  PortfolioRepository.swift
//  Bittern
//

import Foundation

/// Everything the features need from SnapTrade, Yahoo and Brandfetch. Views
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
    /// Holdings Yahoo returned no usable price for.
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
