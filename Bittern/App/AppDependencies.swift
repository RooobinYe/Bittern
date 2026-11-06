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

    static func live() -> AppDependencies {
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
}
