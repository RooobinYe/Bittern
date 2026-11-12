import Foundation
import Testing
@testable import Bittern

private final class InMemoryCredentialsStorage: CredentialsStorage {
    var stored: SnapTradeCredentials?

    init(_ stored: SnapTradeCredentials?) {
        self.stored = stored
    }

    func load() throws -> SnapTradeCredentials? { stored }
    func save(_ credentials: SnapTradeCredentials) throws { stored = credentials }
    func delete() throws { stored = nil }
}

/// Answers loads from `load` and `refresh`, or, while `holdsCalls`, keeps each
/// call waiting until the test answers it. A held call ends with a
/// cancellation error when its task is cancelled, as URLSession does, unless
/// `honorsCancellation` is off.
private final class StubRepository: PortfolioRepository {
    enum Call: Equatable {
        case load
        case refresh
    }

    private struct HeldCall {
        let id: Int
        let call: Call
        let continuation: CheckedContinuation<PortfolioLoadResult, any Error>
    }

    var load: () throws -> PortfolioLoadResult = { throw URLError(.notConnectedToInternet) }
    /// Prices for the holdings asked about. By default, the same prices.
    var refresh: (PortfolioSnapshot) throws -> PortfolioLoadResult = { snapshot in
        PortfolioLoadResult(snapshot: snapshot, partialFailure: PortfolioLoadPartialFailure())
    }
    var holdsCalls = false
    var honorsCancellation = true
    var marketDataConnected = true
    private(set) var calls: [Call] = []
    /// The symbols each price refresh asked about.
    private(set) var refreshedSymbols: [[String]] = []
    private var held: [HeldCall] = []
    private var nextID = 0

    var heldCalls: [Call] { held.map(\.call) }

    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult {
        calls.append(.load)
        return holdsCalls ? try await hold(.load) : try load()
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult {
        calls.append(.refresh)
        refreshedSymbols.append(snapshot.holdings.map(\.symbol).sorted())
        return holdsCalls ? try await hold(.refresh) : try refresh(snapshot)
    }

    func priceHistory(for holding: PortfolioHolding, range: HoldingChartRange) async throws -> HoldingPriceSeries {
        throw URLError(.unsupportedURL)
    }

    func portfolioHistory(credentials: SnapTradeCredentials, accountIDs: [String]) async throws -> PortfolioHistory {
        throw URLError(.unsupportedURL)
    }

    func registerUser(apiKey: SnapTradeCredentials) async throws -> SnapTradeCredentials {
        throw URLError(.unsupportedURL)
    }

    func connectionPortalURL(credentials: SnapTradeCredentials, darkMode: Bool) async throws -> URL {
        throw URLError(.unsupportedURL)
    }

    func isMarketDataConnected() async -> Bool {
        marketDataConnected
    }

    /// Answers the held call at `index`, oldest first.
    func answer(_ index: Int = 0, with snapshot: PortfolioSnapshot) {
        held.remove(at: index).continuation.resume(
            returning: PortfolioLoadResult(snapshot: snapshot, partialFailure: PortfolioLoadPartialFailure())
        )
    }

    /// Fails the held call at `index`, oldest first.
    func fail(_ index: Int = 0, with error: any Error) {
        held.remove(at: index).continuation.resume(throwing: error)
    }

    private func hold(_ call: Call) async throws -> PortfolioLoadResult {
        nextID += 1
        let id = nextID
        let honorsCancellation = honorsCancellation
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                held.append(HeldCall(id: id, call: call, continuation: continuation))
            }
        } onCancel: {
            guard honorsCancellation else { return }
            Task { @MainActor in self.cancel(id) }
        }
    }

    private func cancel(_ id: Int) {
        guard let index = held.firstIndex(where: { $0.id == id }) else { return }
        held.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

private nonisolated final class SavedSnapshots: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [PortfolioSnapshot] = []
    private var deleteCount = 0

    var all: [PortfolioSnapshot] { lock.withLock { values } }
    var deletes: Int { lock.withLock { deleteCount } }

    func append(_ snapshot: PortfolioSnapshot) {
        lock.withLock { values.append(snapshot) }
    }

    func delete() {
        lock.withLock { deleteCount += 1 }
    }
}

private final class Flag {
    var isSet = false
}

/// Lets the model's own tasks run until `condition` holds, or gives up so the
/// test's expectations report what went wrong.
private func settle(until condition: () -> Bool) async {
    var attempts = 0
    while !condition(), attempts < 10_000 {
        await Task.yield()
        attempts += 1
    }
}

/// Lets the model's own tasks run for a while, to show that something they
/// could do doesn't happen.
private func settle() async {
    for _ in 0..<200 {
        await Task.yield()
    }
}

