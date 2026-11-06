//
//  PreviewSupport.swift
//  Bittern
//

#if DEBUG
import Foundation

/// Dependencies for SwiftUI previews. Previews run on the developer's machine,
/// so they must never read the real Keychain, the on-disk cache, the saved
/// settings or the network.
enum PreviewSupport {
    /// A credentials store with nothing saved and nowhere to save to.
    static func credentialsStore() -> CredentialsStore {
        CredentialsStore(storage: PreviewCredentialsStorage())
    }

    /// A dashboard model showing `snapshot`, with no cache and no network.
    static func dashboardViewModel(
        credentialsStore: CredentialsStore,
        snapshot: PortfolioSnapshot? = DemoPortfolio.snapshot
    ) -> DashboardViewModel {
        DashboardViewModel(
            credentialsStore: credentialsStore,
            repository: PreviewPortfolioRepository(),
            defaults: UserDefaults(suiteName: "BitternPreview") ?? .standard,
            initialSnapshot: snapshot,
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in }
        )
    }
}

private final class PreviewCredentialsStorage: CredentialsStorage {
    private var credentials: SnapTradeCredentials?

    func load() throws -> SnapTradeCredentials? { credentials }
    func save(_ credentials: SnapTradeCredentials) throws { self.credentials = credentials }
    func delete() throws { credentials = nil }
}

/// Refreshing a preview leaves its data as it is; anything else is offline.
private struct PreviewPortfolioRepository: PortfolioRepository {
    private let offline = UnavailablePortfolioRepository()

    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult {
        try await offline.loadPortfolio(credentials: credentials)
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult {
        PortfolioLoadResult(snapshot: snapshot, partialFailure: PortfolioLoadPartialFailure())
    }

    func priceHistory(for holding: PortfolioHolding, range: HoldingChartRange) async throws -> HoldingPriceSeries {
        try await offline.priceHistory(for: holding, range: range)
    }

    func portfolioHistory(credentials: SnapTradeCredentials, accountIDs: [String]) async throws -> PortfolioHistory {
        try await offline.portfolioHistory(credentials: credentials, accountIDs: accountIDs)
    }

    func registerUser(apiKey: SnapTradeCredentials) async throws -> SnapTradeCredentials {
        try await offline.registerUser(apiKey: apiKey)
    }

    func connectionPortalURL(credentials: SnapTradeCredentials, darkMode: Bool) async throws -> URL {
        try await offline.connectionPortalURL(credentials: credentials, darkMode: darkMode)
    }
}
#endif
