//
//  DashboardViewModel.swift
//  Bittern
//

import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var snapshot: PortfolioSnapshot = .emptyLive
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
    private let refreshRunner = CancelableTaskRunner()
    private let fullRefreshRunner = CancelableTaskRunner()

    /// `true` while either a price refresh or a full portfolio reload is in flight.
    var isLoading: Bool { refreshRunner.isRunning || fullRefreshRunner.isRunning }

    init(
        credentialsStore: CredentialsStore,
        repository: PortfolioRepository? = nil,
        initialSnapshot: PortfolioSnapshot? = nil
    ) {
        self.credentialsStore = credentialsStore
        self.repository = repository ?? LivePortfolioRepository()
        refreshRunner.onStateChanged = { [weak self] in self?.objectWillChange.send() }
        fullRefreshRunner.onStateChanged = { [weak self] in self?.objectWillChange.send() }
        snapshot = initialSnapshot ?? .emptyLive
        if initialSnapshot == nil {
            Task {
                if let cached = await PortfolioCache.loadAsync() {
                    snapshot = cached
                    await refresh()
                }
            }
        }

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
                isOrdered(lhs.marketValue, before: rhs.marketValue, ascending: false)
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
        await refreshRunner.run { [weak self] gen in
            guard let self else { return }

            debugLog(
                "refresh requested isLoading=\(isLoading) holdings=\(snapshot.holdings.count) hasCompleteCredentials=\(credentialsStore.credentials?.isComplete == true) taskCancelled=\(Task.isCancelled) existingError=\(errorMessage ?? "nil")"
            )

            // No credentials: nothing to refresh.
            guard credentialsStore.credentials?.isComplete == true else {
                snapshot = .emptyLive
                errorMessage = nil
                debugLog("refresh skipped because credentials are incomplete")
                return
            }

            guard !snapshot.holdings.isEmpty else {
                errorMessage = nil
                debugLog("refresh skipped because snapshot has no holdings")
                return
            }

            errorMessage = nil
            debugLog("refresh started price refresh")

            do {
                let newSnapshot = try await repository.refreshPrices(for: snapshot)
                guard gen == refreshRunner.generation else { return }
                snapshot = newSnapshot
                PortfolioCache.save(newSnapshot)
                debugLog("refresh saved updated snapshot holdings=\(newSnapshot.holdings.count)")
            } catch {
                guard gen == refreshRunner.generation else { return }
                errorMessage = error.localizedDescription
                debugLog("refresh failed \(debugDescription(for: error))")
            }
        }
    }

    func fullRefresh() async {
        await fullRefreshRunner.run { [weak self] gen in
            guard let self else { return }

            debugLog(
                "fullRefresh requested isLoading=\(isLoading) hasCompleteCredentials=\(credentialsStore.credentials?.isComplete == true) taskCancelled=\(Task.isCancelled) existingError=\(errorMessage ?? "nil")"
            )

            guard let credentials = credentialsStore.credentials, credentials.isComplete else {
                snapshot = .emptyLive
                errorMessage = nil
                debugLog("fullRefresh skipped because credentials are incomplete")
                return
            }

            errorMessage = nil
            debugLog("fullRefresh started portfolio load")

            do {
                let newSnapshot = try await repository.loadPortfolio(credentials: credentials)
                // Discard stale results when a newer refresh has already started.
                guard gen == fullRefreshRunner.generation else { return }
                snapshot = newSnapshot
                if let selectedProviderName,
                   !newSnapshot.accounts.contains(where: { $0.providerName == selectedProviderName }) {
                    self.selectedProviderName = nil
                }
                PortfolioCache.save(newSnapshot)
                debugLog("fullRefresh saved new snapshot accounts=\(newSnapshot.accounts.count) holdings=\(newSnapshot.holdings.count)")
            } catch {
                guard gen == fullRefreshRunner.generation else { return }
                errorMessage = error.localizedDescription
                debugLog("fullRefresh failed \(debugDescription(for: error))")
            }
        }
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

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[DashboardViewModel] \(message)")
        #endif
    }

    private func debugDescription(for error: Error) -> String {
        let nsError = error as NSError
        return "type=\(type(of: error)) domain=\(nsError.domain) code=\(nsError.code) taskCancelled=\(Task.isCancelled) message=\"\(error.localizedDescription)\""
    }
}
