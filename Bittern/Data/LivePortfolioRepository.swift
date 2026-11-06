//
//  LivePortfolioRepository.swift
//  Bittern
//

import Foundation
import OSLog

/// The portfolio from SnapTrade, priced by Yahoo, with logos from Brandfetch.
/// Every client comes from outside, so tests and the app decide what it talks
/// to.
struct LivePortfolioRepository: PortfolioRepository {
    /// SnapTrade signs every request with the user's credentials, so a client
    /// exists per set of credentials.
    typealias SnapTradeClientFactory = (SnapTradeCredentials) -> SnapTradeClient

    let makeSnapTradeClient: SnapTradeClientFactory
    let yahoo: YahooFinanceClient
    let brandfetch: BrandfetchClient
    let currentDate: @Sendable () -> Date

    init(
        makeSnapTradeClient: @escaping SnapTradeClientFactory,
        yahoo: YahooFinanceClient,
        brandfetch: BrandfetchClient,
        currentDate: @escaping @Sendable () -> Date
    ) {
        self.makeSnapTradeClient = makeSnapTradeClient
        self.yahoo = yahoo
        self.brandfetch = brandfetch
        self.currentDate = currentDate
    }

    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult {
        AppLog.portfolio.debug(
            "Portfolio load started taskCancelled=\(Task.isCancelled, privacy: .public)"
        )
        let snapTrade = makeSnapTradeClient(credentials)

        let accounts = try await loadAccounts(from: snapTrade)
        let positions = try readablePositions(
            from: try await loadPositions(of: accounts, from: snapTrade)
        )

        let quoteRequests = positions.map {
            YahooQuoteRequest(symbol: $0.symbol, instrumentKind: $0.instrumentKind)
        }
        AppLog.portfolio.debug(
            "Loading quotes assets=\(quoteRequests.count, privacy: .public)"
        )
        let quoteBatch = quoteRequests.isEmpty
            ? YahooQuoteBatch.empty
            : try await yahoo.quotes(for: quoteRequests)
        let quotes = quoteBatch.quotes
        AppLog.portfolio.debug("Loaded quotes=\(quotes.count, privacy: .public)")

        let dividends = await loadDividendActivities(of: accounts, from: snapTrade)

        var mismatches: [PortfolioCurrencyMismatch] = []
        let holdings = positions.map { position -> PortfolioHolding in
            let account = position.account
            let symbol = position.symbol
            let priced = pricedValues(
                quote: quotes[symbol],
                symbol: symbol,
                currencyCode: position.currencyCode,
                quantity: position.units,
                mismatches: &mismatches
            )
            let logoURL = brandfetch.logoURL(for: symbol, kind: position.instrumentKind)
            AppLog.portfolio.debug(
                "Logo resolution symbol=\(symbol) resolvedKind=\(position.instrumentKind?.rawValue ?? "nil", privacy: .public) configured=\(brandfetch.isConfigured, privacy: .public) url=\(brandfetch.redactedDescription(for: logoURL))"
            )

            return PortfolioHolding(
                id: [account.id, position.dto.instrument?.id ?? symbol].joined(separator: "-"),
                accountID: account.id,
                symbol: symbol,
                name: position.dto.resolvedName ?? symbol,
                instrumentKind: position.instrumentKind,
                logoURL: logoURL,
                accountName: account.name,
                quantity: position.units,
                quantityDisplay: position.dto.unitsDisplay,
                averageCost: position.dto.resolvedAverageCost,
                currentPrice: priced.currentPrice,
                previousClose: priced.previousClose,
                preMarketChange: priced.preMarketChange,
                postMarketChange: priced.postMarketChange,
                currencyCode: position.currencyCode,
                dividendsReceived: dividends.activitiesByAccount[account.id].flatMap {
                    dividendAmount(for: symbol, currencyCode: position.currencyCode, activities: $0)
                }
            )
        }

        AppLog.portfolio.debug(
            "Portfolio load completed accounts=\(accounts.count, privacy: .public) holdings=\(holdings.count, privacy: .public) logos=\(holdings.lazy.filter { $0.logoURL != nil }.count, privacy: .public)"
        )
        return result(
            accounts: accounts,
            holdings: holdings,
            partialFailure: PortfolioLoadPartialFailure(
                dividendsFailed: dividends.didFailSomeAccounts,
                currencyMismatches: mismatches,
                extendedHoursFailed: quoteBatch.didFailExtendedHours
            )
        )
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult {
        let quoteRequests = snapshot.holdings.map {
            YahooQuoteRequest(symbol: $0.symbol, instrumentKind: $0.instrumentKind)
        }
        let symbols = Array(Set(quoteRequests.map { normalized($0.symbol) })).sorted()
        AppLog.portfolio.debug(
            "Price refresh started holdings=\(snapshot.holdings.count, privacy: .public) uniqueSymbols=\(symbols.count, privacy: .public) symbols=\(symbols.joined(separator: ",")) taskCancelled=\(Task.isCancelled, privacy: .public)"
        )

        let quoteBatch: YahooQuoteBatch
        do {
            quoteBatch = try await yahoo.quotes(for: quoteRequests)
        } catch {
            AppLog.portfolio.warning(
                "Price refresh quote request failed: \(AppLog.describe(error))"
            )
            throw error
        }
        let quotes = quoteBatch.quotes
        AppLog.portfolio.debug(
            "Price refresh quote summary succeeded=\(quotes.count, privacy: .public)/\(symbols.count, privacy: .public) missingSymbols=\(AppLog.list(symbols.filter { quotes[$0] == nil }))"
        )

        var mismatches: [PortfolioCurrencyMismatch] = []
        let holdings = snapshot.holdings.map { holding -> PortfolioHolding in
            let symbol = normalized(holding.symbol)
            let priced = pricedValues(
                quote: quotes[symbol],
                symbol: symbol,
                currencyCode: holding.currencyCode,
                quantity: holding.quantity,
                mismatches: &mismatches
            )
            AppLog.portfolio.debug(
                "Price refresh holding symbol=\(symbol) quoteFound=\(quotes[symbol] != nil, privacy: .public) oldPrice=\(AppLog.optional(holding.currentPrice)) newPrice=\(AppLog.optional(priced.currentPrice))"
            )
            return holding.repriced(
                currentPrice: priced.currentPrice,
                previousClose: priced.previousClose,
                preMarketChange: priced.preMarketChange,
                postMarketChange: priced.postMarketChange
            )
        }

        return result(
            accounts: snapshot.accounts,
            holdings: holdings,
            partialFailure: PortfolioLoadPartialFailure(
                currencyMismatches: mismatches,
                extendedHoursFailed: quoteBatch.didFailExtendedHours
            )
        )
    }

    func priceHistory(
        for holding: PortfolioHolding,
        range: HoldingChartRange
    ) async throws -> HoldingPriceSeries {
        try await yahoo.priceHistory(
            for: holding.symbol,
            instrumentKind: holding.instrumentKind,
            currencyCode: holding.currencyCode,
            range: range
        )
    }

    /// A snapshot and its partial failures. Only a snapshot where every
    /// holding has a price advances "Updated".
    private func result(
        accounts: [PortfolioAccount],
        holdings: [PortfolioHolding],
        partialFailure: PortfolioLoadPartialFailure
    ) -> PortfolioLoadResult {
        let unpricedSymbols = Set(holdings.filter { $0.currentPrice == nil }.map(\.symbol))
        var partialFailure = partialFailure
        partialFailure.missingQuoteSymbols = unpricedSymbols
            .subtracting(partialFailure.currencyMismatches.map(\.symbol))
            .sorted()

        return PortfolioLoadResult(
            snapshot: .make(
                accounts: accounts,
                holdings: holdings,
                lastUpdated: unpricedSymbols.isEmpty ? currentDate() : nil
            ),
            partialFailure: partialFailure
        )
    }

    /// The price fields of a holding, or none of them when the quote is absent
    /// or in another currency. The comparison is exact on purpose: Yahoo quotes
    /// London shares in pence as "GBp", which isn't "GBP".
    private func pricedValues(
        quote: YahooQuoteDTO?,
        symbol: String,
        currencyCode: String,
        quantity: Double,
        mismatches: inout [PortfolioCurrencyMismatch]
    ) -> PricedValues {
        guard let quote else { return .none }
        guard quote.currency == currencyCode else {
            let mismatch = PortfolioCurrencyMismatch(
                symbol: symbol,
                holdingCurrency: currencyCode,
                quoteCurrency: quote.currency
            )
            if !mismatches.contains(mismatch) {
                mismatches.append(mismatch)
            }
            return .none
        }

        return PricedValues(
            currentPrice: quote.regularMarketPrice.flatMap { $0 > 0 ? $0 : nil },
            previousClose: quote.regularMarketPreviousClose,
            preMarketChange: extendedHoursChange(quote: quote.preMarket, quantity: quantity),
            postMarketChange: extendedHoursChange(quote: quote.postMarket, quantity: quantity)
        )
    }

    private func extendedHoursChange(
        quote: YahooExtendedHoursQuoteDTO?,
        quantity: Double
    ) -> HoldingExtendedHoursChange? {
        guard let quote, quantity != 0, quote.regularClose > 0 else { return nil }

        let amount = quantity * (quote.price - quote.regularClose)
        return HoldingExtendedHoursChange(
            amount: amount,
            percent: amount / abs(quantity * quote.regularClose),
            observedAt: quote.observedAt,
            sessionStart: quote.sessionStart,
            sessionEnd: quote.sessionEnd
        )
    }

    func normalized(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

private struct PricedValues {
    let currentPrice: Double?
    let previousClose: Double?
    let preMarketChange: HoldingExtendedHoursChange?
    let postMarketChange: HoldingExtendedHoursChange?

    static let none = PricedValues(
        currentPrice: nil,
        previousClose: nil,
        preMarketChange: nil,
        postMarketChange: nil
    )
}
