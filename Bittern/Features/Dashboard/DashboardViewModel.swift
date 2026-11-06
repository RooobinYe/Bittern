//
//  DashboardViewModel.swift
//  Bittern
//

import Foundation
import Observation
import OSLog

/// Whether there is portfolio data to show, kept apart from an empty portfolio
/// so that no data is never displayed as a value of zero.
enum PortfolioLoadState {
    /// Nothing to show and nothing on the way: no credentials yet.
    case notLoaded
    /// The first load is in flight, with nothing to show meanwhile.
    case loading
    /// Data is showing; a refresh of it reports through `isLoading`.
    case loaded(PortfolioSnapshot)
    /// The load failed with nothing to fall back on.
    case failed(String)

    var snapshot: PortfolioSnapshot? {
        guard case .loaded(let snapshot) = self else { return nil }
        return snapshot
    }
}

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var loadState: PortfolioLoadState
    var errorMessage: String?
    var performanceMode: PerformanceMode {
        didSet { defaults.set(performanceMode.rawValue, forKey: AppSettingKey.performanceMode) }
    }
    var sortOption: HoldingSortOption {
        didSet { defaults.set(sortOption.rawValue, forKey: AppSettingKey.sortOption) }
    }
    var selectedProviderName: String?
    /// Holdings worth less than this are hidden everywhere. The only copy of
    /// the setting; the views bind to it.
    var minPriceThreshold: Double {
        didSet { defaults.set(minPriceThreshold, forKey: AppSettingKey.minPriceThreshold) }
    }
    private(set) var isLoading = false

    private let credentialsStore: CredentialsStore
    private let repository: any PortfolioRepository
    private let defaults: UserDefaults
    private let loadCachedSnapshot: @Sendable () async -> PortfolioSnapshot?
    private let saveCachedSnapshot: @Sendable (PortfolioSnapshot) -> Void

    @ObservationIgnored private var bootstrapState = BootstrapState.notStarted
    @ObservationIgnored private var cacheState = CacheState.unread
    @ObservationIgnored private var refreshFlight: RefreshFlight?
    @ObservationIgnored private var nextFlightID: UInt64 = 0
    /// The credentials the shown snapshot was loaded with. A price refresh
    /// only makes sense on a snapshot of the current credentials.
    @ObservationIgnored private var snapshotCredentials: SnapTradeCredentials?

    private enum BootstrapState {
        case notStarted
        case running(Task<Void, Never>)
        case finished
    }

    private enum CacheState {
        case unread
        case reading(Task<PortfolioSnapshot?, Never>)
        case read
    }

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

    private struct RefreshFlight {
        let id: UInt64
        let kind: RefreshKind
        let credentials: SnapTradeCredentials
        let task: Task<Void, Never>
    }

    init(
        credentialsStore: CredentialsStore,
        repository: any PortfolioRepository,
        defaults: UserDefaults = .standard,
        initialSnapshot: PortfolioSnapshot? = nil,
        loadCachedSnapshot: @escaping @Sendable () async -> PortfolioSnapshot? = {
            await PortfolioCache.loadAsync()
        },
        saveCachedSnapshot: @escaping @Sendable (PortfolioSnapshot) -> Void = {
            PortfolioCache.save($0)
        }
    ) {
        self.credentialsStore = credentialsStore
        self.repository = repository
        self.defaults = defaults
        self.loadCachedSnapshot = loadCachedSnapshot
        self.saveCachedSnapshot = saveCachedSnapshot

        performanceMode = defaults.string(forKey: AppSettingKey.performanceMode)
            .flatMap(PerformanceMode.init(rawValue:)) ?? .today
        sortOption = defaults.string(forKey: AppSettingKey.sortOption)
            .flatMap(HoldingSortOption.init(rawValue:)) ?? .marketValue
        minPriceThreshold = defaults.object(forKey: AppSettingKey.minPriceThreshold) as? Double ?? 1.0

        if let initialSnapshot {
            loadState = .loaded(initialSnapshot)
            cacheState = .read
            snapshotCredentials = credentialsStore.credentials?.sanitized
        } else {
            loadState = credentialsStore.credentials?.sanitized.isComplete == true
                ? .loading
                : .notLoaded
        }
    }

    // MARK: - What the dashboard shows

    var snapshot: PortfolioSnapshot? {
        loadState.snapshot
    }

    /// The currency for amounts that aren't portfolio data, such as the minimum
    /// market value setting, which exists before any portfolio has loaded.
    var displayCurrencyCode: String {
        visibleSnapshot?.currencyCode ?? "USD"
    }

    /// The selected provider's part of the portfolio.
    var visibleSnapshot: PortfolioSnapshot? {
        snapshot?.filtered(toProvider: selectedProviderName)
    }

    /// `visibleSnapshot` without the holdings under the minimum market value,
    /// with totals recomputed. Every dashboard surface reads this one pass.
    var displaySnapshot: PortfolioSnapshot? {
        visibleSnapshot?.filtered(minimumMarketValue: minPriceThreshold)
    }

    var sortedHoldings: [PortfolioHolding] {
        sortOption.sorted(displaySnapshot?.holdings ?? [], by: performanceMode)
    }

    /// Holdings across every account (no provider filter) with the minimum
    /// market value applied.
    var thresholdFilteredHoldings: [PortfolioHolding] {
        (snapshot?.holdings ?? []).filter { $0.meetsMinimumMarketValue(minPriceThreshold) }
    }

    // MARK: - Loading

    /// Reads the cache once, then loads from the network. Concurrent callers
    /// share one bootstrap.
    func bootstrap() async {
        switch bootstrapState {
        case .finished:
            return
        case .running(let task):
            await task.value
        case .notStarted:
            let task = Task {
                await loadCacheOnce()
                await requestRefresh(.price)
            }
            bootstrapState = .running(task)
            await task.value
            bootstrapState = .finished
        }
    }

    /// New prices for the holdings already shown. Before the first load this
    /// is the first load.
    func refresh() async {
        guard case .finished = bootstrapState else {
            await bootstrap()
            return
        }
        await requestRefresh(.price)
    }

    /// Accounts, positions and prices from scratch.
    func fullRefresh() async {
        await loadCacheOnce()
        await requestRefresh(.full)
    }

    /// The cached snapshot is read before any network load starts, so a late
    /// cache read can never overwrite fresh data.
    private func loadCacheOnce() async {
        let task: Task<PortfolioSnapshot?, Never>
        switch cacheState {
        case .read:
            return
        case .reading(let reading):
            task = reading
        case .unread:
            task = Task { [loadCachedSnapshot] in await loadCachedSnapshot() }
            cacheState = .reading(task)
        }

        let cachedSnapshot = await task.value
        guard case .reading = cacheState else { return }
        cacheState = .read

        guard let cachedSnapshot else {
            AppLog.portfolio.debug("Bootstrap cache miss")
            return
        }
        // The cache may predate today's rules for what counts as known.
        loadState = .loaded(cachedSnapshot.recomputed())
        snapshotCredentials = credentialsStore.credentials?.sanitized
        AppLog.portfolio.debug(
            "Bootstrap loaded cached snapshot accounts=\(cachedSnapshot.accounts.count, privacy: .public) holdings=\(cachedSnapshot.holdings.count, privacy: .public)"
        )
    }

    /// Runs at most one network load at a time. A request that an in-flight
    /// load already covers joins it; any other request cancels and replaces
    /// it. A price refresh without a snapshot of the current credentials
    /// becomes a full one.
    private func requestRefresh(_ requestedKind: RefreshKind) async {
        guard let credentials = credentialsStore.credentials?.sanitized,
              credentials.isComplete
        else {
            resetForMissingCredentials()
            return
        }

        var kind = requestedKind
        if kind == .price && snapshotCredentials != credentials {
            kind = .full
        }

        if kind == .price && snapshot?.holdings.isEmpty != false {
            errorMessage = nil
            AppLog.portfolio.debug(
                "Price refresh skipped because the loaded portfolio has no holdings"
            )
            return
        }

        if let current = refreshFlight {
            if current.credentials == credentials, current.kind.rawValue >= kind.rawValue {
                AppLog.portfolio.debug(
                    "Refresh joined in-flight task current=\(current.kind.logName, privacy: .public) requested=\(kind.logName, privacy: .public) flight=\(current.id, privacy: .public)"
                )
                await awaitFlight(current, satisfying: kind)
                return
            }

            if current.credentials != credentials {
                kind = .full
            }
            AppLog.portfolio.debug(
                "Refresh superseding in-flight task current=\(current.kind.logName, privacy: .public) requested=\(kind.logName, privacy: .public) flight=\(current.id, privacy: .public)"
            )
            current.task.cancel()
        }

        await awaitFlight(startRefresh(kind, credentials: credentials), satisfying: kind)
    }

    private func startRefresh(
        _ kind: RefreshKind,
        credentials: SnapTradeCredentials
    ) -> RefreshFlight {
        nextFlightID &+= 1
        let flightID = nextFlightID
        let task = Task {
            await performRefresh(kind, credentials: credentials, flightID: flightID)
            finishRefresh(flightID: flightID)
        }
        let flight = RefreshFlight(id: flightID, kind: kind, credentials: credentials, task: task)

        refreshFlight = flight
        errorMessage = nil
        isLoading = true
        if snapshot == nil {
            loadState = .loading
        }
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
        // Replaced before it began: there is nothing to ask the network.
        guard canCommit(flightID: flightID, credentials: credentials) else { return }

        let result: PortfolioLoadResult
        do {
            switch kind {
            case .price:
                guard let snapshot else { return }
                result = try await repository.refreshPrices(for: snapshot)
            case .full:
                result = try await repository.loadPortfolio(credentials: credentials)
            }
        } catch {
            guard canCommit(flightID: flightID, credentials: credentials) else { return }
            if snapshot == nil {
                loadState = .failed(
                    UserFacingError.message(
                        for: error,
                        fallback: "Portfolio couldn’t be loaded. Please try again."
                    )
                )
            } else {
                errorMessage = UserFacingError.message(
                    for: error,
                    fallback: "Portfolio couldn’t be refreshed. Your existing data is still available."
                )
            }
            AppLog.portfolio.error(
                "Refresh failed kind=\(kind.logName, privacy: .public) flight=\(flightID, privacy: .public): \(AppLog.describe(error))"
            )
            return
        }

        guard canCommit(flightID: flightID, credentials: credentials) else {
            AppLog.portfolio.debug(
                "Refresh discarded stale result kind=\(kind.logName, privacy: .public) flight=\(flightID, privacy: .public)"
            )
            return
        }

        let newSnapshot = result.snapshot.inheritingLastUpdated(from: snapshot)
        loadState = .loaded(newSnapshot)
        snapshotCredentials = credentials
        if let selectedProviderName,
           !newSnapshot.accounts.contains(where: { $0.providerName == selectedProviderName }) {
            self.selectedProviderName = nil
        }
        // A snapshot with holes shows what's known for now, but the next
        // launch should fall back on the last complete one.
        if newSnapshot.unpricedSymbols.isEmpty {
            saveCachedSnapshot(newSnapshot)
        }
        if let message = result.partialFailure.message(
            hasMixedCurrencies: newSnapshot.hasMixedCurrencies
        ) {
            errorMessage = message
        }
        AppLog.portfolio.debug(
            "Refresh committed snapshot kind=\(kind.logName, privacy: .public) flight=\(flightID, privacy: .public) accounts=\(newSnapshot.accounts.count, privacy: .public) holdings=\(newSnapshot.holdings.count, privacy: .public) unpriced=\(newSnapshot.unpricedSymbols.count, privacy: .public) extendedHoursFailed=\(result.partialFailure.extendedHoursFailed, privacy: .public)"
        )
    }

    /// Waits for `initialFlight`, and when another request replaced it, for
    /// the replacement that now satisfies this request.
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
                  replacement.kind.rawValue >= requestedKind.rawValue
            else {
                return
            }
            awaitedFlight = replacement
        }
    }

    /// Whether a flight's result may still be shown: it hasn't been cancelled
    /// or replaced, and the credentials it loaded with are still the saved
    /// ones.
    private func canCommit(flightID: UInt64, credentials: SnapTradeCredentials) -> Bool {
        !Task.isCancelled
            && refreshFlight?.id == flightID
            && credentialsStore.credentials?.sanitized == credentials
    }

    private func finishRefresh(flightID: UInt64) {
        guard refreshFlight?.id == flightID else { return }
        refreshFlight = nil
        isLoading = false
        // The flight ended without committing anything (its result went stale).
        if case .loading = loadState {
            loadState = .notLoaded
        }
    }

    private func resetForMissingCredentials() {
        refreshFlight?.task.cancel()
        refreshFlight = nil
        loadState = .notLoaded
        selectedProviderName = nil
        errorMessage = nil
        snapshotCredentials = nil
        isLoading = false
        AppLog.portfolio.debug(
            "Refresh skipped and current flight invalidated because credentials are incomplete"
        )
    }
}
