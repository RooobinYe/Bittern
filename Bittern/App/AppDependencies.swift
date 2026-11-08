//
//  AppDependencies.swift
//  Bittern
//
//  The one place that creates network clients and wires them together.
//

import Foundation

struct AppDependencies {
    let credentialsStore: CredentialsStore
    let repository: any PortfolioRepository
    let logoSource: LogoSource
    var networkMonitor: any NetworkMonitor = SystemNetworkMonitor()
    var loadCachedSnapshot: @Sendable () async -> PortfolioSnapshot? = { await PortfolioCache.loadAsync() }
    var saveCachedSnapshot: @Sendable (PortfolioSnapshot) -> Void = { PortfolioCache.save($0) }
    var deleteCachedSnapshot: @Sendable () throws -> Void = { try PortfolioCache.clear() }

    static func live() -> AppDependencies {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BITTERN_DEMO"] == "1" {
            return demo()
        }
        #endif

        let session = URLSession.shared
        let currentDate: @Sendable () -> Date = { Date() }
        let brandfetch = BrandfetchClient(session: session)

        let credentialsStore = CredentialsStore()
        #if DEBUG
        DebugSnapTradeCredentialsInjector.injectIfConfigured(into: credentialsStore)
        #endif

        return AppDependencies(
            credentialsStore: credentialsStore,
            repository: LivePortfolioRepository(
                makeSnapTradeClient: { credentials in
                    SnapTradeClient(credentials: credentials, session: session, currentDate: currentDate)
                },
                yahoo: YahooFinanceClient(session: session, currentDate: currentDate),
                brandfetch: brandfetch,
                currentDate: currentDate
            ),
            logoSource: .remote(
                LogoImageLoader { name, url in
                    try await brandfetch.image(for: name, at: url)
                }
            )
        )
    }

    #if DEBUG
    /// Made-up data for screenshots: no Keychain, no cache, no network.
    /// `BITTERN_DEMO_STATE` picks a state to show (see `DemoScenario`).
    static func demo() -> AppDependencies {
        let scenario = DemoScenario.current
        let cached = scenario.cachedSnapshot
        return AppDependencies(
            credentialsStore: PreviewSupport.demoCredentialsStore(),
            repository: DemoPortfolioRepository(scenario: scenario),
            logoSource: .none,
            networkMonitor: FixedNetworkMonitor(isOnline: scenario.isOnline),
            loadCachedSnapshot: { cached },
            saveCachedSnapshot: { _ in },
            deleteCachedSnapshot: {}
        )
    }
    #endif
}
