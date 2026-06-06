//
//  DashboardViewModel.swift
//  Bittern
//

import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var snapshot: PortfolioSnapshot = .emptyLive
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var performanceMode: PerformanceMode = .today
    @Published var sortOption: HoldingSortOption = .marketValue
    @Published var selectedProviderName: String?

    private let credentialsStore: CredentialsStore
    private let repository: PortfolioRepository
    private var hasAttemptedDividendBackfill = false

    init(
        credentialsStore: CredentialsStore,
        repository: PortfolioRepository? = nil
    ) {
        self.credentialsStore = credentialsStore
        self.repository = repository ?? LivePortfolioRepository()
        snapshot = PortfolioCache.load() ?? .emptyLive
    }

    var sortedHoldings: [PortfolioHolding] {
        visibleSnapshot.holdings.sorted { lhs, rhs in
            switch sortOption {
            case .gainAmount:
                lhs.performanceAmount(for: performanceMode) > rhs.performanceAmount(for: performanceMode)
            case .lossAmount:
                lhs.performanceAmount(for: performanceMode) < rhs.performanceAmount(for: performanceMode)
            case .percent:
                lhs.performancePercent(for: performanceMode) > rhs.performancePercent(for: performanceMode)
            case .marketValue:
                lhs.marketValue > rhs.marketValue
            }
        }
    }

    var visibleSnapshot: PortfolioSnapshot {
        guard let selectedProviderName else {
            return snapshot
        }

        let accounts = snapshot.accounts.filter { $0.providerName == selectedProviderName }
        let accountIDs = Set(accounts.map(\.id))
        let holdings = snapshot.holdings.filter { accountIDs.contains($0.accountID) }

        if accounts.isEmpty {
            return snapshot
        }

        return PortfolioSnapshot.make(
            accounts: accounts,
            holdings: holdings,
            lastUpdated: snapshot.lastUpdated,
            isDemo: snapshot.isDemo
        )
    }

    func refresh() async {
        // Prevent overlapping refreshes — the first caller wins.
        guard !isLoading else { return }

        // No credentials: nothing to refresh.
        guard let credentials = credentialsStore.credentials, credentials.isComplete else {
            snapshot = .emptyLive
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let needsDividendBackfill = !hasAttemptedDividendBackfill
                && snapshot.holdings.contains { $0.dividendsReceived == nil }
            hasAttemptedDividendBackfill = hasAttemptedDividendBackfill || needsDividendBackfill

            let newSnapshot = needsDividendBackfill
                ? try await repository.loadPortfolio(credentials: credentials)
                : try await repository.refreshPrices(for: snapshot)
            snapshot = newSnapshot
            PortfolioCache.save(newSnapshot)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func fullRefresh() async {
        guard let credentials = credentialsStore.credentials, credentials.isComplete else {
            snapshot = .emptyLive
            errorMessage = nil
            return
        }

        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            let newSnapshot = try await repository.loadPortfolio(credentials: credentials)
            snapshot = newSnapshot
            if let selectedProviderName,
               !newSnapshot.accounts.contains(where: { $0.providerName == selectedProviderName }) {
                self.selectedProviderName = nil
            }
            PortfolioCache.save(newSnapshot)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
