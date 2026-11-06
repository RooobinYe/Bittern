//
//  LivePortfolioRepository+Connection.swift
//  Bittern
//
//  SnapTrade user registration, the brokerage connection portal and account
//  balance history.
//

import Foundation
import OSLog

extension LivePortfolioRepository {
    func portfolioHistory(
        credentials: SnapTradeCredentials,
        accountIDs: [String]
    ) async throws -> PortfolioHistory {
        let snapTrade = makeSnapTradeClient(credentials)
        let ids = accountIDs.isEmpty
            ? try await snapTrade.listAccounts().map(\.id)
            : accountIDs

        let histories = try await withThrowingTaskGroup(
            of: AccountBalanceHistory.self,
            returning: [AccountBalanceHistory].self
        ) { group in
            for id in ids {
                group.addTask {
                    try await snapTrade.accountBalanceHistory(accountID: id).accountBalanceHistory
                }
            }

            var histories: [AccountBalanceHistory] = []
            for try await history in group {
                histories.append(history)
            }
            return histories
        }

        return try PortfolioHistoryAggregator.aggregate(histories: histories)
    }

    /// The user ID is derived from the client ID, so one API key always
    /// registers under the same name.
    func registerUser(apiKey: SnapTradeCredentials) async throws -> SnapTradeCredentials {
        let apiKey = apiKey.sanitized
        let registered = try await makeSnapTradeClient(apiKey)
            .registerUser(userId: Self.userID(clientId: apiKey.clientId))
        AppLog.credentials.debug("SnapTrade user registered")
        return SnapTradeCredentials(
            clientId: apiKey.clientId,
            consumerKey: apiKey.consumerKey,
            userId: registered.userId,
            userSecret: registered.userSecret
        )
    }

    func connectionPortalURL(
        credentials: SnapTradeCredentials,
        darkMode: Bool
    ) async throws -> URL {
        try await makeSnapTradeClient(credentials).connectionPortalURL(darkMode: darkMode)
    }

    static func userID(clientId: String) -> String {
        let normalized = clientId.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return "bittern-personal-\(String(normalized))"
    }
}
