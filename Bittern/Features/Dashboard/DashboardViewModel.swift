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
    /// Launching: nothing for the saved credentials is in memory yet. The
    /// skeleton is nil for the first moments, when nothing is drawn, so a
    /// load that answers at once never flashes it.
    case loading(LaunchSkeleton?)
    /// Data is showing, current or not (`DashboardViewModel.priceStatus`).
    case loaded(PortfolioSnapshot)
    /// Launch failed with nothing to fall back on.
    case failed(PortfolioLoadFailure)

    var snapshot: PortfolioSnapshot? {
        guard case .loaded(let snapshot) = self else { return nil }
        return snapshot
    }
}

/// The dashboard's shape while launch waits for data.
struct LaunchSkeleton: Equatable {
    let rowCount: Int
    /// The row count comes from the cache. Without one it is a guess, so
    /// the list fades out rather than ending.
    let isRowCountKnown: Bool

    static let withoutCache = LaunchSkeleton(rowCount: 8, isRowCountKnown: false)
}

struct PortfolioLoadFailure: Equatable {
    let message: String
    /// Set when only the user can fix it; the page then says what and
    /// leads to Settings.
    let attention: PortfolioAttention?
}

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var loadState: PortfolioLoadState
    /// A short message for something the user did, or for data that loaded
    /// incomplete. Automatic refreshes never set it when they fail.
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
    /// A load is in flight.
    private(set) var isLoading = false
    private(set) var priceStatus = PriceStatus.current
    /// Whether the device has a network path, as last reported.
    private(set) var isOnline = true
    /// Prices are refreshing themselves: the app is in the foreground with
    /// data and a network path.
    private(set) var isLiveRefreshing = false
    /// Why the last holdings load failed, when only the user can fix it.
    private(set) var holdingsAttention: PortfolioAttention?

    private let credentialsStore: CredentialsStore
    private let repository: any PortfolioRepository
    private let defaults: UserDefaults
    private let loadCachedSnapshot: @Sendable () async -> PortfolioSnapshot?
    private let saveCachedSnapshot: @Sendable (PortfolioSnapshot) -> Void
    private let deleteCachedSnapshot: @Sendable () throws -> Void
    private let networkMonitor: any NetworkMonitor
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date

    @ObservationIgnored private var bootstrapState = BootstrapState.notStarted
    @ObservationIgnored private var cacheRead: Task<PortfolioSnapshot?, Never>?
    @ObservationIgnored private var refreshFlight: RefreshFlight?
    @ObservationIgnored private var nextFlightID: UInt64 = 0
    /// The credentials the shown snapshot was loaded with. A price refresh
    /// only makes sense on a snapshot of the current credentials.
    @ObservationIgnored private var snapshotCredentials: SnapTradeCredentials?
    /// The credentials the data in memory, or the launch under way, belongs
    /// to. Saved credentials that differ from these mean a new launch.
    @ObservationIgnored private var launchCredentials: SnapTradeCredentials?
    @ObservationIgnored private var launchID: UInt64 = 0
    /// Launch found neither a cache nor a network and waits for one.
    @ObservationIgnored private var isLaunchWaitingForNetwork = false
    /// Holdings are re-fetched when prices next arrive: after launch, and
    /// once they are due.
    @ObservationIgnored private var isHoldingsRefreshPending = false
    /// When holdings were last asked for. Nil means never, or that they may
    /// have changed: due at once.
    @ObservationIgnored private var lastHoldingsRequest: Date?
    @ObservationIgnored private var isRefreshingHoldings = false
    @ObservationIgnored private var networkTask: Task<Void, Never>?
    @ObservationIgnored private var isNetworkStatusKnown = false
    @ObservationIgnored private var networkWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var isForeground = true
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var liveTaskID: UInt64 = 0
    @ObservationIgnored private var lastPartialFailureMessage: String?

    private enum BootstrapState {
        case notStarted
        case running(Task<Void, Never>)
        case finished
    }

    private enum RefreshKind: Int, Comparable {
        case prices
        case holdings

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var logName: String {
            switch self {
            case .prices: "prices"
            case .holdings: "holdings"
            }
        }
    }

    private enum RefreshRequest {
        /// New prices for `snapshot`'s holdings, or only for those in
        /// `holdingIDs`; the rest keep theirs.
        case prices(PortfolioSnapshot, holdingIDs: Set<String>?)
        /// Accounts, positions and prices from scratch.
        case holdings

        var kind: RefreshKind {
            switch self {
            case .prices: .prices
            case .holdings: .holdings
            }
        }
    }

    private enum RefreshOutcome {
        case committed(PortfolioLoadPartialFailure)
        case failed(any Error)
        /// A live tick that would have lost prices or extended-hours quotes
        /// the screen has; nothing was committed.
        case rejected
        /// Cancelled, replaced, or the credentials changed: nothing to report.
        case superseded
    }

    private struct RefreshFlight {
        let id: UInt64
        let kind: RefreshKind
        let credentials: SnapTradeCredentials
        let task: Task<RefreshOutcome, Never>
    }

    init(
        credentialsStore: CredentialsStore,
        repository: any PortfolioRepository,
        defaults: UserDefaults = .standard,
        initialSnapshot: PortfolioSnapshot? = nil,
        loadCachedSnapshot: @escaping @Sendable () async -> PortfolioSnapshot?,
        saveCachedSnapshot: @escaping @Sendable (PortfolioSnapshot) -> Void,
        deleteCachedSnapshot: @escaping @Sendable () throws -> Void,
        networkMonitor: any NetworkMonitor,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentialsStore = credentialsStore
        self.repository = repository
        self.defaults = defaults
        self.loadCachedSnapshot = loadCachedSnapshot
        self.saveCachedSnapshot = saveCachedSnapshot
        self.deleteCachedSnapshot = deleteCachedSnapshot
        self.networkMonitor = networkMonitor
        self.sleep = sleep
        self.now = now

        performanceMode = defaults.string(forKey: AppSettingKey.performanceMode)
            .flatMap(PerformanceMode.init(rawValue:)) ?? .today
        sortOption = defaults.string(forKey: AppSettingKey.sortOption)
            .flatMap(HoldingSortOption.init(rawValue:)) ?? .marketValue
        minPriceThreshold = defaults.object(forKey: AppSettingKey.minPriceThreshold) as? Double ?? 1.0

        let credentials = credentialsStore.credentials?.sanitized
        if let initialSnapshot {
            loadState = .loaded(initialSnapshot)
            snapshotCredentials = credentials
            launchCredentials = credentials
        } else {
            loadState = credentials?.isComplete == true ? .loading(nil) : .notLoaded
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

    /// How many of the selected provider's holdings the minimum market value
    /// hides.
    var hiddenHoldingCount: Int {
        visibleSnapshot?.holdings.count { !$0.meetsMinimumMarketValue(minPriceThreshold) } ?? 0
    }

    /// Saves a new minimum market value. Anything that isn't a non-negative
    /// number shows every holding.
    func setMinimumMarketValue(_ value: Double) {
        minPriceThreshold = value.isFinite ? max(value, 0) : 0
    }

    var sortedHoldings: [PortfolioHolding] {
        sortOption.sorted(displaySnapshot?.holdings ?? [], by: performanceMode)
    }

    /// Holdings across every account (no provider filter) with the minimum
    /// market value applied.
    var thresholdFilteredHoldings: [PortfolioHolding] {
        (snapshot?.holdings ?? []).filter { $0.meetsMinimumMarketValue(minPriceThreshold) }
    }

    /// What the user has to fix, shown over the data while there is some:
    /// a holdings load SnapTrade refused, or a disabled brokerage connection.
    var attention: PortfolioAttention? {
        guard let snapshot else { return nil }
        return holdingsAttention ?? PortfolioAttention.disabledConnections(in: snapshot)
    }

    /// Whether `holding`'s figures are moving now: prices refresh themselves
    /// and are current, and the holding is in an active session.
    func isLive(_ holding: PortfolioHolding) -> Bool {
        isLiveRefreshing && !priceStatus.isStale && holding.isInActiveSession(at: now())
    }

    // MARK: - Launch

    /// Starts watching the network and launches once. Concurrent callers
    /// share one bootstrap.
    func bootstrap() async {
        switch bootstrapState {
        case .finished:
            return
        case .running(let task):
            await task.value
        case .notStarted:
            let task = Task {
                startObservingNetwork()
                if snapshot != nil, snapshotCredentials == currentCredentials {
                    // Already showing data, as a preview does.
                    await waitForNetworkStatus()
                    updateLiveRefresh(refreshingFirst: true)
                } else {
                    await launch(readingCache: true)
                }
            }
            bootstrapState = .running(task)
            await task.value
            bootstrapState = .finished
        }
    }

    /// Shows the skeleton and loads the portfolio for the saved credentials.
    /// With a cache, only prices for its holdings are awaited, then holdings
    /// are re-fetched behind the data; without one, everything is.
    private func launch(readingCache: Bool) async {
        guard let credentials = currentCredentials else {
            resetForMissingCredentials()
            return
        }

        launchID &+= 1
        let launch = launchID
        stopLiveRefresh()
        launchCredentials = credentials
        snapshotCredentials = nil
        holdingsAttention = nil
        priceStatus = .current
        isLaunchWaitingForNetwork = false
        isHoldingsRefreshPending = false
        selectedProviderName = nil
        loadState = .loading(nil)
        AppLog.portfolio.debug("Launch started readingCache=\(readingCache, privacy: .public)")

        let cached = readingCache ? await readCacheOnce() : nil
        guard launch == launchID else { return }

        let skeleton = cached.map {
            LaunchSkeleton(
                rowCount: $0.filtered(minimumMarketValue: minPriceThreshold).holdings.count,
                isRowCountKnown: true
            )
        } ?? .withoutCache
        revealSkeleton(skeleton, launch: launch)

        await waitForNetworkStatus()
        guard launch == launchID else { return }

        if let cached {
            isHoldingsRefreshPending = true
            guard isOnline else {
                showStale(cached, credentials: credentials)
                return
            }
            await launchPrices(of: cached, credentials: credentials, launch: launch)
        } else {
            guard isOnline else {
                waitForNetworkOnSkeleton(skeleton)
                return
            }
            await launchHoldings(skeleton: skeleton, launch: launch)
        }
    }

    private func launchPrices(
        of cached: PortfolioSnapshot,
        credentials: SnapTradeCredentials,
        launch: UInt64
    ) async {
        let outcome = await refreshRetrying(.prices(cached, holdingIDs: nil), launch: launch)
        guard launch == launchID else { return }

        switch outcome {
        case .committed(let partialFailure):
            report(partialFailure, force: false)
            updateLiveRefresh()
            await refreshHoldingsIfPending()
        case .failed(let error):
            AppLog.portfolio.error("Launch prices failed, showing the cache: \(AppLog.describe(error))")
            // Current prices can't be had: the cache, as it was. Live
            // refresh keeps trying while there is a network.
            showStale(cached, credentials: credentials)
        case .rejected, .superseded:
            return
        }
    }

    private func launchHoldings(skeleton: LaunchSkeleton, launch: UInt64) async {
        isLaunchWaitingForNetwork = false
        let outcome = await refreshRetrying(.holdings, launch: launch)
        guard launch == launchID else { return }

        switch outcome {
        case .committed(let partialFailure):
            report(partialFailure, force: false)
            updateLiveRefresh()
        case .failed(let error):
            switch failure(of: error) {
            case .offline:
                waitForNetworkOnSkeleton(skeleton)
            case .needsAction(let attention):
                loadState = .failed(PortfolioLoadFailure(message: attention.message, attention: attention))
            case .transient, .permanent:
                loadState = .failed(
                    PortfolioLoadFailure(
                        message: UserFacingError.message(
                            for: error,
                            fallback: "Portfolio couldn’t be loaded. Please try again."
                        ),
                        attention: nil
                    )
                )
            }
        case .rejected, .superseded:
            return
        }
    }

    /// No cache and no network: the skeleton stays, and the load starts when
    /// the network returns. Nothing is wrong yet, so there is no error.
    private func waitForNetworkOnSkeleton(_ skeleton: LaunchSkeleton) {
        loadState = .loading(skeleton)
        isLaunchWaitingForNetwork = true
        AppLog.portfolio.debug("Launch waits for the network")
    }

    /// Shows the skeleton unless data arrives first.
    private func revealSkeleton(_ skeleton: LaunchSkeleton, launch: UInt64) {
        let sleep = sleep
        Task {
            do {
                try await sleep(LivePriceRefresh.skeletonDelay)
            } catch {
                return
            }
            guard launch == launchID, case .loading(nil) = loadState else { return }
            loadState = .loading(skeleton)
        }
    }

    /// Retries transient failures with backoff while the network is up.
    private func refreshRetrying(_ request: RefreshRequest, launch: UInt64) async -> RefreshOutcome {
        var failures = 0
        while true {
            let outcome = await requestRefresh(request, acceptsRegression: true)
            guard case .failed(let error) = outcome,
                  failure(of: error) == .transient
            else {
                return outcome
            }
            failures += 1
            guard failures < LivePriceRefresh.attemptsBeforeGivingUp else { return outcome }
            AppLog.portfolio.debug("Launch retrying after failure \(failures, privacy: .public)")
            do {
                try await sleep(LivePriceRefresh.backoff(afterFailures: failures))
            } catch {
                return .superseded
            }
            guard launch == launchID else { return .superseded }
        }
    }

    /// The cached snapshot is read once, before any network load starts, so
    /// a late cache read can never overwrite fresh data.
    private func readCacheOnce() async -> PortfolioSnapshot? {
        let task: Task<PortfolioSnapshot?, Never>
        if let cacheRead {
            task = cacheRead
        } else {
            task = Task { [loadCachedSnapshot] in await loadCachedSnapshot() }
            cacheRead = task
        }
        guard let cached = await task.value else {
            AppLog.portfolio.debug("Launch cache miss")
            return nil
        }
        AppLog.portfolio.debug(
            "Launch read cached snapshot accounts=\(cached.accounts.count, privacy: .public) holdings=\(cached.holdings.count, privacy: .public)"
        )
        // The cache may predate today's rules for what counts as known.
        return cached.recomputed()
    }

    /// Shows `snapshot` as it was, in gray.
    private func showStale(_ snapshot: PortfolioSnapshot, credentials: SnapTradeCredentials) {
        loadState = .loaded(snapshot)
        snapshotCredentials = credentials
        priceStatus = .stale(since: snapshot.lastUpdated)
        // Keeps trying, from one interval on, while there is a network;
        // without one, the network's return starts it.
        updateLiveRefresh()
    }

    // MARK: - Refreshing holdings

    /// After saving or clearing credentials. New credentials are a new
    /// launch, with the old cache gone; the same ones re-fetch holdings
    /// behind the data on screen.
    func fullRefresh() async {
        guard let credentials = currentCredentials else {
            resetForMissingCredentials()
            return
        }
        if launchCredentials == credentials, snapshot != nil {
            isHoldingsRefreshPending = true
            await refreshHoldingsIfPending()
        } else {
            await relaunchIfNeeded(credentials)
        }
    }

    /// Something outside the app, such as connecting a brokerage, may have
    /// changed the holdings: they are re-fetched when prices next arrive,
    /// without waiting out `LivePriceRefresh.holdingsInterval`.
    func holdingsMayHaveChanged() {
        lastHoldingsRequest = nil
    }

    /// The error page's Try Again.
    func retryLaunch() async {
        await launch(readingCache: false)
    }

    private func relaunchIfNeeded(_ credentials: SnapTradeCredentials) async {
        if launchCredentials != credentials {
            // Whatever is cached belongs to other credentials.
            deleteCache()
            cacheRead = Task { nil }
            await launch(readingCache: false)
            return
        }
        switch loadState {
        case .failed:
            await launch(readingCache: false)
        case .loading where isLaunchWaitingForNetwork && isOnline:
            await launchHoldings(skeleton: .withoutCache, launch: launchID)
        case .notLoaded:
            await launch(readingCache: cacheRead == nil)
        case .loading, .loaded:
            break
        }
    }

    /// Re-fetches holdings behind the data on screen: once after launch, and
    /// whenever they are due. SnapTrade refusing the credentials shows a
    /// banner; other failures leave the list as it is, and its prices keep
    /// refreshing.
    private func refreshHoldingsIfPending() async {
        guard isHoldingsRefreshPending, !isRefreshingHoldings else { return }
        isRefreshingHoldings = true
        defer { isRefreshingHoldings = false }

        let launch = launchID
        var failures = 0
        while launch == launchID, isHoldingsRefreshPending {
            let outcome = await requestRefresh(.holdings, acceptsRegression: true)
            switch outcome {
            case .committed(let partialFailure):
                isHoldingsRefreshPending = false
                holdingsAttention = nil
                report(partialFailure, force: false)
                AppLog.portfolio.debug("Holdings refreshed after launch")
                return
            case .failed(let error):
                AppLog.portfolio.error("Holdings refresh after launch failed: \(AppLog.describe(error))")
                switch failure(of: error) {
                case .needsAction(let attention):
                    isHoldingsRefreshPending = false
                    holdingsAttention = attention
                    return
                case .offline:
                    // Still pending: the first prices after the network
                    // returns bring it back.
                    return
                case .permanent:
                    isHoldingsRefreshPending = false
                    return
                case .transient:
                    failures += 1
                    guard failures < LivePriceRefresh.attemptsBeforeGivingUp else {
                        isHoldingsRefreshPending = false
                        return
                    }
                }
            case .rejected, .superseded:
                return
            }
            do {
                try await sleep(LivePriceRefresh.backoff(afterFailures: failures))
            } catch {
                return
            }
        }
    }

    // MARK: - Live prices

    /// The app came to the foreground. This isn't a launch: the data stays,
    /// and new prices replace it as they come.
    func sceneDidBecomeActive() {
        guard !isForeground else { return }
        isForeground = true
        updateLiveRefresh(refreshingFirst: true)
    }

    /// Live refresh stops in the background.
    func sceneDidEnterBackground() {
        isForeground = false
        stopLiveRefresh()
    }

    /// Starts or stops live refresh to match whether it can run: in the
    /// foreground, with data for the saved credentials and a network path.
    /// `refreshingFirst` fetches every price at once instead of after the
    /// first interval.
    private func updateLiveRefresh(refreshingFirst: Bool = false) {
        let canRun = isForeground
            && isOnline
            && snapshot != nil
            && snapshotCredentials != nil
            && snapshotCredentials == currentCredentials
        guard canRun else {
            stopLiveRefresh()
            return
        }
        guard liveTask == nil || refreshingFirst else { return }

        liveTask?.cancel()
        liveTaskID &+= 1
        let id = liveTaskID
        isLiveRefreshing = true
        liveTask = Task { [weak self] in
            await self?.runLiveRefresh(id: id, refreshingFirst: refreshingFirst)
        }
    }

    private func stopLiveRefresh() {
        liveTask?.cancel()
        liveTask = nil
        liveTaskID &+= 1
        isLiveRefreshing = false
    }

    /// Fetches prices for the holdings in an active session every interval.
    /// With none in session it waits for the next one to open, checking
    /// every price now and then. While prices aren't current it fetches
    /// all of them, backing off as failures repeat. Prices turn stale at
    /// once when the Market Data Connection is lost, and after a few failed
    /// requests in a row while it is live.
    private func runLiveRefresh(id: UInt64, refreshingFirst: Bool) async {
        var failures = 0
        var pricesEverything = refreshingFirst
        if !refreshingFirst {
            do { try await sleep(LivePriceRefresh.interval) } catch { return }
        }

        while !Task.isCancelled, id == liveTaskID, let snapshot {
            let date = now()
            let active = snapshot.activeHoldings(at: date)

            if !pricesEverything, !priceStatus.isStale, active.isEmpty {
                let opening = snapshot.nextSessionStart(after: date)
                    .map { Duration.seconds(max($0.timeIntervalSince(date), 1)) }
                let wait = min(opening ?? LivePriceRefresh.idleCheckInterval, LivePriceRefresh.idleCheckInterval)
                AppLog.portfolio.debug("Live refresh idle for \(wait, privacy: .public)")
                do { try await sleep(wait) } catch { return }
                pricesEverything = true
                continue
            }

            await markStaleIfConnectionLost()
            guard !Task.isCancelled, id == liveTaskID else { return }

            let holdingIDs = pricesEverything || priceStatus.isStale
                ? nil
                : Set(active.map(\.id))
            pricesEverything = false
            let outcome = await requestRefresh(
                .prices(snapshot, holdingIDs: holdingIDs),
                acceptsRegression: failures + 1 >= LivePriceRefresh.attemptsBeforeGivingUp
            )
            guard !Task.isCancelled, id == liveTaskID else { return }

            switch outcome {
            case .committed:
                failures = 0
                if areHoldingsDue {
                    isHoldingsRefreshPending = true
                }
                if isHoldingsRefreshPending {
                    Task { await refreshHoldingsIfPending() }
                }
            case .failed(let error):
                failures += 1
                AppLog.portfolio.debug(
                    "Live refresh failed \(failures, privacy: .public) in a row: \(AppLog.describe(error))"
                )
            case .rejected:
                failures += 1
            case .superseded:
                break
            }
            if failures >= LivePriceRefresh.attemptsBeforeGivingUp, !priceStatus.isStale, let shown = self.snapshot {
                priceStatus = .stale(since: shown.lastUpdated)
            }

            let delay = failures == 0
                ? LivePriceRefresh.interval
                : LivePriceRefresh.backoff(afterFailures: failures)
            do { try await sleep(delay) } catch { return }
        }
    }

    /// Holdings change only when the user trades or connects a brokerage,
    /// so after launch they are asked for again only once an hour has
    /// passed since the last time.
    private var areHoldingsDue: Bool {
        guard let lastHoldingsRequest else { return true }
        let interval = TimeInterval(LivePriceRefresh.holdingsInterval.components.seconds)
        return now().timeIntervalSince(lastHoldingsRequest) >= interval
    }

    /// Before each price request: with the Market Data Connection lost,
    /// the figures on screen are the last ones heard, not current ones,
    /// unless no market can have moved since. Returning from the background
    /// usually finds it lost. The prices the request brings turn them back.
    private func markStaleIfConnectionLost() async {
        guard !priceStatus.isStale else { return }
        let isConnected = await repository.isMarketDataConnected()
        guard !isConnected,
              !priceStatus.isStale,
              let shown = snapshot,
              shown.mayHavePricesMoved(until: now())
        else {
            return
        }
        AppLog.portfolio.debug("Market data connection lost; prices shown as stale")
        priceStatus = .stale(since: shown.lastUpdated)
    }

    // MARK: - Network

    private func startObservingNetwork() {
        guard networkTask == nil else { return }
        let paths = networkMonitor.paths()
        networkTask = Task { [weak self] in
            for await isOnline in paths {
                guard let self else { return }
                self.networkPathChanged(isOnline: isOnline)
            }
        }
    }

    private func waitForNetworkStatus() async {
        guard !isNetworkStatusKnown else { return }
        await withCheckedContinuation { continuation in
            networkWaiters.append(continuation)
        }
    }

    private func networkPathChanged(isOnline online: Bool) {
        let wasKnown = isNetworkStatusKnown
        let changed = online != isOnline
        isOnline = online
        if !wasKnown {
            isNetworkStatusKnown = true
            let waiters = networkWaiters
            networkWaiters = []
            waiters.forEach { $0.resume() }
            if !online, let snapshot {
                priceStatus = .stale(since: snapshot.lastUpdated)
            }
            return
        }
        guard changed else { return }
        AppLog.portfolio.debug("Network path changed online=\(online, privacy: .public)")

        if online {
            Task { await resumeAfterReconnect() }
        } else {
            stopLiveRefresh()
            if let snapshot, !priceStatus.isStale {
                priceStatus = .stale(since: snapshot.lastUpdated)
            }
        }
    }

    /// Whatever waited on the network goes now: a launch with nothing to
    /// show loads, and data on screen gets new prices, which bring its
    /// colors back.
    private func resumeAfterReconnect() async {
        switch loadState {
        case .loading where isLaunchWaitingForNetwork:
            await launchHoldings(skeleton: .withoutCache, launch: launchID)
        case .loaded:
            updateLiveRefresh(refreshingFirst: true)
        case .failed(let failure) where failure.attention == nil:
            await launch(readingCache: false)
        case .loading, .failed, .notLoaded:
            break
        }
    }

    // MARK: - One load at a time

    private var currentCredentials: SnapTradeCredentials? {
        guard let credentials = credentialsStore.credentials?.sanitized,
              credentials.isComplete
        else {
            return nil
        }
        return credentials
    }

    /// Runs at most one network load at a time. A request that an in-flight
    /// load already covers joins it; any other request cancels and replaces
    /// it.
    private func requestRefresh(_ request: RefreshRequest, acceptsRegression: Bool) async -> RefreshOutcome {
        guard let credentials = currentCredentials else {
            resetForMissingCredentials()
            return .superseded
        }

        if let current = refreshFlight {
            if current.credentials == credentials, current.kind >= request.kind {
                AppLog.portfolio.debug(
                    "Refresh joined in-flight task current=\(current.kind.logName, privacy: .public) requested=\(request.kind.logName, privacy: .public) flight=\(current.id, privacy: .public)"
                )
                return await awaitFlight(current, satisfying: request.kind)
            }
            AppLog.portfolio.debug(
                "Refresh superseding in-flight task current=\(current.kind.logName, privacy: .public) requested=\(request.kind.logName, privacy: .public) flight=\(current.id, privacy: .public)"
            )
            current.task.cancel()
        }

        let flight = startRefresh(request, credentials: credentials, acceptsRegression: acceptsRegression)
        return await awaitFlight(flight, satisfying: request.kind)
    }

    private func startRefresh(
        _ request: RefreshRequest,
        credentials: SnapTradeCredentials,
        acceptsRegression: Bool
    ) -> RefreshFlight {
        nextFlightID &+= 1
        let flightID = nextFlightID
        let task = Task {
            let outcome = await performRefresh(
                request,
                credentials: credentials,
                flightID: flightID,
                acceptsRegression: acceptsRegression
            )
            finishRefresh(flightID: flightID)
            return outcome
        }
        let flight = RefreshFlight(id: flightID, kind: request.kind, credentials: credentials, task: task)

        refreshFlight = flight
        isLoading = true
        if request.kind == .holdings {
            lastHoldingsRequest = now()
        }
        AppLog.portfolio.debug(
            "Refresh started kind=\(request.kind.logName, privacy: .public) flight=\(flightID, privacy: .public)"
        )
        return flight
    }

    private func performRefresh(
        _ request: RefreshRequest,
        credentials: SnapTradeCredentials,
        flightID: UInt64,
        acceptsRegression: Bool
    ) async -> RefreshOutcome {
        // Replaced before it began: there is nothing to ask the network.
        guard canCommit(flightID: flightID, credentials: credentials) else { return .superseded }

        let result: PortfolioLoadResult
        do {
            switch request {
            case .prices(let base, let holdingIDs):
                result = try await repository.refreshPrices(
                    for: holdingIDs.map(base.only(holdingIDs:)) ?? base
                )
            case .holdings:
                result = try await repository.loadPortfolio(credentials: credentials)
            }
        } catch {
            guard canCommit(flightID: flightID, credentials: credentials),
                  !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled
            else {
                return .superseded
            }
            AppLog.portfolio.error(
                "Refresh failed kind=\(request.kind.logName, privacy: .public) flight=\(flightID, privacy: .public): \(AppLog.describe(error))"
            )
            return .failed(error)
        }

        guard canCommit(flightID: flightID, credentials: credentials) else {
            AppLog.portfolio.debug(
                "Refresh discarded stale result kind=\(request.kind.logName, privacy: .public) flight=\(flightID, privacy: .public)"
            )
            return .superseded
        }

        let newSnapshot: PortfolioSnapshot
        switch request {
        case .prices(let base, _):
            if !acceptsRegression, Self.loses(result, from: base) {
                AppLog.portfolio.debug("Refresh rejected a result missing data the screen has flight=\(flightID, privacy: .public)")
                return .rejected
            }
            newSnapshot = (snapshot ?? base).merging(
                prices: result.snapshot.holdings,
                pricedAt: result.snapshot.lastUpdated
            )
        case .holdings:
            newSnapshot = result.snapshot.inheritingLastUpdated(from: snapshot)
        }

        commit(newSnapshot, credentials: credentials)
        AppLog.portfolio.debug(
            "Refresh committed snapshot kind=\(request.kind.logName, privacy: .public) flight=\(flightID, privacy: .public) accounts=\(newSnapshot.accounts.count, privacy: .public) holdings=\(newSnapshot.holdings.count, privacy: .public) unpriced=\(newSnapshot.unpricedSymbols.count, privacy: .public) extendedHoursFailed=\(result.partialFailure.extendedHoursFailed, privacy: .public)"
        )
        return .committed(result.partialFailure)
    }

    /// Whether a price result would take away a price, or the extended-hours
    /// quotes, that the shown snapshot has. A live tick like that is more
    /// likely a hiccup than news, so it is retried before it is shown.
    private static func loses(_ result: PortfolioLoadResult, from base: PortfolioSnapshot) -> Bool {
        let priced = Set(base.holdings.filter { $0.currentPrice != nil }.map(\.id))
        let losesPrice = result.snapshot.holdings.contains {
            priced.contains($0.id) && $0.currentPrice == nil
        }
        return losesPrice || result.partialFailure.extendedHoursFailed
    }

    private func commit(_ newSnapshot: PortfolioSnapshot, credentials: SnapTradeCredentials) {
        loadState = .loaded(newSnapshot)
        snapshotCredentials = credentials
        isLaunchWaitingForNetwork = false
        priceStatus = .current
        if let selectedProviderName,
           !newSnapshot.accounts.contains(where: { $0.providerName == selectedProviderName }) {
            self.selectedProviderName = nil
        }
        // A snapshot with holes shows what's known for now, but the next
        // launch should fall back on the last complete one.
        if newSnapshot.unpricedSymbols.isEmpty {
            saveCachedSnapshot(newSnapshot)
        }
    }

    /// Waits for `initialFlight`, and when another request replaced it, for
    /// the replacement that now satisfies this request.
    private func awaitFlight(
        _ initialFlight: RefreshFlight,
        satisfying requestedKind: RefreshKind
    ) async -> RefreshOutcome {
        var awaitedFlight = initialFlight
        while true {
            let outcome = await awaitedFlight.task.value
            if case .failed = outcome, awaitedFlight.kind > requestedKind {
                // A live tick that waited for a holdings load: SnapTrade
                // failing says nothing about prices, and whoever asked for
                // the holdings handles it.
                return .superseded
            }
            guard case .superseded = outcome,
                  let replacement = refreshFlight,
                  replacement.id != awaitedFlight.id,
                  replacement.kind >= requestedKind
            else {
                return outcome
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
            && currentCredentials == credentials
    }

    private func finishRefresh(flightID: UInt64) {
        guard refreshFlight?.id == flightID else { return }
        refreshFlight = nil
        isLoading = false
    }

    /// What a failed load means now. A dropped connection while the device
    /// still has a network path is worth retrying, not waiting out.
    private func failure(of error: any Error) -> RefreshFailure {
        let failure = RefreshFailure(error)
        if failure == .offline, isOnline {
            return .transient
        }
        if failure == .transient, !isOnline {
            return .offline
        }
        return failure
    }

    /// Partial failures of loads the user started, or of launch, as a short
    /// message; the same message isn't repeated unless `force`.
    private func report(_ partialFailure: PortfolioLoadPartialFailure, force: Bool) {
        guard let snapshot,
              let message = partialFailure.message(hasMixedCurrencies: snapshot.hasMixedCurrencies)
        else {
            return
        }
        guard force || message != lastPartialFailureMessage else { return }
        lastPartialFailureMessage = message
        errorMessage = message
    }

    private func deleteCache() {
        do {
            try deleteCachedSnapshot()
        } catch {
            AppLog.persistence.error("Cache delete failed: \(AppLog.describe(error))")
        }
    }

    private func resetForMissingCredentials() {
        refreshFlight?.task.cancel()
        refreshFlight = nil
        launchID &+= 1
        stopLiveRefresh()
        loadState = .notLoaded
        selectedProviderName = nil
        errorMessage = nil
        snapshotCredentials = nil
        launchCredentials = nil
        holdingsAttention = nil
        priceStatus = .current
        isLoading = false
        isLaunchWaitingForNetwork = false
        isHoldingsRefreshPending = false
        AppLog.portfolio.debug(
            "Refresh skipped and current flight invalidated because credentials are incomplete"
        )
    }
}
