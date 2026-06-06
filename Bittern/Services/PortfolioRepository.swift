//
//  PortfolioRepository.swift
//  Bittern
//

import Foundation

protocol PortfolioRepository {
    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioSnapshot
}

struct LivePortfolioRepository: PortfolioRepository {
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

            return PortfolioHolding(
                id: id,
                accountID: account.id,
                symbol: symbol,
                name: name,
                accountName: account.name,
                quantity: position.units,
                averageCost: averageCost,
                currentPrice: currentPrice,
                previousClose: previousClose,
                currencyCode: currencyCode
            )
        }

        return PortfolioSnapshot.make(
            accounts: accounts,
            holdings: holdings,
            lastUpdated: Date(),
            isDemo: false
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