private extension PortfolioLoadState {
    var skeleton: LaunchSkeleton?? {
        guard case .loading(let skeleton) = self else { return nil }
        return .some(skeleton)
    }

    var failure: PortfolioLoadFailure? {
        guard case .failed(let failure) = self else { return nil }
        return failure
    }

    var isNotLoaded: Bool {
        guard case .notLoaded = self else { return false }
        return true
    }
}

/// Keychain, disk, settings, the network path and time are replaced, so
/// running these on any simulator leaves the real credentials, cached
/// portfolio and preferences untouched.
@Suite
struct DashboardViewModelTests {
    private let credentials = SnapTradeCredentials(
        clientId: "client",
        consumerKey: "key",
        userId: "user",
        userSecret: "secret"
    )
    private let saved = SavedSnapshots()
    private let repository = StubRepository()
    private let clock = TestClock()
    private let network = TestNetworkMonitor()
    private let defaultsSuite = "BitternTests.\(UUID().uuidString)"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: defaultsSuite)!
    }

    private func viewModel(
        credentials: SnapTradeCredentials?,
        cached: PortfolioSnapshot? = nil
    ) -> DashboardViewModel {
        viewModel(
            store: CredentialsStore(storage: InMemoryCredentialsStorage(credentials)),
            cached: cached
        )
    }

    private func viewModel(
        store: CredentialsStore,
        cached: PortfolioSnapshot? = nil
    ) -> DashboardViewModel {
        let saved = saved
        let clock = clock
        let box = UncheckedSnapshot(value: cached)
        return DashboardViewModel(
            credentialsStore: store,
            repository: repository,
            defaults: defaults,
            loadCachedSnapshot: { box.value },
            saveCachedSnapshot: { saved.append($0) },
            deleteCachedSnapshot: { saved.delete() },
            networkMonitor: network,
            sleep: { try await clock.sleep(for: $0) },
            now: { clock.now }
        )
    }

    private func complete(
        _ symbol: String = "AAPL",
        at time: TimeInterval = 2_000,
        instrumentKind: PortfolioInstrumentKind? = .stock
    ) -> PortfolioSnapshot {
        .make(
            accounts: [makeAccount()],
            holdings: [makeHolding(symbol: symbol, instrumentKind: instrumentKind)],
            lastUpdated: Date(timeIntervalSince1970: time)
        )
    }

    private func result(_ snapshot: PortfolioSnapshot) -> PortfolioLoadResult {
        PortfolioLoadResult(snapshot: snapshot, partialFailure: PortfolioLoadPartialFailure())
    }

    /// The same holdings at `price`, priced now.
    private func repriced(_ snapshot: PortfolioSnapshot, to price: Double) -> PortfolioSnapshot {
        .make(
            accounts: snapshot.accounts,
            holdings: snapshot.holdings.map {
                $0.repriced(
                    currentPrice: price,
                    previousClose: $0.previousClose,
                    preMarketChange: nil,
                    postMarketChange: nil,
                    overnightChange: nil,
                    marketSession: $0.marketSession,
                    regularPriceTime: clock.now
                )
            },
            lastUpdated: clock.now
        )
    }

    /// Lets the model start a sleep of `duration`, moves time on by it, and
    /// lets the model act on it. Moving time before the model sleeps would
    /// leave that sleep waiting forever.
    private func advance(by duration: Duration) async {
        await settle { clock.pendingSleeps.contains(duration) }
        clock.advance(by: duration)
        await settle()
    }

    /// A model that has launched from a cache holding `cached` and is
    /// showing current prices, with the holdings refresh after launch done.
    private func launchedModel(cached: PortfolioSnapshot) async -> DashboardViewModel {
        repository.load = { [result] in result(cached) }
        let model = viewModel(credentials: credentials, cached: cached)
        await model.bootstrap()
        await settle()
        return model
    }

    // MARK: - Launch

    @Test func withoutCredentialsNothingIsLoadedAndNoSnapshotExists() async {
        let model = viewModel(credentials: nil)

        await model.bootstrap()

        #expect(model.loadState.isNotLoaded)
        #expect(model.snapshot == nil)
        #expect(model.displaySnapshot == nil)
        #expect(model.sortedHoldings.isEmpty)
        #expect(repository.calls.isEmpty)
    }

    @Test func startsLaunchingWithNothingDrawnWithCredentials() {
        let model = viewModel(credentials: credentials)

        #expect(model.loadState.skeleton == .some(nil))
    }

    @Test func launchWithACacheKeepsTheSkeletonUntilPricesArrive() async {
        let cached = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [makeHolding(), makeHolding(symbol: "MSFT")],
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )
        repository.holdsCalls = true
        let model = viewModel(credentials: credentials, cached: cached)

        let launch = Task { await model.bootstrap() }
        await settle { repository.heldCalls == [.refresh] }

        // Only prices are awaited, for the cache's holdings.
        #expect(repository.refreshedSymbols == [["AAPL", "MSFT"]])
        #expect(model.loadState.skeleton == .some(nil))
        #expect(model.snapshot == nil)

        await advance(by: LivePriceRefresh.skeletonDelay)
        #expect(model.loadState.skeleton == LaunchSkeleton(rowCount: 2, isRowCountKnown: true))

        repository.answer(with: repriced(cached, to: 120))
        await settle { repository.heldCalls == [.load] }

        #expect(model.snapshot?.totalMarketValue == 2_400)
        #expect(model.priceStatus == .current)

        repository.answer(with: repriced(cached, to: 120))
        await launch.value
    }

    @Test func pricesThatArriveQuicklySkipTheSkeleton() async {
        let cached = complete(at: 1_000)
        let model = await launchedModel(cached: cached)

        #expect(model.snapshot != nil)
        await advance(by: LivePriceRefresh.skeletonDelay)
        #expect(model.snapshot != nil)
    }

    @Test func launchWithoutACacheShowsAFadingSkeletonUntilTheFullLoad() async {
        repository.holdsCalls = true
        let model = viewModel(credentials: credentials)

        let launch = Task { await model.bootstrap() }
        await settle { repository.heldCalls == [.load] }
        await advance(by: LivePriceRefresh.skeletonDelay)

        #expect(model.loadState.skeleton == LaunchSkeleton.withoutCache)
        #expect(!LaunchSkeleton.withoutCache.isRowCountKnown)

        repository.answer(with: complete())
        await launch.value

        #expect(model.snapshot?.holdings.map(\.symbol) == ["AAPL"])
        #expect(repository.calls == [.load])
        #expect(saved.all.count == 1)
    }

    @Test func cachedDataIsRecomputedByCurrentRules() async {
        let stale = PortfolioSnapshot(
            accounts: [makeAccount()],
            holdings: [makeHolding(averageCost: 0)],
            totalMarketValue: 1_100,
            dayGainAmount: 50,
            dayGainPercent: 0.05,
            allTimeGainAmount: 1_100,
            allTimeGainPercent: 0,
            currencyCode: "USD",
            hasMixedCurrencies: false,
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )
        network.set(online: false)
        let model = viewModel(credentials: credentials, cached: stale)

        await model.bootstrap()

        #expect(model.snapshot?.allTimeGainAmount == nil)
    }

    // MARK: - Without a network

    @Test func launchWithoutNetworkShowsTheCacheInGrayAtOnce() async {
        let cached = complete(at: 1_000)
        network.set(online: false)
        let model = viewModel(credentials: credentials, cached: cached)

        await model.bootstrap()

        #expect(model.snapshot?.holdings.map(\.symbol) == ["AAPL"])
        #expect(model.priceStatus == .stale(since: cached.lastUpdated))
        #expect(repository.calls.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(!model.isLiveRefreshing)
    }

    @Test func launchWithoutNetworkOrCacheStaysOnTheSkeletonAndLoadsWhenOnline() async {
        network.set(online: false)
        repository.load = { [result, complete] in result(complete("AAPL", 2_000, .stock)) }
        let model = viewModel(credentials: credentials)

        await model.bootstrap()

        #expect(model.loadState.skeleton == LaunchSkeleton.withoutCache)
        #expect(model.loadState.failure == nil)
        #expect(repository.calls.isEmpty)

        network.set(online: true)
        await settle { model.snapshot != nil }

        #expect(model.snapshot?.holdings.map(\.symbol) == ["AAPL"])
        #expect(model.priceStatus == .current)
        #expect(repository.calls == [.load])
    }

    @Test func losingTheNetworkGraysTheDataAndItsReturnRefreshesIt() async {
        let cached = complete(at: 1_000)
        let model = await launchedModel(cached: cached)
        let lastUpdated = model.snapshot?.lastUpdated
        #expect(model.isLiveRefreshing)

        network.set(online: false)
        await settle()

        #expect(model.priceStatus == .stale(since: lastUpdated))
        #expect(!model.isLiveRefreshing)
        #expect(model.snapshot != nil)

        let callsBefore = repository.calls.count
        repository.refresh = { [repriced] snapshot in
            PortfolioLoadResult(snapshot: repriced(snapshot, 130), partialFailure: PortfolioLoadPartialFailure())
        }
        network.set(online: true)
        await settle { model.priceStatus == .current }

        #expect(repository.calls.count == callsBefore + 1)
        #expect(model.snapshot?.holdings.first?.currentPrice == 130)
        #expect(model.isLiveRefreshing)
        #expect(model.errorMessage == nil)
    }

    // MARK: - Failures with a network

    @Test func transientLaunchFailuresRetryThenShowTheCacheInGray() async {
        let cached = complete(at: 1_000)
        repository.refresh = { _ in throw URLError(.timedOut) }
        let model = viewModel(credentials: credentials, cached: cached)

        let launch = Task { await model.bootstrap() }
        await settle { repository.calls.count == 1 }
        #expect(model.snapshot == nil)

        await advance(by: LivePriceRefresh.backoff(afterFailures: 1))
        await settle { repository.calls.count == 2 }
        #expect(model.snapshot == nil)

        await advance(by: LivePriceRefresh.backoff(afterFailures: 2))
        await launch.value

        #expect(repository.calls == [.refresh, .refresh, .refresh])
        #expect(model.snapshot?.holdings.map(\.symbol) == ["AAPL"])
        #expect(model.priceStatus == .stale(since: cached.lastUpdated))
        // Nothing the user did failed, so nothing is said.
        #expect(model.errorMessage == nil)
    }

    @Test func transientFailuresWithoutACacheEndOnTheErrorPage() async throws {
        repository.load = { throw SnapTradeError.httpStatus(503, "") }
        let model = viewModel(credentials: credentials)

        let launch = Task { await model.bootstrap() }
        await settle { repository.calls.count == 1 }
        await advance(by: LivePriceRefresh.backoff(afterFailures: 1))
        await settle { repository.calls.count == 2 }
        await advance(by: LivePriceRefresh.backoff(afterFailures: 2))
        await launch.value

        let failure = try #require(model.loadState.failure)
        #expect(failure.attention == nil)
        #expect(repository.calls == [.load, .load, .load])
        #expect(model.errorMessage == nil)
    }

    @Test func tryingAgainAfterTheErrorPageLoads() async {
        repository.load = { throw SnapTradeError.decodingFailed(operation: "listAccounts", reason: "") }
        let model = viewModel(credentials: credentials)
        await model.bootstrap()
        #expect(model.loadState.failure != nil)

        let snapshot = complete()
        repository.load = { [result] in result(snapshot) }
        await model.retryLaunch()

        #expect(model.snapshot?.totalMarketValue == 1_100)
        #expect(saved.all.count == 1)
    }

    @Test func rejectedCredentialsWithoutACacheExplainWhyAtOnce() async throws {
        repository.load = { throw SnapTradeError.httpStatus(401, "{\"code\":\"1083\"}") }
        let model = viewModel(credentials: credentials)

        await model.bootstrap()

        let failure = try #require(model.loadState.failure)
        #expect(failure.attention == PortfolioAttention(reason: .credentialsRejected))
        // Retrying can't fix it.
        #expect(repository.calls == [.load])
    }

    @Test func rejectedCredentialsWithACacheShowABannerOverLivePrices() async {
        let cached = complete(at: 1_000)
        repository.load = { throw SnapTradeError.httpStatus(403, "") }
        let model = viewModel(credentials: credentials, cached: cached)

        await model.bootstrap()

        #expect(repository.calls == [.refresh, .load])
        #expect(model.attention == PortfolioAttention(reason: .credentialsRejected))
        #expect(model.priceStatus == .current)
        #expect(model.errorMessage == nil)

        // Fixed: the next holdings load clears it.
        repository.load = { [result] in result(cached) }
        await model.fullRefresh()
        #expect(model.attention == nil)
    }

    @Test func aDisabledConnectionShowsABanner() async {
        let disabled = PortfolioSnapshot.make(
            accounts: [makeAccount(isConnectionDisabled: true)],
            holdings: [makeHolding()],
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )
        repository.load = { [result] in result(disabled) }
        let model = viewModel(credentials: credentials)

        await model.bootstrap()

        #expect(model.attention == PortfolioAttention(reason: .connectionDisabled(providerNames: ["Broker a1"])))
        #expect(model.attention?.title == "Broker a1 holdings couldn’t be refreshed")
    }

    // MARK: - Holdings

    @Test func holdingsAreRefetchedOnceAfterLaunchPrices() async {
        let cached = complete("AAPL", at: 1_000)
        let current = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [makeHolding(), makeHolding(symbol: "MSFT")],
            lastUpdated: Date(timeIntervalSince1970: 2_000)
        )
        repository.load = { [result] in result(current) }
        let model = viewModel(credentials: credentials, cached: cached)

        await model.bootstrap()

        #expect(repository.calls == [.refresh, .load])
        #expect(model.snapshot?.holdings.map(\.symbol) == ["AAPL", "MSFT"])
        #expect(saved.all.last?.holdings.count == 2)
    }

    @Test func holdingsAreRefetchedBehindTheDataOnceAnHourHasPassed() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        await advance(by: LivePriceRefresh.interval)
        // Not due yet: the tick brought prices only.
        #expect(repository.calls == [.refresh, .load, .refresh])

        let refreshed = complete("ETH", at: 3_000, instrumentKind: .crypto)
        repository.load = { [result] in result(refreshed) }
        await settle { clock.pendingSleeps.contains(LivePriceRefresh.interval) }
        clock.advance(by: LivePriceRefresh.holdingsInterval)
        await settle { model.snapshot?.holdings.first?.symbol == "ETH" }

        #expect(repository.calls == [.refresh, .load, .refresh, .refresh, .load])
        #expect(model.snapshot?.holdings.map(\.symbol) == ["ETH"])
        #expect(model.priceStatus == .current)
        #expect(model.errorMessage == nil)
    }

    @Test func returningAfterAnHourRefetchesHoldingsAfterThePrices() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        model.sceneDidEnterBackground()
        let callsBefore = repository.calls.count

        clock.advance(by: LivePriceRefresh.holdingsInterval)
        model.sceneDidBecomeActive()
        await settle { repository.calls.count == callsBefore + 2 }

        #expect(Array(repository.calls.dropFirst(callsBefore)) == [.refresh, .load])
        #expect(model.snapshot != nil)
    }

    @Test func connectingABrokerageRefetchesHoldingsOnReturn() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        model.holdingsMayHaveChanged()
        model.sceneDidEnterBackground()
        let callsBefore = repository.calls.count

        model.sceneDidBecomeActive()
        await settle { repository.calls.count == callsBefore + 2 }

        #expect(Array(repository.calls.dropFirst(callsBefore)) == [.refresh, .load])
    }

    @Test func aFailedHoldingsRefreshIsSilentAndLeavesLivePricesAlone() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        repository.holdsCalls = true
        await settle { clock.pendingSleeps.contains(LivePriceRefresh.interval) }
        clock.advance(by: LivePriceRefresh.holdingsInterval)
        await settle { repository.heldCalls == [.refresh] }
        repository.answer(with: model.snapshot!)
        await settle { repository.heldCalls == [.load] }

        // The next tick waits for the holdings load, which fails.
        await advance(by: LivePriceRefresh.interval)
        #expect(repository.heldCalls == [.load])
        repository.fail(with: URLError(.timedOut))
        await settle()

        // Ticks go on at their usual pace: SnapTrade failing isn't a
        // price failure.
        #expect(clock.pendingSleeps.contains(LivePriceRefresh.interval))
        #expect(model.priceStatus == .current)
        #expect(model.errorMessage == nil)
        #expect(model.snapshot?.holdings.map(\.symbol) == ["BTC"])
    }

    @Test func partialPricesWarnKeepTheUpdateTimeAndSpareTheCache() async throws {
        let cached = complete()
        let partial = PortfolioSnapshot.make(
            accounts: cached.accounts,
            holdings: [makeHolding(currentPrice: nil)],
            lastUpdated: nil
        )
        repository.refresh = { _ in
            PortfolioLoadResult(
                snapshot: partial,
                partialFailure: PortfolioLoadPartialFailure(missingQuoteSymbols: ["AAPL"])
            )
        }
        repository.load = { throw URLError(.timedOut) }
        let model = viewModel(credentials: credentials, cached: cached)

        let launch = Task { await model.bootstrap() }
        await settle { repository.calls.count == 2 }
        // Live refresh has started its own first wait, which may be as long
        // as the holdings retry's: let both begin before time moves.
        let backoff = LivePriceRefresh.backoff(afterFailures: 1)
        let waits = backoff == LivePriceRefresh.interval ? 2 : 1
        await settle { clock.pendingSleeps.count(where: { $0 == backoff }) == waits }
        await advance(by: backoff)
        await settle { repository.calls.count == 3 }
        await advance(by: LivePriceRefresh.backoff(afterFailures: 2))
        await launch.value

        #expect(model.snapshot?.holdings.first?.currentPrice == nil)
        #expect(model.snapshot?.totalMarketValue == nil)
        #expect(model.snapshot?.lastUpdated == cached.lastUpdated)
        #expect(try #require(model.errorMessage).contains("AAPL"))
        #expect(saved.all.isEmpty)
    }

    @Test func completePricesAdvanceTimeAndSave() async {
        let cached = complete(at: 1_000)
        let fresh = complete(at: 2_000)
        repository.refresh = { [result] _ in result(fresh) }
        repository.load = { throw SnapTradeError.decodingFailed(operation: "listAccounts", reason: "") }
        let model = viewModel(credentials: credentials, cached: cached)

        await model.bootstrap()

        #expect(model.snapshot?.lastUpdated == fresh.lastUpdated)
        #expect(saved.all.map(\.lastUpdated) == [fresh.lastUpdated])
        #expect(model.priceStatus == .current)
        #expect(model.errorMessage == nil)
    }

    @Test func mixedCurrenciesExplainTheMissingTotals() async throws {
        let mixed = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [makeHolding(), makeHolding(symbol: "SHOP", currencyCode: "CAD")]
        )
        repository.load = { [result] in result(mixed) }
        let model = viewModel(credentials: credentials)

        await model.bootstrap()

        #expect(try #require(model.errorMessage).contains("more than one currency"))
        #expect(model.snapshot?.totalMarketValue == nil)
    }

    @Test func filteringToOneCurrencyBringsTotalsBack() async {
        let mixed = PortfolioSnapshot.make(
            accounts: [makeAccount(id: "a1"), makeAccount(id: "a2")],
            holdings: [
                makeHolding(accountID: "a1"),
                makeHolding(symbol: "SHOP", accountID: "a2", currencyCode: "CAD")
            ]
        )
        repository.load = { [result] in result(mixed) }
        let model = viewModel(credentials: credentials)
        await model.bootstrap()

        #expect(model.displaySnapshot?.totalMarketValue == nil)

        model.selectedProviderName = "Broker a1"

        #expect(model.displaySnapshot?.totalMarketValue == 1_100)
    }

    // MARK: - Live prices

    @Test func liveRefreshFetchesOnlyHoldingsInSessionEveryInterval() async {
        let date = clock.now
        let cached = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [
                makeHolding(symbol: "BTC", instrumentKind: .crypto),
                makeHolding(
                    symbol: "AAPL",
                    marketSession: HoldingMarketSession(
                        start: date.addingTimeInterval(3_600),
                        regularStart: date.addingTimeInterval(7_200),
                        regularEnd: date.addingTimeInterval(30_000),
                        end: date.addingTimeInterval(44_000)
                    )
                )
            ],
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )
        let model = await launchedModel(cached: cached)
        #expect(repository.refreshedSymbols == [["AAPL", "BTC"]])

        await advance(by: LivePriceRefresh.interval)
        await settle { repository.refreshedSymbols.count == 2 }
        await advance(by: LivePriceRefresh.interval)
        await settle { repository.refreshedSymbols.count == 3 }

        #expect(repository.refreshedSymbols == [["AAPL", "BTC"], ["BTC"], ["BTC"]])
        #expect(model.isLive(cached.holdings[0]))
        #expect(!model.isLive(cached.holdings[1]))
    }

    @Test func numbersChangeInPlaceAsLivePricesArrive() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        let total = model.snapshot?.totalMarketValue

        repository.refresh = { [repriced] snapshot in
            PortfolioLoadResult(snapshot: repriced(snapshot, 115), partialFailure: PortfolioLoadPartialFailure())
        }
        await advance(by: LivePriceRefresh.interval)
        await settle { model.snapshot?.totalMarketValue != total }

        #expect(model.snapshot?.totalMarketValue == 1_150)
        #expect(model.priceStatus == .current)
    }

    @Test func liveRefreshStopsInTheBackgroundAndRefreshesEverythingOnReturn() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        model.sceneDidEnterBackground()
        let callsBefore = repository.calls.count

        await advance(by: LivePriceRefresh.interval * 3)

        #expect(repository.calls.count == callsBefore)
        #expect(!model.isLiveRefreshing)

        model.sceneDidBecomeActive()
        await settle { repository.calls.count == callsBefore + 1 }

        // Not a launch: the data stayed on screen throughout.
        #expect(model.snapshot != nil)
        #expect(repository.calls.last == .refresh)
        #expect(model.isLiveRefreshing)
    }

    @Test func returningWithTheConnectionLostGraysThePricesUntilNewOnesArrive() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        let lastUpdated = model.snapshot?.lastUpdated
        model.sceneDidEnterBackground()
        repository.marketDataConnected = false
        repository.holdsCalls = true

        model.sceneDidBecomeActive()
        await settle { repository.heldCalls == [.refresh] }
        #expect(model.priceStatus == .stale(since: lastUpdated))

        repository.marketDataConnected = true
        repository.answer(with: repriced(model.snapshot!, to: 120))
        await settle { model.priceStatus == .current }
        #expect(model.priceStatus == .current)
        #expect(model.snapshot?.holdings.first?.currentPrice == 120)
    }

    @Test func returningWithTheConnectionLiveKeepsTheColors() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        model.sceneDidEnterBackground()
        repository.holdsCalls = true

        model.sceneDidBecomeActive()
        await settle { repository.heldCalls == [.refresh] }

        #expect(model.priceStatus == .current)
    }

    @Test func aLostConnectionLeavesPricesOfAClosedMarketInColor() async {
        let opening = clock.now.addingTimeInterval(600)
        let cached = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [
                makeHolding(
                    marketSession: HoldingMarketSession(
                        start: opening,
                        regularStart: opening.addingTimeInterval(3_600),
                        regularEnd: opening.addingTimeInterval(30_000),
                        end: opening.addingTimeInterval(44_000)
                    )
                )
            ],
            lastUpdated: clock.now.addingTimeInterval(-60)
        )
        let model = await launchedModel(cached: cached)
        model.sceneDidEnterBackground()
        repository.marketDataConnected = false
        repository.holdsCalls = true

        model.sceneDidBecomeActive()
        await settle { repository.heldCalls == [.refresh] }

        #expect(model.priceStatus == .current)
    }

    @Test func aConnectionLostWhileLiveGraysThePricesAtTheNextTick() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        let lastUpdated = model.snapshot?.lastUpdated
        repository.marketDataConnected = false
        repository.holdsCalls = true

        await advance(by: LivePriceRefresh.interval)
        await settle { repository.heldCalls == [.refresh] }

        #expect(model.priceStatus == .stale(since: lastUpdated))
        #expect(model.errorMessage == nil)
    }

    @Test func liveRefreshWaitsForTheNextSessionWhenNothingTrades() async {
        let opening = clock.now.addingTimeInterval(600)
        let cached = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [
                makeHolding(
                    marketSession: HoldingMarketSession(
                        start: opening,
                        regularStart: opening.addingTimeInterval(3_600),
                        regularEnd: opening.addingTimeInterval(30_000),
                        end: opening.addingTimeInterval(44_000)
                    )
                )
            ],
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )
        let model = await launchedModel(cached: cached)
        let callsBefore = repository.calls.count

        await advance(by: LivePriceRefresh.interval)
        await advance(by: LivePriceRefresh.interval)
        #expect(repository.calls.count == callsBefore)

        await advance(by: .seconds(600))
        await settle { repository.calls.count == callsBefore + 1 }
        #expect(repository.refreshedSymbols.last == ["AAPL"])
        #expect(model.isLive(cached.holdings[0]))
    }

    @Test func repeatedLiveFailuresGrayThePricesUntilOneSucceeds() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        let lastUpdated = model.snapshot?.lastUpdated

        repository.refresh = { _ in throw URLError(.timedOut) }
        await advance(by: LivePriceRefresh.interval)
        await advance(by: LivePriceRefresh.backoff(afterFailures: 1))
        #expect(model.priceStatus == .current)
        await advance(by: LivePriceRefresh.backoff(afterFailures: 2))

        #expect(model.priceStatus == .stale(since: lastUpdated))
        #expect(model.errorMessage == nil)

        repository.refresh = { [result] snapshot in result(snapshot) }
        await advance(by: LivePriceRefresh.backoff(afterFailures: 3))
        await settle { model.priceStatus == .current }

        #expect(model.priceStatus == .current)
    }

    @Test func aTickThatLosesAPriceIsRetriedBeforeItShows() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        let lost = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [makeHolding(symbol: "BTC", currentPrice: nil, instrumentKind: .crypto)],
            lastUpdated: nil
        )
        repository.refresh = { _ in
            PortfolioLoadResult(
                snapshot: lost,
                partialFailure: PortfolioLoadPartialFailure(missingQuoteSymbols: ["BTC"])
            )
        }

        await advance(by: LivePriceRefresh.interval)
        await advance(by: LivePriceRefresh.backoff(afterFailures: 1))
        #expect(model.snapshot?.holdings.first?.currentPrice == 110)

        // The third time it's news: the price is shown as missing.
        await advance(by: LivePriceRefresh.backoff(afterFailures: 2))
        await settle { model.snapshot?.holdings.first?.currentPrice == nil }
        #expect(model.snapshot?.totalMarketValue == nil)
        #expect(model.errorMessage == nil)
    }

    // MARK: - Credentials

    @Test func newCredentialsAreALaunchWithTheOldCacheDeleted() async throws {
        let store = CredentialsStore(storage: InMemoryCredentialsStorage(credentials))
        let cached = complete("OLD", at: 1_000)
        repository.load = { [result] in result(cached) }
        let model = viewModel(store: store, cached: cached)
        await model.bootstrap()
        #expect(model.snapshot?.holdings.map(\.symbol) == ["OLD"])

        var otherUser = credentials
        otherUser.userId = "other"
        try store.save(otherUser)
        repository.holdsCalls = true
        let refresh = Task { await model.fullRefresh() }
        await settle { repository.heldCalls == [.load] }

        #expect(saved.deletes == 1)
        #expect(model.snapshot == nil)
        #expect(model.loadState.skeleton != nil)

        repository.answer(with: complete("NEW"))
        await refresh.value
        #expect(model.snapshot?.holdings.map(\.symbol) == ["NEW"])
    }

    // MARK: - Settings

    @Test func minimumMarketValueIsOneSettingSavedToTheInjectedDefaults() {
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let model = viewModel(credentials: credentials, cached: complete())

        model.minPriceThreshold = 2_000

        #expect(defaults.double(forKey: AppSettingKey.minPriceThreshold) == 2_000)
        #expect(viewModel(credentials: credentials).minPriceThreshold == 2_000)
    }

    @Test func hiddenHoldingCountFollowsTheMinimumAndTheSelectedProvider() {
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let snapshot = PortfolioSnapshot.make(
            accounts: [makeAccount(id: "a1"), makeAccount(id: "a2")],
            holdings: [
                makeHolding(symbol: "BIG", accountID: "a1", quantity: 10, currentPrice: 100),
                makeHolding(symbol: "DUST", accountID: "a1", quantity: 1, currentPrice: 0.5),
                makeHolding(symbol: "SMALL", accountID: "a2", quantity: 1, currentPrice: 20),
                makeHolding(symbol: "NOPRICE", accountID: "a2", currentPrice: nil)
            ]
        )
        let model = DashboardViewModel(
            credentialsStore: CredentialsStore(storage: InMemoryCredentialsStorage(credentials)),
            repository: repository,
            defaults: defaults,
            initialSnapshot: snapshot,
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in },
            deleteCachedSnapshot: {},
            networkMonitor: network
        )

        model.setMinimumMarketValue(1)
        #expect(model.hiddenHoldingCount == 1)

        // An unpriced holding is never hidden: its value is unknown, not small.
        model.setMinimumMarketValue(50)
        #expect(model.hiddenHoldingCount == 2)
        #expect(model.displaySnapshot?.holdings.map(\.symbol).sorted() == ["BIG", "NOPRICE"])

        model.selectedProviderName = "Broker a2"
        #expect(model.hiddenHoldingCount == 1)
    }

    @Test func aMinimumMarketValueThatIsntANonNegativeNumberShowsEverything() {
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let model = viewModel(credentials: credentials)

        model.setMinimumMarketValue(-5)
        #expect(model.minPriceThreshold == 0)

        model.setMinimumMarketValue(.nan)
        #expect(model.minPriceThreshold == 0)

        model.setMinimumMarketValue(12.5)
        #expect(model.minPriceThreshold == 12.5)
    }

    // MARK: - Refreshes in flight

    @Test func aSecondHoldingsRefreshStartsNoSecondLoad() async {
        let model = await launchedModel(cached: complete(at: 1_000))
        repository.holdsCalls = true
        let callsBefore = repository.calls.count

        let first = Task { await model.fullRefresh() }
        await settle { repository.heldCalls == [.load] }
        let second = Task { await model.fullRefresh() }
        await settle()

        #expect(repository.calls.count == callsBefore + 1)

        let fresh = complete(at: 3_000)
        repository.answer(with: fresh)
        await first.value
        await second.value

        #expect(model.snapshot?.lastUpdated == fresh.lastUpdated)
        #expect(!model.isLoading)
        #expect(repository.calls.count == callsBefore + 1)
    }

    @Test func aHoldingsLoadReplacesALiveTickThatWaitsForIt() async {
        let model = await launchedModel(cached: complete("BTC", at: 1_000, instrumentKind: .crypto))
        repository.holdsCalls = true

        await advance(by: LivePriceRefresh.interval)
        await settle { repository.heldCalls == [.refresh] }

        let full = Task { await model.fullRefresh() }
        await settle { repository.heldCalls == [.load] }

        #expect(repository.heldCalls == [.load])

        repository.answer(with: complete("MSFT"))
        await full.value
        await settle()

        #expect(model.snapshot?.holdings.map(\.symbol) == ["MSFT"])
        #expect(!model.isLoading)
    }

    @Test func aReplacedLoadsLateResultIsDiscarded() async throws {
        let store = CredentialsStore(storage: InMemoryCredentialsStorage(credentials))
        let model = viewModel(store: store)
        repository.holdsCalls = true
        repository.honorsCancellation = false

        let first = Task { await model.bootstrap() }
        await settle { repository.heldCalls == [.load] }

        var otherUser = credentials
        otherUser.userId = "other"
        try store.save(otherUser)
        let second = Task { await model.fullRefresh() }
        await settle { repository.heldCalls == [.load, .load] }

        // The first load answers for credentials that are no longer saved.
        repository.answer(0, with: complete("OLD"))
        await settle()

        #expect(model.snapshot == nil)
        #expect(saved.all.isEmpty)

        // Bootstrap waits for the load that replaced its own.
        repository.answer(0, with: complete("NEW"))
        await first.value
        await second.value

        #expect(model.snapshot?.holdings.map(\.symbol) == ["NEW"])
        #expect(saved.all.map { $0.holdings.map(\.symbol) } == [["NEW"]])
    }
}

private nonisolated struct UncheckedSnapshot: @unchecked Sendable {
    let value: PortfolioSnapshot?
}
