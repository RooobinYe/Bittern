//
//  PreviewSupport.swift
//  Bittern
//

#if DEBUG
import Foundation

/// Dependencies for SwiftUI previews. Previews run on the developer's machine,
/// so they must never read the real Keychain, the on-disk cache, or the network.
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
            initialSnapshot: snapshot,
            loadCachedSnapshot: { nil },
            saveCachedSnapshot: { _ in }
        )
    }

    /// A session whose every request fails as if the device were offline.
    static let offlineSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineURLProtocol.self]
        return URLSession(configuration: configuration)
    }()
}

private final class PreviewCredentialsStorage: CredentialsStorage {
    private var credentials: SnapTradeCredentials?

    func load() throws -> SnapTradeCredentials? { credentials }
    func save(_ credentials: SnapTradeCredentials) throws { self.credentials = credentials }
    func delete() throws { credentials = nil }
}

/// Refreshing a preview leaves its data as it is.
private struct PreviewPortfolioRepository: PortfolioRepository {
    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult {
        throw URLError(.notConnectedToInternet)
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult {
        PortfolioLoadResult(snapshot: snapshot, partialFailure: PortfolioLoadPartialFailure())
    }
}

nonisolated private final class OfflineURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
#endif
