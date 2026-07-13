//
//  PortfolioRepository.swift
//  Bittern
//

import Foundation
import OSLog

protocol PortfolioRepository {
    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioSnapshot
    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot
}

struct LivePortfolioRepository: PortfolioRepository {
    private let dividendActivityTypes = ["DIVIDEND", "REI", "STOCK_DIVIDEND"]
    private let brandfetch = BrandfetchClient()

    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioSnapshot {
        AppLog.portfolio.debug(
            "Portfolio load started taskCancelled=\(Task.isCancelled, privacy: .public)"
        )
        let snapTrade = SnapTradeClient(credentials: credentials)
        let yahoo = YahooFinanceClient()

        let accountSources = try await loadAccountSources(from: snapTrade)
        AppLog.portfolio.debug(
            "Portfolio load accountSources=\(accountSources.count, privacy: .public)"
        )
        let accounts = accountSources.map { source in
            let dto = source.account
            return PortfolioAccount(
                id: dto.id,
                connectionID: source.connection?.id ?? dto.brokerageAuthorizationID,
                name: dto.displayName,
                institutionName: source.connection?.displayName ?? dto.displayInstitution,
                providerLogoURL: source.connection?.logoURL,
                isConnectionDisabled: source.connection?.disabled == true,
                totalBalance: dto.balance?.total?.amount,
                currencyCode: dto.balance?.total?.currency ?? "USD"
            )
        }

        var positionsByAccount: [(PortfolioAccount, SnapTradePositionDTO)] = []
        for account in accounts {
            AppLog.portfolio.debug(
                "Loading positions currentCount=\(positionsByAccount.count, privacy: .public)"
            )
            let positions = try await snapTrade.listPositions(accountID: account.id)
            positionsByAccount.append(contentsOf: positions.map { (account, $0) })
            AppLog.portfolio.debug(
                "Loaded positions batch=\(positions.count, privacy: .public) total=\(positionsByAccount.count, privacy: .public)"
            )
        }

        let quoteRequests = positionsByAccount.compactMap { _, position -> YahooQuoteRequest? in
            guard let symbol = position.resolvedSymbol else { return nil }
            return YahooQuoteRequest(
                symbol: symbol,
                instrumentKind: PortfolioInstrumentKind(
                    snapTradeValue: position.instrument?.kind
                )
            )
        }
        AppLog.portfolio.debug(
            "Loading quotes assets=\(quoteRequests.count, privacy: .public)"
        )

        let quotes = (try? await yahoo.quotes(for: quoteRequests)) ?? [:]
        AppLog.portfolio.debug(
            "Loaded quotes=\(quotes.count, privacy: .public)"
        )
        let dividendActivitiesByAccount = await loadDividendActivitiesByAccount(
            accounts: accounts,
            snapTrade: snapTrade
        )
        AppLog.portfolio.debug(
            "Loaded dividend activity accounts=\(dividendActivitiesByAccount.count, privacy: .public)"
        )

        let holdings = positionsByAccount.compactMap { account, position -> PortfolioHolding? in
            guard let rawSymbol = position.resolvedSymbol?.trimmedNonEmpty else {
                return nil
            }
            guard let units = position.units else {
                return nil
            }

            let symbol = rawSymbol.uppercased()
            let quote = quotes[symbol]
            let currentPrice = quote?.regularMarketPrice.flatMap { $0 > 0 ? $0 : nil }
            let previousClose = quote?.regularMarketPreviousClose
            let averageCost = position.resolvedAverageCost
            let currencyCode = position.resolvedCurrency ?? account.currencyCode
            let name = position.resolvedName ?? symbol
            let instrumentKind = PortfolioInstrumentKind(
                snapTradeValue: position.instrument?.kind
            )
            let logoURL = brandfetch.logoURL(for: symbol, kind: instrumentKind)
            AppLog.portfolio.debug(
                "Logo resolution symbol=\(symbol) snapTradeKind=\(position.instrument?.kind ?? "nil", privacy: .public) resolvedKind=\(instrumentKind?.rawValue ?? "nil", privacy: .public) configured=\(brandfetch.isConfigured, privacy: .public) url=\(brandfetch.redactedDescription(for: logoURL))"
            )
            let id = [account.id, position.id ?? position.instrument?.id ?? symbol]
                .joined(separator: "-")
            let dividendsReceived = dividendActivitiesByAccount[account.id].map {
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
                name: name,
                instrumentKind: instrumentKind,
                logoURL: logoURL,
                accountName: account.name,
                quantity: units,
                quantityDisplay: position.unitsDisplay,
                averageCost: averageCost,
                currentPrice: currentPrice,
                previousClose: previousClose,
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
        return PortfolioSnapshot.make(
            accounts: accounts,
            holdings: holdings,
            lastUpdated: Date(),
            isDemo: false
        )
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot {
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

        let quotes: [String: YahooQuoteDTO]
        do {
            quotes = try await YahooFinanceClient().quotes(for: quoteRequests)
        } catch {
            AppLog.portfolio.warning(
                "Price refresh quote request failed: \(AppLog.describe(error))"
            )
            quotes = [:]
        }

        let quoteSymbols = quotes.keys.sorted()
        let missingSymbols = normalizedSymbols.filter { quotes[$0] == nil }
        AppLog.portfolio.debug(
            "Price refresh quote summary succeeded=\(quoteSymbols.count, privacy: .public)/\(normalizedSymbols.count, privacy: .public) quoteSymbols=\(AppLog.list(quoteSymbols)) missingSymbols=\(AppLog.list(missingSymbols))"
        )

        let updatedHoldings = snapshot.holdings.map { holding -> PortfolioHolding in
            let symbol = normalized(holding.symbol)
            let quote = quotes[symbol]
            let currentPrice = quote?.regularMarketPrice.flatMap { $0 > 0 ? $0 : nil }
            let previousClose = quote?.regularMarketPreviousClose

            AppLog.portfolio.debug(
                "Price refresh holding symbol=\(symbol) quoteFound=\(quote != nil, privacy: .public) oldPrice=\(AppLog.optional(holding.currentPrice)) newPrice=\(AppLog.optional(currentPrice)) oldPreviousClose=\(AppLog.optional(holding.previousClose)) newPreviousClose=\(AppLog.optional(previousClose))"
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
                currentPrice: currentPrice,
                previousClose: previousClose,
                currencyCode: holding.currencyCode,
                dividendsReceived: holding.dividendsReceived
            )
        }

        return PortfolioSnapshot.make(
            accounts: snapshot.accounts,
            holdings: updatedHoldings,
            lastUpdated: Date(),
            isDemo: snapshot.isDemo
        )
    }

    private func loadAccountSources(from snapTrade: SnapTradeClient) async throws -> [AccountSource] {
        AppLog.portfolio.debug(
            "Account source load started taskCancelled=\(Task.isCancelled, privacy: .public)"
        )
        do {
            let connections = try await snapTrade.listConnections()
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
                        if let accounts = try? await snapTrade.listAccounts(connectionID: connection.id) {
                            return accounts.map { AccountSource(account: $0, connection: connection) }
                        }
                        return []
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
        } catch {
            AppLog.portfolio.warning(
                "Account source primary path failed; trying fallback: \(AppLog.describe(error))"
            )
            let accounts = try await snapTrade.listAccounts().map {
                AccountSource(account: $0, connection: nil)
            }
            AppLog.portfolio.debug(
                "Account source fallback after failure accounts=\(accounts.count, privacy: .public)"
            )
            return accounts
        }
    }

    private func loadDividendActivitiesByAccount(
        accounts: [PortfolioAccount],
        snapTrade: SnapTradeClient
    ) async -> [String: [SnapTradeActivityDTO]] {
        AppLog.portfolio.debug(
            "Dividend activity load started accounts=\(accounts.count, privacy: .public) taskCancelled=\(Task.isCancelled, privacy: .public)"
        )
        return await withTaskGroup(
            of: (String, [SnapTradeActivityDTO])?.self,
            returning: [String: [SnapTradeActivityDTO]].self
        ) { group in
            for account in accounts {
                group.addTask { [dividendActivityTypes] in
                    if let activities = try? await snapTrade.listActivities(
                        accountID: account.id,
                        types: []
                    ) {
                        let filtered = activities.filter { activity in
                            guard let type = activity.type?.uppercased() else { return false }
                            return dividendActivityTypes.contains(type)
                        }
                        return (account.id, filtered)
                    }
                    return nil
                }
            }

            var result: [String: [SnapTradeActivityDTO]] = [:]
            for await pair in group {
                if let (accountID, activities) = pair {
                    result[accountID] = activities
                    AppLog.portfolio.debug(
                        "Dividend activities collected accountActivities=\(activities.count, privacy: .public) accountCount=\(result.count, privacy: .public)"
                    )
                }
            }
            return result
        }
    }

    private func dividendAmount(
        for symbol: String,
        currencyCode: String,
        activities: [SnapTradeActivityDTO]
    ) -> Double {
        let normalizedSymbol = normalized(symbol)
        let normalizedCurrencyCode = currencyCode.uppercased()

        return activities.reduce(0) { total, activity in
            guard let activitySymbol = activity.resolvedSymbol.map(normalized),
                  activitySymbol == normalizedSymbol,
                  let amount = activity.amount
            else {
                return total
            }

            if let activityCurrency = activity.currency?.uppercased(),
               activityCurrency != normalizedCurrencyCode {
                return total
            }

            return total + max(amount, 0)
        }
    }

    private func normalized(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

}

private struct AccountSource {
    let account: SnapTradeAccountDTO
    let connection: SnapTradeConnectionDTO?
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
