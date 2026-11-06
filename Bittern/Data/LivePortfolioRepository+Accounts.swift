//
//  LivePortfolioRepository+Accounts.swift
//  Bittern
//
//  Accounts, positions and dividends from SnapTrade.
//

import Foundation
import OSLog

struct ReadablePosition {
    let account: PortfolioAccount
    let dto: SnapTradePositionDTO
    let symbol: String
    let units: Double
    let currencyCode: String
    let instrumentKind: PortfolioInstrumentKind?
}

struct DividendActivities {
    let activitiesByAccount: [String: [SnapTradeActivityDTO]]
    let didFailSomeAccounts: Bool
}

private struct AccountSource {
    let account: SnapTradeAccountDTO
    let connection: SnapTradeConnectionDTO?
}

extension LivePortfolioRepository {
    private static let dividendActivityTypes = ["DIVIDEND", "REI", "STOCK_DIVIDEND"]

    func loadAccounts(from snapTrade: SnapTradeClient) async throws -> [PortfolioAccount] {
        let sources = try await loadAccountSources(from: snapTrade)
        AppLog.portfolio.debug(
            "Portfolio load accountSources=\(sources.count, privacy: .public)"
        )
        return sources.map { source in
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
    }

    /// Every account's positions, in account order. One failed account fails
    /// the load: a partial list would commit an understated total.
    func loadPositions(
        of accounts: [PortfolioAccount],
        from snapTrade: SnapTradeClient
    ) async throws -> [(PortfolioAccount, SnapTradePositionDTO)] {
        try await withThrowingTaskGroup(
            of: (Int, [SnapTradePositionDTO]).self,
            returning: [(PortfolioAccount, SnapTradePositionDTO)].self
        ) { group in
            for (index, account) in accounts.enumerated() {
                group.addTask {
                    (index, try await snapTrade.listPositions(accountID: account.id))
                }
            }

            var batches = [[SnapTradePositionDTO]?](repeating: nil, count: accounts.count)
            for try await (index, positions) in group {
                batches[index] = positions
                AppLog.portfolio.debug(
                    "Loaded positions batch=\(positions.count, privacy: .public)"
                )
            }

            return batches.enumerated().flatMap { index, positions in
                (positions ?? []).map { (accounts[index], $0) }
            }
        }
    }

    /// Positions that can become holdings. Cash isn't a holding; anything else
    /// missing a symbol, quantity or currency fails the load, because leaving
    /// it out would quietly understate the portfolio.
    func readablePositions(
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
                    instrumentKind: position.instrument?.portfolioKind
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

    /// Dividend activity per account. Unlike positions, a failed account only
    /// leaves its dividends unknown.
    func loadDividendActivities(
        of accounts: [PortfolioAccount],
        from snapTrade: SnapTradeClient
    ) async -> DividendActivities {
        await withTaskGroup(
            of: (accountID: String, activities: [SnapTradeActivityDTO]?).self,
            returning: DividendActivities.self
        ) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let activities = try await snapTrade.listActivities(
                            accountID: account.id,
                            types: Self.dividendActivityTypes
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
            }
            return DividendActivities(
                activitiesByAccount: result,
                didFailSomeAccounts: didFailSomeAccounts
            )
        }
    }

    /// Dividends received for a symbol, or nil if some were paid in another
    /// currency: they can't be added, and leaving them out would understate
    /// the return.
    func dividendAmount(
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

    // Account data must be complete or absent: a partial account list would
    // commit (and cache) an understated portfolio total. Per-connection
    // failures therefore propagate and fail the whole load; only a
    // listConnections failure may fall back to the flat account list, which
    // SnapTrade documents as returning every account for the user.
    private func loadAccountSources(
        from snapTrade: SnapTradeClient
    ) async throws -> [AccountSource] {
        let connections: [SnapTradeConnectionDTO]
        do {
            connections = try await snapTrade.listConnections()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.portfolio.warning(
                "Connection listing failed; trying flat account fallback: \(AppLog.describe(error))"
            )
            return try await snapTrade.listAccounts().map {
                AccountSource(account: $0, connection: nil)
            }
        }

        AppLog.portfolio.debug(
            "Account source connections=\(connections.count, privacy: .public)"
        )
        guard !connections.isEmpty else {
            return try await snapTrade.listAccounts().map {
                AccountSource(account: $0, connection: nil)
            }
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
            }
            return sources
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
