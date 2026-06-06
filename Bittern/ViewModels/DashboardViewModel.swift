//
//  DashboardViewModel.swift
//  Bittern
//

import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var snapshot: PortfolioSnapshot = DemoPortfolio.snapshot
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var performanceMode: PerformanceMode = .today
    @Published var sortOption: HoldingSortOption = .marketValue
    @Published var selectedProviderName: String?

    private let credentialsStore: CredentialsStore
    private let repository: PortfolioRepository

    init(
        credentialsStore: CredentialsStore,
        repository: PortfolioRepository? = nil
    ) {
        self.credentialsStore = credentialsStore
        self.repository = repository ?? LivePortfolioRepository()
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
        guard let credentials = credentialsStore.credentials, credentials.isComplete else {
            snapshot = DemoPortfolio.snapshot
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            snapshot = try await repository.loadPortfolio(credentials: credentials)
            if let selectedProviderName,
               !snapshot.accounts.contains(where: { $0.providerName == selectedProviderName }) {
                self.selectedProviderName = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            snapshot = PortfolioSnapshot.emptyLive
        }

        isLoading = false
    }
}
