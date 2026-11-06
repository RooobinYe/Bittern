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
    var refresh: () throws -> PortfolioLoadResult = { throw URLError(.notConnectedToInternet) }
    var holdsCalls = false
    var honorsCancellation = true
    private(set) var calls: [Call] = []
    private var held: [HeldCall] = []
    private var nextID = 0

    var heldCalls: [Call] { held.map(\.call) }

    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult {
        calls.append(.load)
        return holdsCalls ? try await hold(.load) : try load()
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult {
        calls.append(.refresh)
        return holdsCalls ? try await hold(.refresh) : try refresh()
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

    /// Answers the held call at `index`, oldest first.
    func answer(_ index: Int = 0, with snapshot: PortfolioSnapshot) {
        held.remove(at: index).continuation.resume(
            returning: PortfolioLoadResult(snapshot: snapshot, partialFailure: PortfolioLoadPartialFailure())
        )
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

    var all: [PortfolioSnapshot] { lock.withLock { values } }

    func append(_ snapshot: PortfolioSnapshot) {
        lock.withLock { values.append(snapshot) }
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

/// Keychain, disk and settings are replaced, so running these on any simulator
/// leaves the real credentials, cached portfolio and preferences untouched.
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
        let box = UncheckedSnapshot(value: cached)
        return DashboardViewModel(
            credentialsStore: store,
            repository: repository,
            defaults: defaults,
            loadCachedSnapshot: { box.value },
            saveCachedSnapshot: { saved.append($0) }
        )
    }

    private func complete(
        _ symbol: String = "AAPL",
        at time: TimeInterval = 2_000
    ) -> PortfolioSnapshot {
        .make(
            accounts: [makeAccount()],
            holdings: [makeHolding(symbol: symbol)],
            lastUpdated: Date(timeIntervalSince1970: time)
        )
    }

    /// A model that has finished its first load, with later calls held.
    private func bootstrappedModel() async -> DashboardViewModel {
        let first = complete(at: 1_000)
        repository.refresh = {
            PortfolioLoadResult(snapshot: first, partialFailure: PortfolioLoadPartialFailure())
        }
        let model = viewModel(credentials: credentials, cached: first)
        await model.bootstrap()
        repository.holdsCalls = true
        return model
    }

    @Test func withoutCredentialsNothingIsLoadedAndNoSnapshotExists() async {
        let model = viewModel(credentials: nil)

        await model.bootstrap()

        guard case .notLoaded = model.loadState else {
            Issue.record("expected notLoaded, got \(model.loadState)")
            return
        }
        #expect(model.snapshot == nil)
        #expect(model.displaySnapshot == nil)
        #expect(model.sortedHoldings.isEmpty)
    }

    @Test func startsInLoadingWithCredentials() {
        let model = viewModel(credentials: credentials)

        guard case .loading = model.loadState else {
            Issue.record("expected loading, got \(model.loadState)")
            return
        }
    }

    @Test func firstLoadFailureWithNoDataIsAFailedState() async {
        let model = viewModel(credentials: credentials)

        await model.bootstrap()

        guard case .failed(let message) = model.loadState else {
            Issue.record("expected failed, got \(model.loadState)")
            return
        }
        #expect(message.contains("internet"))
        #expect(model.errorMessage == nil)
    }

    @Test func retryAfterFailureLoads() async {
        let model = viewModel(credentials: credentials)
        await model.bootstrap()

        let snapshot = complete()
        repository.load = {
            PortfolioLoadResult(snapshot: snapshot, partialFailure: PortfolioLoadPartialFailure())
        }
        await model.fullRefresh()

        #expect(model.snapshot?.totalMarketValue == 1_100)
        #expect(saved.all.count == 1)
    }

    @Test func refreshFailureKeepsExistingDataAndWarns() async throws {
        let model = viewModel(credentials: credentials, cached: complete())

        await model.bootstrap()

        #expect(model.snapshot?.totalMarketValue == 1_100)
        #expect(try #require(model.errorMessage).contains("internet"))
        #expect(saved.all.isEmpty)
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
        let model = viewModel(credentials: credentials, cached: stale)

        await model.bootstrap()

        #expect(model.snapshot?.allTimeGainAmount == nil)
    }

    @Test func partialRefreshWarnsKeepsUpdateTimeAndSparesTheCache() async throws {
        let cached = complete()
        let partial = PortfolioSnapshot.make(
            accounts: cached.accounts,
            holdings: [makeHolding(currentPrice: nil)],
            lastUpdated: nil
        )
        repository.refresh = {
            PortfolioLoadResult(
                snapshot: partial,
                partialFailure: PortfolioLoadPartialFailure(missingQuoteSymbols: ["AAPL"])
            )
        }
        let model = viewModel(credentials: credentials, cached: cached)

        await model.bootstrap()

        #expect(model.snapshot?.holdings.first?.currentPrice == nil)
        #expect(model.snapshot?.totalMarketValue == nil)
        #expect(model.snapshot?.lastUpdated == cached.lastUpdated)
        #expect(try #require(model.errorMessage).contains("AAPL"))
        #expect(saved.all.isEmpty)
    }

    @Test func completeRefreshAdvancesTimeAndSaves() async {
        let cached = complete(at: 1_000)
        let fresh = complete(at: 2_000)
        repository.refresh = {
            PortfolioLoadResult(snapshot: fresh, partialFailure: PortfolioLoadPartialFailure())
        }
        let model = viewModel(credentials: credentials, cached: cached)

        await model.bootstrap()

        #expect(model.snapshot?.lastUpdated == fresh.lastUpdated)
        #expect(saved.all.map(\.lastUpdated) == [fresh.lastUpdated])
        #expect(model.errorMessage == nil)
    }

    @Test func mixedCurrenciesExplainTheMissingTotals() async throws {
        let mixed = PortfolioSnapshot.make(
            accounts: [makeAccount()],
            holdings: [makeHolding(), makeHolding(symbol: "SHOP", currencyCode: "CAD")]
        )
        repository.load = {
            PortfolioLoadResult(snapshot: mixed, partialFailure: PortfolioLoadPartialFailure())
        }
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
        repository.load = {
            PortfolioLoadResult(snapshot: mixed, partialFailure: PortfolioLoadPartialFailure())
        }
        let model = viewModel(credentials: credentials)
        await model.bootstrap()

        #expect(model.displaySnapshot?.totalMarketValue == nil)

        model.selectedProviderName = "Broker a1"

        #expect(model.displaySnapshot?.totalMarketValue == 1_100)
    }

    @Test func minimumMarketValueIsOneSettingSavedToTheInjectedDefaults() {
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let model = viewModel(credentials: credentials, cached: complete())

        model.minPriceThreshold = 2_000

        #expect(defaults.double(forKey: AppSettingKey.minPriceThreshold) == 2_000)
        #expect(viewModel(credentials: credentials).minPriceThreshold == 2_000)
    }

    // MARK: - Refreshes in flight

    @Test func aSecondRefreshJoinsTheOneInFlight() async {
        let model = await bootstrappedModel()
        let callsBefore = repository.calls.count

        let first = Task { await model.refresh() }
        await settle { repository.heldCalls == [.refresh] }
        let second = Task { await model.refresh() }
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

    @Test func aFullRefreshReplacesAPriceRefreshThatWaitsForIt() async {
        let model = await bootstrappedModel()
        let priceRefreshFinished = Flag()

        let price = Task {
            await model.refresh()
            priceRefreshFinished.isSet = true
        }
        await settle { repository.heldCalls == [.refresh] }

        let full = Task { await model.fullRefresh() }
        await settle { repository.heldCalls == [.load] }

        #expect(repository.heldCalls == [.load])
        #expect(!priceRefreshFinished.isSet)

        repository.answer(with: complete("MSFT"))
        await full.value
        await price.value

        #expect(priceRefreshFinished.isSet)
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
