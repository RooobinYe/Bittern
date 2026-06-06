//
//  PortfolioRepository.swift
//  Bittern
//

import Foundation

protocol PortfolioRepository {
    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioSnapshot
    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot
}

struct LivePortfolioRepository: PortfolioRepository {
    private let dividendActivityTypes = ["DIVIDEND", "REI", "STOCK_DIVIDEND"]

    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioSnapshot {
        let snapTrade = SnapTradeClient(credentials: credentials)
        let yahoo = YahooFinanceClient()

        let accountSources = try await loadAccountSources(from: snapTrade)
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
            let positions = try await snapTrade.listPositions(accountID: account.id)
            positionsByAccount.append(contentsOf: positions.map { (account, $0) })
        }

        let symbols = positionsByAccount.compactMap { _, position in
            position.resolvedSymbol
        }

        let quotes = (try? await yahoo.quotes(for: symbols)) ?? [:]
        let dividendActivitiesByAccount = await loadDividendActivitiesByAccount(
            accounts: accounts,
            snapTrade: snapTrade
        )

        let holdings = positionsByAccount.compactMap { account, position -> PortfolioHolding? in
            guard let rawSymbol = position.resolvedSymbol?.trimmedNonEmpty else {
                return nil
            }

            let symbol = rawSymbol.uppercased()
            let quote = quotes[symbol]
            let currentPrice = quote?.regularMarketPrice ?? position.price ?? position.resolvedAverageCost ?? 0
            let previousClose = quote?.regularMarketPreviousClose
                ?? quote?.regularMarketChange.map { currentPrice - $0 }
                ?? position.price
                ?? currentPrice
            let averageCost = position.resolvedAverageCost ?? currentPrice
            let currencyCode = quote?.currency ?? position.resolvedCurrency ?? account.currencyCode
            let name = quote?.displayName ?? position.resolvedName ?? symbol
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
                accountName: account.name,
                quantity: position.units,
                quantityDisplay: position.unitsDisplay,
                averageCost: averageCost,
                currentPrice: currentPrice,
                previousClose: previousClose,
                currencyCode: currencyCode,
                dividendsReceived: dividendsReceived
            )
        }

        return PortfolioSnapshot.make(
            accounts: accounts,
            holdings: holdings,
            lastUpdated: Date(),
            isDemo: false
        )
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot {
        let symbols = snapshot.holdings.map(\.symbol)
        let quotes = (try? await YahooFinanceClient().quotes(for: symbols)) ?? [:]

        let updatedHoldings = snapshot.holdings.map { holding -> PortfolioHolding in
            let symbol = holding.symbol.uppercased()
            guard let quote = quotes[symbol] else { return holding }

            guard let currentPrice = quote.regularMarketPrice, currentPrice > 0 else {
                return holding
            }
            let previousClose = quote.regularMarketPreviousClose
                ?? quote.regularMarketChange.map { currentPrice - $0 }
                ?? holding.previousClose

            return PortfolioHolding(
                id: holding.id,
                accountID: holding.accountID,
                symbol: holding.symbol,
                name: quote.displayName ?? holding.name,
                accountName: holding.accountName,
                quantity: holding.quantity,
                quantityDisplay: holding.quantityDisplay,
                averageCost: holding.averageCost,
                currentPrice: currentPrice,
                previousClose: previousClose,
                currencyCode: quote.currency ?? holding.currencyCode,
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
        do {
            let connections = try await snapTrade.listConnections()
            guard !connections.isEmpty else {
                return try await snapTrade.listAccounts().map {
                    AccountSource(account: $0, connection: nil)
                }
            }

            var sources: [AccountSource] = []
            for connection in connections {
                let accounts = try await snapTrade.listAccounts(connectionID: connection.id)
                sources.append(contentsOf: accounts.map {
                    AccountSource(account: $0, connection: connection)
                })
            }
            return sources
        } catch {
            return try await snapTrade.listAccounts().map {
                AccountSource(account: $0, connection: nil)
            }
        }
    }

    private func loadDividendActivitiesByAccount(
        accounts: [PortfolioAccount],
        snapTrade: SnapTradeClient
    ) async -> [String: [SnapTradeActivityDTO]] {
        var result: [String: [SnapTradeActivityDTO]] = [:]

        for account in accounts {
            if let activities = try? await snapTrade.listActivities(
                accountID: account.id,
                types: []
            ) {
                result[account.id] = activities.filter { activity in
                    guard let type = activity.type?.uppercased() else { return false }
                    return dividendActivityTypes.contains(type)
                }
            }
        }

        return result
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
