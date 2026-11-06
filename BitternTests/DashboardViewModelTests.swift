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

private final class StubRepository: PortfolioRepository {
    var load: () throws -> PortfolioLoadResult = { throw URLError(.notConnectedToInternet) }
    var refresh: () throws -> PortfolioLoadResult = { throw URLError(.notConnectedToInternet) }

    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult {
        try load()
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult {
        try refresh()
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

/// Keychain and disk are replaced, so running these on any simulator leaves the
/// real credentials and cached portfolio there untouched.
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

    private func viewModel(
        credentials: SnapTradeCredentials?,
        cached: PortfolioSnapshot? = nil
    ) -> DashboardViewModel {
        let saved = saved
        let box = UncheckedSnapshot(value: cached)
        return DashboardViewModel(
            credentialsStore: CredentialsStore(storage: InMemoryCredentialsStorage(credentials)),
            repository: repository,
            loadCachedSnapshot: { box.value },
            saveCachedSnapshot: { saved.append($0) }
        )
    }

    private func complete(at time: TimeInterval = 2_000) -> PortfolioSnapshot {
        .make(
            accounts: [makeAccount()],
            holdings: [makeHolding()],
            lastUpdated: Date(timeIntervalSince1970: time)
        )
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
}

private nonisolated struct UncheckedSnapshot: @unchecked Sendable {
    let value: PortfolioSnapshot?
}
