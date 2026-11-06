//
//  PortfolioRepository.swift
//  Bittern
//

import Foundation
import OSLog

protocol PortfolioRepository {
    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult
    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult
}

struct PortfolioCurrencyMismatch: Equatable, Sendable {
    let symbol: String
    let holdingCurrency: String
    let quoteCurrency: String?
}

struct PortfolioLoadPartialFailure: Equatable, Sendable {
    var dividendsFailed = false
    /// Holdings Yahoo returned no usable price for.
    var missingQuoteSymbols: [String] = []
    /// Holdings whose price can't be used because it's in another currency.
    var currencyMismatches: [PortfolioCurrencyMismatch] = []

    /// What the user needs to know about data that loaded but isn't whole.
    func message(didFailExtendedHours: Bool, hasMixedCurrencies: Bool) -> String? {
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
        if didFailExtendedHours {
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

struct PortfolioExtendedHoursRefreshError: Error, Sendable {
    let regularSnapshot: PortfolioSnapshot
    let partialFailure: PortfolioLoadPartialFailure
}

struct LivePortfolioRepository: PortfolioRepository {
    private let dividendActivityTypes = ["DIVIDEND", "REI", "STOCK_DIVIDEND"]
    private let brandfetch = BrandfetchClient()
    private let session: URLSession
    private let currentDate: @Sendable () -> Date

    init(
        session: URLSession = .shared,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.currentDate = currentDate
    }

    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult {
        AppLog.portfolio.debug(
            "Portfolio load started taskCancelled=\(Task.isCancelled, privacy: .public)"
        )
        let snapTrade = SnapTradeClient(
            credentials: credentials,
            session: session,
            currentDate: currentDate
        )
        let yahoo = YahooFinanceClient(session: session, currentDate: currentDate)

        let accountSources = try await loadAccountSources(from: snapTrade)
        AppLog.portfolio.debug(
            "Portfolio load accountSources=\(accountSources.count, privacy: .public)"
        )
        let accounts = accountSources.map { source in
            let dto = source.account
            return PortfolioAccount(
                id: dto.id,
                name: dto.displayName,
                institutionName: source.connection?.displayName ?? dto.displayInstitution,
                providerLogoURL: source.connection?.logoURL,
                isConnectionDisabled: source.connection?.disabled == true,
                currencyCode: dto.balance?.total?.currency
            )
        }

        let positionsByAccount = try await withThrowingTaskGroup(
            of: (Int, [SnapTradePositionDTO]).self,
            returning: [(PortfolioAccount, SnapTradePositionDTO)].self
        ) { group in
            for (index, account) in accounts.enumerated() {
                group.addTask {
                    let positions = try await snapTrade.listPositions(accountID: account.id)
                    return (index, positions)
                }
            }

            var batches = Array<[SnapTradePositionDTO]?>(
                repeating: nil,
                count: accounts.count
            )
            var loadedPositionCount = 0
            for try await (index, positions) in group {
                batches[index] = positions
                loadedPositionCount += positions.count
                AppLog.portfolio.debug(
                    "Loaded positions batch=\(positions.count, privacy: .public) total=\(loadedPositionCount, privacy: .public)"
                )
            }

            return batches.enumerated().flatMap { index, positions in
                (positions ?? []).map { (accounts[index], $0) }
            }
        }

        let positions = try readablePositions(from: positionsByAccount)

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
        AppLog.portfolio.debug(
            "Loaded quotes=\(quotes.count, privacy: .public)"
        )
        let (dividendActivitiesByAccount, didFailSomeDividends) = await loadDividendActivitiesByAccount(
            accounts: accounts,
            snapTrade: snapTrade
        )
        AppLog.portfolio.debug(
            "Loaded dividend activity accounts=\(dividendActivitiesByAccount.count, privacy: .public)"
        )

        var mismatches: [PortfolioCurrencyMismatch] = []
        let holdings = positions.map { position -> PortfolioHolding in
            let account = position.account
            let symbol = position.symbol
            let currencyCode = position.currencyCode
            let priced = pricedValues(
                quote: quotes[symbol],
                symbol: symbol,
                currencyCode: currencyCode,
                quantity: position.units,
                mismatches: &mismatches
            )
            let logoURL = brandfetch.logoURL(for: symbol, kind: position.instrumentKind)
            AppLog.portfolio.debug(
                "Logo resolution symbol=\(symbol) resolvedKind=\(position.instrumentKind?.rawValue ?? "nil", privacy: .public) configured=\(brandfetch.isConfigured, privacy: .public) url=\(brandfetch.redactedDescription(for: logoURL))"
            )
            let id = [account.id, position.dto.instrument?.id ?? symbol]
                .joined(separator: "-")
            let dividendsReceived = dividendActivitiesByAccount[account.id].flatMap {
                dividendAmount(
                    for: symbol,
                    currencyCode: currencyCode,
                    activities: $0
                )
            }

            return PortfolioHolding(
                id: id,
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
                currencyCode: currencyCode,
                dividendsReceived: dividendsReceived
            )
        }

        let holdingsWithPreparedLogoURL = holdings.lazy.filter { $0.logoURL != nil }.count
        AppLog.portfolio.debug(
            "Portfolio logo summary configured=\(brandfetch.isConfigured, privacy: .public) urlsPrepared=\(holdingsWithPreparedLogoURL, privacy: .public)/\(holdings.count, privacy: .public)"
        )
        AppLog.portfolio.debug(
            "Portfolio load completed accounts=\(accounts.count, privacy: .public) holdings=\(holdings.count, privacy: .public)"
        )
        return try result(
            accounts: accounts,
            holdings: holdings,
            dividendsFailed: didFailSomeDividends,
            mismatches: mismatches,
            didFailExtendedHours: quoteBatch.didFailExtendedHours
        )
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult {
        let quoteRequests = snapshot.holdings.map {
            YahooQuoteRequest(
                symbol: $0.symbol,
                instrumentKind: $0.instrumentKind
            )
        }
        let normalizedSymbols = Array(Set(quoteRequests.map { normalized($0.symbol) })).sorted()
        AppLog.portfolio.debug(
            "Price refresh started holdings=\(snapshot.holdings.count, privacy: .public) uniqueSymbols=\(normalizedSymbols.count, privacy: .public) symbols=\(normalizedSymbols.joined(separator: ",")) taskCancelled=\(Task.isCancelled, privacy: .public)"
        )

        let quoteBatch: YahooQuoteBatch
        do {
            quoteBatch = try await YahooFinanceClient(
                session: session,
                currentDate: currentDate
            ).quotes(
                for: quoteRequests
            )
        } catch {
            AppLog.portfolio.warning(
                "Price refresh quote request failed: \(AppLog.describe(error))"
            )
            throw error
        }
        let quotes = quoteBatch.quotes

        let quoteSymbols = quotes.keys.sorted()
        let missingSymbols = normalizedSymbols.filter { quotes[$0] == nil }
        AppLog.portfolio.debug(
            "Price refresh quote summary succeeded=\(quoteSymbols.count, privacy: .public)/\(normalizedSymbols.count, privacy: .public) quoteSymbols=\(AppLog.list(quoteSymbols)) missingSymbols=\(AppLog.list(missingSymbols))"
        )

        var mismatches: [PortfolioCurrencyMismatch] = []
        let updatedHoldings = snapshot.holdings.map { holding -> PortfolioHolding in
            let symbol = normalized(holding.symbol)
            let priced = pricedValues(
                quote: quotes[symbol],
                symbol: symbol,
                currencyCode: holding.currencyCode,
                quantity: holding.quantity,
                mismatches: &mismatches
            )

            AppLog.portfolio.debug(
                "Price refresh holding symbol=\(symbol) quoteFound=\(quotes[symbol] != nil, privacy: .public) oldPrice=\(AppLog.optional(holding.currentPrice)) newPrice=\(AppLog.optional(priced.currentPrice)) oldPreviousClose=\(AppLog.optional(holding.previousClose)) newPreviousClose=\(AppLog.optional(priced.previousClose))"
            )

            return PortfolioHolding(
                id: holding.id,
                accountID: holding.accountID,
                symbol: holding.symbol,
                name: holding.name,
                instrumentKind: holding.instrumentKind,
                logoURL: holding.logoURL,
                accountName: holding.accountName,
                quantity: holding.quantity,
                quantityDisplay: holding.quantityDisplay,
                averageCost: holding.averageCost,
                currentPrice: priced.currentPrice,
                previousClose: priced.previousClose,
                preMarketChange: priced.preMarketChange,
                postMarketChange: priced.postMarketChange,
                currencyCode: holding.currencyCode,
                dividendsReceived: holding.dividendsReceived
            )
        }

        return try result(
            accounts: snapshot.accounts,
            holdings: updatedHoldings,
            dividendsFailed: false,
            mismatches: mismatches,
            didFailExtendedHours: quoteBatch.didFailExtendedHours
        )
    }

    /// Positions that can become holdings. Cash isn't a holding; anything else
    /// missing a symbol, quantity or currency fails the load, because leaving
    /// it out would quietly understate the portfolio.
    private func readablePositions(
        from positionsByAccount: [(PortfolioAccount, SnapTradePositionDTO)]
    ) throws -> [ReadablePosition] {
        var readable: [ReadablePosition] = []
        var unreadableCount = 0
        var unreadableAccounts: [String] = []

        for (account, position) in positionsByAccount where !position.isCash {
            guard let symbol = position.resolvedSymbol?.trimmedNonEmpty,
                  let units = position.units,
                  let currencyCode = position.resolvedCurrency?.trimmedNonEmpty
            else {
                unreadableCount += 1
                if !unreadableAccounts.contains(account.name) {
                    unreadableAccounts.append(account.name)
                }
                continue
            }

            readable.append(
                ReadablePosition(
                    account: account,
                    dto: position,
                    symbol: symbol.uppercased(),
                    units: units,
                    currencyCode: currencyCode.uppercased(),
                    instrumentKind: PortfolioInstrumentKind(
                        snapTradeValue: position.instrument?.kind
                    )
                )
            )
        }

        guard unreadableCount == 0 else {
            throw PortfolioDataError.unreadablePositions(
                count: unreadableCount,
                accountNames: unreadableAccounts
            )
        }
        return readable
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
            preMarketChange: preMarketChange(quote: quote, quantity: quantity),
            postMarketChange: postMarketChange(quote: quote, quantity: quantity)
        )
    }

    private func result(
        accounts: [PortfolioAccount],
        holdings: [PortfolioHolding],
        dividendsFailed: Bool,
        mismatches: [PortfolioCurrencyMismatch],
        didFailExtendedHours: Bool
    ) throws -> PortfolioLoadResult {
        let unpricedSymbols = Set(
            holdings.filter { $0.currentPrice == nil }.map(\.symbol)
        )
        let snapshot = PortfolioSnapshot.make(
            accounts: accounts,
            holdings: holdings,
            lastUpdated: unpricedSymbols.isEmpty ? currentDate() : nil
        )
        let partialFailure = PortfolioLoadPartialFailure(
            dividendsFailed: dividendsFailed,
            missingQuoteSymbols: unpricedSymbols
                .subtracting(mismatches.map(\.symbol))
                .sorted(),
            currencyMismatches: mismatches
        )
        guard !didFailExtendedHours else {
            throw PortfolioExtendedHoursRefreshError(
                regularSnapshot: snapshot,
                partialFailure: partialFailure
            )
        }
        return PortfolioLoadResult(snapshot: snapshot, partialFailure: partialFailure)
    }

    private func preMarketChange(
        quote: YahooQuoteDTO?,
        quantity: Double
    ) -> HoldingExtendedHoursChange? {
        extendedHoursChange(quote: quote?.preMarket, quantity: quantity)
    }

    private func postMarketChange(
        quote: YahooQuoteDTO?,
        quantity: Double
    ) -> HoldingExtendedHoursChange? {
        extendedHoursChange(quote: quote?.postMarket, quantity: quantity)
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

    // Account data must be complete or absent: a partial account list would
    // commit (and cache) an understated portfolio total. Per-connection
    // failures therefore propagate and fail the whole load; only a
    // listConnections failure may fall back to the flat account list, which
    // SnapTrade documents as returning every account for the user.
    private func loadAccountSources(
        from snapTrade: SnapTradeClient
    ) async throws -> [AccountSource] {
        AppLog.portfolio.debug(
            "Account source load started taskCancelled=\(Task.isCancelled, privacy: .public)"
        )
        let connections: [SnapTradeConnectionDTO]
        do {
            connections = try await snapTrade.listConnections()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.portfolio.warning(
                "Connection listing failed; trying flat account fallback: \(AppLog.describe(error))"
            )
            let accounts = try await snapTrade.listAccounts().map {
                AccountSource(account: $0, connection: nil)
            }
            AppLog.portfolio.debug(
                "Account source fallback after failure accounts=\(accounts.count, privacy: .public)"
            )
            return accounts
        }

        AppLog.portfolio.debug(
            "Account source connections=\(connections.count, privacy: .public)"
        )
        guard !connections.isEmpty else {
            let accounts = try await snapTrade.listAccounts().map {
                AccountSource(account: $0, connection: nil)
            }
            AppLog.portfolio.debug(
                "Account source fallback accounts=\(accounts.count, privacy: .public)"
            )
            return accounts
        }

        return try await withThrowingTaskGroup(
            of: [AccountSource].self,
            returning: [AccountSource].self
        ) { group in
            for connection in connections {
                group.addTask {
                    do {
                        let accounts = try await snapTrade.listAccounts(connectionID: connection.id)
                        return accounts.map { AccountSource(account: $0, connection: connection) }
                    } catch {
                        AppLog.portfolio.warning(
                            "Account load failed connection=\(connection.id): \(AppLog.describe(error))"
                        )
                        throw error
                    }
                }
            }

            var sources: [AccountSource] = []
            for try await batch in group {
                sources.append(contentsOf: batch)
                AppLog.portfolio.debug(
                    "Account sources collected batch=\(batch.count, privacy: .public) total=\(sources.count, privacy: .public)"
                )
            }
            return sources
        }
    }

    private func loadDividendActivitiesByAccount(
        accounts: [PortfolioAccount],
        snapTrade: SnapTradeClient
    ) async -> (activities: [String: [SnapTradeActivityDTO]], didFailSomeAccounts: Bool) {
        AppLog.portfolio.debug(
            "Dividend activity load started accounts=\(accounts.count, privacy: .public) taskCancelled=\(Task.isCancelled, privacy: .public)"
        )
        return await withTaskGroup(
            of: (accountID: String, activities: [SnapTradeActivityDTO]?).self,
            returning: ([String: [SnapTradeActivityDTO]], Bool).self
        ) { group in
            for account in accounts {
                group.addTask { [dividendActivityTypes] in
                    do {
                        let activities = try await snapTrade.listActivities(
                            accountID: account.id,
                            types: dividendActivityTypes
                        )
                        return (account.id, activities)
                    } catch {
                        AppLog.portfolio.warning(
                            "Dividend activity load failed account=\(account.id): \(AppLog.describe(error))"
                        )
                        return (account.id, nil)
                    }
                }
            }

            var result: [String: [SnapTradeActivityDTO]] = [:]
            var didFailSomeAccounts = false
            for await (accountID, activities) in group {
                guard let activities else {
                    didFailSomeAccounts = true
                    continue
                }
                result[accountID] = activities
                AppLog.portfolio.debug(
                    "Dividend activities collected accountActivities=\(activities.count, privacy: .public) accountCount=\(result.count, privacy: .public)"
                )
            }
            return (result, didFailSomeAccounts)
        }
    }

    /// Dividends received for a symbol, or nil if some were paid in another
    /// currency: they can't be added, and leaving them out would understate
    /// the return.
    private func dividendAmount(
        for symbol: String,
        currencyCode: String,
        activities: [SnapTradeActivityDTO]
    ) -> Double? {
        let normalizedSymbol = normalized(symbol)
        let normalizedCurrencyCode = currencyCode.uppercased()

        var total = 0.0
        for activity in activities {
            guard let activitySymbol = activity.resolvedSymbol.map(normalized),
                  activitySymbol == normalizedSymbol,
                  let amount = activity.amount
            else {
                continue
            }

            if let activityCurrency = activity.currencyCode?.uppercased(),
               activityCurrency != normalizedCurrencyCode {
                return nil
            }

            total += max(amount, 0)
        }
        return total
    }

    private func normalized(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

}

private struct AccountSource {
    let account: SnapTradeAccountDTO
    let connection: SnapTradeConnectionDTO?
}

private struct ReadablePosition {
    let account: PortfolioAccount
    let dto: SnapTradePositionDTO
    let symbol: String
    let units: Double
    let currencyCode: String
    let instrumentKind: PortfolioInstrumentKind?
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

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
