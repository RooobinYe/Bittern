//
//  PortfolioHistoryModel.swift
//  Bittern
//

import Foundation
import Observation

@MainActor
@Observable
final class PortfolioHistoryModel {
    var selectedRange: PortfolioHistoryRange = .fiveDays
    var selectedPoint: PortfolioHistoryPoint?
    var errorMessage: String?
    private(set) var history: PortfolioHistory?
    private(set) var isLoading = false

    /// Pull to refresh and the view's task can overlap; only the latest load
    /// may show its result.
    @ObservationIgnored private var latestLoadID = 0

    var visibleSeries: [PortfolioHistoryPoint] {
        selectedRange.points(in: history?.points ?? [])
    }

    func load(
        credentials: SnapTradeCredentials?,
        accountIDs: [String],
        using repository: any PortfolioRepository
    ) async {
        latestLoadID += 1
        let loadID = latestLoadID

        guard let credentials = credentials?.sanitized, credentials.isComplete else {
            history = nil
            errorMessage = "Connect your SnapTrade account before opening portfolio history."
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            if loadID == latestLoadID {
                isLoading = false
            }
        }

        do {
            let history = try await repository.portfolioHistory(
                credentials: credentials,
                accountIDs: accountIDs
            )
            guard loadID == latestLoadID, !Task.isCancelled else { return }
            self.history = history
        } catch {
            guard loadID == latestLoadID, !Task.isCancelled else { return }
            history = nil
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "Account history couldn’t be loaded. Please try again."
            )
        }
    }
}
