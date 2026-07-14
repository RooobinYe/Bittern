//
//  DashboardViewModel.swift
//  Bittern
//

import Foundation
import Combine
import OSLog

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
    @Published private(set) var isLoading = false

    private let credentialsStore: CredentialsStore
    private let repository: PortfolioRepository
    private var bootstrapTask: Task<Void, Never>?
    private var cacheLoadFlight: CacheLoadFlight?
    private var refreshFlight: RefreshFlight?
    private var nextFlightID: UInt64 = 0
    private var didLoadCache = false
    private var cacheWasHit = false
    private var didBootstrap = false
    private var hasPortfolioBaseline: Bool
    private var baselineCredentials: SnapTradeCredentials?

    private enum RefreshKind: Int {
        case price
        case full

        var logName: String {
            switch self {
            case .price: "price"
            case .full: "full"
            }
        }
    }

    private struct CacheLoadFlight {
        let id: UInt64
        let task: Task<PortfolioSnapshot?, Never>
    }

    private struct RefreshFlight {
        let id: UInt64
        let kind: RefreshKind
        let credentials: SnapTradeCredentials
        let task: Task<Void, Never>
    }

    init(
        credentialsStore: CredentialsStore,
        repository: PortfolioRepository? = nil,
        initialSnapshot: PortfolioSnapshot? = nil
    ) {
        self.credentialsStore = credentialsStore
        self.repository = repository ?? LivePortfolioRepository()
        snapshot = initialSnapshot ?? .emptyLive
        hasPortfolioBaseline = initialSnapshot != nil
        baselineCredentials = initialSnapshot == nil
            ? nil
            : credentialsStore.credentials?.sanitized
        didLoadCache = initialSnapshot != nil
        cacheWasHit = initialSnapshot != nil

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

    /// Loads the cached snapshot once, then performs the appropriate initial
    /// network load. Concurrent callers share this bootstrap task.
    func bootstrap() async {
        if didBootstrap {
            return
        }

        if let bootstrapTask {
            await bootstrapTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performBootstrap()
        }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
        didBootstrap = true
    }

    func refresh() async {
        guard didBootstrap else {
            await bootstrap()
            return
        }

        await requestRefresh(.price)
    }

    func fullRefresh() async {
        _ = await ensureCacheLoaded()
        await requestRefresh(.full)
    }

    private func performBootstrap() async {
        let foundCachedSnapshot = await ensureCacheLoaded()
        await requestRefresh(foundCachedSnapshot ? .price : .full)
    }

    /// Serializes the one-time cache read ahead of every network load so a late
    /// cache result can never overwrite a fresh network snapshot.
    private func ensureCacheLoaded() async -> Bool {
        if didLoadCache {
            return cacheWasHit
        }

        if let cacheLoadFlight {
            let cachedSnapshot = await cacheLoadFlight.task.value
            completeCacheLoad(
                cachedSnapshot,
                flightID: cacheLoadFlight.id
            )
            return cacheWasHit
        }

        let flightID = makeFlightID()
        let task = Task { await PortfolioCache.loadAsync() }
        let flight = CacheLoadFlight(id: flightID, task: task)
        cacheLoadFlight = flight

        let cachedSnapshot = await task.value
        completeCacheLoad(cachedSnapshot, flightID: flightID)
        return cacheWasHit
    }

    private func completeCacheLoad(
        _ cachedSnapshot: PortfolioSnapshot?,
        flightID: UInt64
    ) {
        guard !didLoadCache, cacheLoadFlight?.id == flightID else {
            return
        }

        if let cachedSnapshot {
            snapshot = cachedSnapshot
            cacheWasHit = true
            hasPortfolioBaseline = true
            baselineCredentials = credentialsStore.credentials?.sanitized
            AppLog.portfolio.debug(
                "Bootstrap loaded cached snapshot accounts=\(cachedSnapshot.accounts.count, privacy: .public) holdings=\(cachedSnapshot.holdings.count, privacy: .public)"
            )
        } else {
            AppLog.portfolio.debug("Bootstrap cache miss")
        }

        didLoadCache = true
        cacheLoadFlight = nil
    }

    /// Runs at most one logical network load at a time. A full refresh satisfies
    /// a price request, while a full request cancels and supersedes a price load.
    private func requestRefresh(_ requestedKind: RefreshKind) async {
        guard let credentials = credentialsStore.credentials?.sanitized,
              credentials.isComplete else {
            resetForMissingCredentials()
            return
        }

        var effectiveKind = requestedKind
        if requestedKind == .price
            && (!hasPortfolioBaseline || baselineCredentials != credentials) {
            effectiveKind = .full
            AppLog.portfolio.debug(
                "Price refresh promoted to full refresh because no matching portfolio baseline exists"
            )
        }

        if effectiveKind == .price && snapshot.holdings.isEmpty {
            errorMessage = nil
            AppLog.portfolio.debug(
                "Price refresh skipped because the loaded portfolio has no holdings"
            )
            return
        }

        if let current = refreshFlight {
            let credentialsMatch = current.credentials == credentials
            let currentSatisfiesRequest = credentialsMatch
                && current.kind.rawValue >= effectiveKind.rawValue

            if currentSatisfiesRequest {
                AppLog.portfolio.debug(
                    "Refresh joined in-flight task current=\(current.kind.logName, privacy: .public) requested=\(effectiveKind.logName, privacy: .public) flight=\(current.id, privacy: .public)"
                )
                await awaitFlight(current, satisfying: effectiveKind)
                return
            }

            if !credentialsMatch {
                effectiveKind = .full
            }

            AppLog.portfolio.debug(
                "Refresh superseding in-flight task current=\(current.kind.logName, privacy: .public) requested=\(effectiveKind.logName, privacy: .public) flight=\(current.id, privacy: .public)"
            )
            current.task.cancel()
        }

        let flight = startRefresh(effectiveKind, credentials: credentials)
        await awaitFlight(flight, satisfying: effectiveKind)
    }

    private func startRefresh(
        _ kind: RefreshKind,
        credentials: SnapTradeCredentials
    ) -> RefreshFlight {
        let flightID = makeFlightID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performRefresh(kind, credentials: credentials, flightID: flightID)
            finishRefresh(flightID: flightID)
        }
        let flight = RefreshFlight(
            id: flightID,
            kind: kind,
            credentials: credentials,
            task: task
        )

        refreshFlight = flight
        errorMessage = nil
        isLoading = true
        AppLog.portfolio.debug(
            "Refresh started kind=\(kind.logName, privacy: .public) flight=\(flightID, privacy: .public)"
        )
        return flight
    }

    private func performRefresh(
        _ kind: RefreshKind,
        credentials: SnapTradeCredentials,
        flightID: UInt64
    ) async {
        guard canCommit(flightID: flightID, credentials: credentials) else {
            return
        }

        do {
            let newSnapshot: PortfolioSnapshot
            switch kind {
            case .price:
                let baseSnapshot = snapshot
                newSnapshot = try await repository.refreshPrices(for: baseSnapshot)
            case .full:
                newSnapshot = try await repository.loadPortfolio(credentials: credentials)
            }

            guard canCommit(flightID: flightID, credentials: credentials) else {
                AppLog.portfolio.debug(
                    "Refresh discarded stale result kind=\(kind.logName, privacy: .public) flight=\(flightID, privacy: .public)"
                )
                return
            }

            snapshot = newSnapshot
            hasPortfolioBaseline = true
            baselineCredentials = credentials
            if kind == .full,
               let selectedProviderName,
               !newSnapshot.accounts.contains(where: { $0.providerName == selectedProviderName }) {
                self.selectedProviderName = nil
            }
            PortfolioCache.save(newSnapshot)
            AppLog.portfolio.debug(
                "Refresh saved snapshot kind=\(kind.logName, privacy: .public) flight=\(flightID, privacy: .public) accounts=\(newSnapshot.accounts.count, privacy: .public) holdings=\(newSnapshot.holdings.count, privacy: .public)"
            )
        } catch {
            guard canCommit(flightID: flightID, credentials: credentials) else {
                return
            }
            errorMessage = error.localizedDescription
            AppLog.portfolio.error(
                "Refresh failed kind=\(kind.logName, privacy: .public) flight=\(flightID, privacy: .public): \(AppLog.describe(error))"
            )
        }
    }

    /// If the task was superseded, keep the original caller waiting for the
    /// replacement full refresh that now satisfies its request.
    private func awaitFlight(
        _ initialFlight: RefreshFlight,
        satisfying requestedKind: RefreshKind
    ) async {
        var awaitedFlight = initialFlight

        while true {
            await awaitedFlight.task.value
            guard awaitedFlight.task.isCancelled,
                  let replacement = refreshFlight,
                  replacement.id != awaitedFlight.id,
                  replacement.kind.rawValue >= requestedKind.rawValue else {
                return
            }
            awaitedFlight = replacement
        }
    }

    private func canCommit(
        flightID: UInt64,
        credentials: SnapTradeCredentials
    ) -> Bool {
        !Task.isCancelled
            && refreshFlight?.id == flightID
            && credentialsStore.credentials?.sanitized == credentials
    }

    private func finishRefresh(flightID: UInt64) {
        guard refreshFlight?.id == flightID else {
            return
        }
        refreshFlight = nil
        isLoading = false
    }

    private func resetForMissingCredentials() {
        if let refreshFlight {
            refreshFlight.task.cancel()
            self.refreshFlight = nil
        }
        snapshot = .emptyLive
        selectedProviderName = nil
        errorMessage = nil
        hasPortfolioBaseline = false
        baselineCredentials = nil
        isLoading = false
        AppLog.portfolio.debug(
            "Refresh skipped and current flight invalidated because credentials are incomplete"
        )
    }

    private func makeFlightID() -> UInt64 {
        nextFlightID &+= 1
        return nextFlightID
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
