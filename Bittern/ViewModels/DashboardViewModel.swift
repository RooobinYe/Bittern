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
    @Published var performanceMode: PerformanceMode = .today {
        didSet {
            UserDefaults.standard.set(performanceMode.rawValue, forKey: AppSettingKey.performanceMode)
        }
    }
    @Published var sortOption: HoldingSortOption = .marketValue {
        didSet {
            UserDefaults.standard.set(sortOption.rawValue, forKey: AppSettingKey.sortOption)
        }
    }
    @Published var selectedProviderName: String?

    private let credentialsStore: CredentialsStore
    private let repository: PortfolioRepository
    private var hasAttemptedDividendBackfill = false
    private var shouldReloadPositionsOnNextRefresh = true

    init(
        credentialsStore: CredentialsStore,
        repository: PortfolioRepository? = nil
    ) {
        self.credentialsStore = credentialsStore
        self.repository = repository ?? LivePortfolioRepository()
        snapshot = PortfolioCache.load() ?? .emptyLive

        if let rawMode = UserDefaults.standard.string(forKey: AppSettingKey.performanceMode),
           let mode = PerformanceMode(rawValue: rawMode) {
            performanceMode = mode
        }

        if let rawSort = UserDefaults.standard.string(forKey: AppSettingKey.sortOption),
           let sort = HoldingSortOption(rawValue: rawSort) {
            sortOption = sort
        }
    }

    var sortedHoldings: [PortfolioHolding] {
        visibleSnapshot.holdings.sorted { lhs, rhs in
            switch sortOption {
            case .gainAmount:
                isOrdered(lhs.performanceAmount(for: performanceMode), before: rhs.performanceAmount(for: performanceMode), ascending: false)
            case .lossAmount:
                isOrdered(lhs.performanceAmount(for: performanceMode), before: rhs.performanceAmount(for: performanceMode), ascending: true)
            case .percent:
                isOrdered(lhs.performancePercent(for: performanceMode), before: rhs.performancePercent(for: performanceMode), ascending: false)
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
            let shouldReloadPositions = shouldReloadPositionsOnNextRefresh || needsDividendBackfill

            let newSnapshot = shouldReloadPositions
                ? try await repository.loadPortfolio(credentials: credentials)
                : try await repository.refreshPrices(for: snapshot)
            shouldReloadPositionsOnNextRefresh = false
            hasAttemptedDividendBackfill = hasAttemptedDividendBackfill || needsDividendBackfill
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
            shouldReloadPositionsOnNextRefresh = false
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

    private func isOrdered(_ lhs: Double?, before rhs: Double?, ascending: Bool) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return ascending ? lhs < rhs : lhs > rhs
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return false
        }
    }
}
