//
//  RepositoryEnvironment.swift
//  Bittern
//

import SwiftUI

extension EnvironmentValues {
    /// The app sets the live repository at its root. Anything outside that
    /// root, such as a preview, gets one that fails every request rather than
    /// reaching the network.
    @Entry var portfolioRepository: any PortfolioRepository = UnavailablePortfolioRepository()
}

struct UnavailablePortfolioRepository: PortfolioRepository {
    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult {
        throw URLError(.notConnectedToInternet)
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult {
        throw URLError(.notConnectedToInternet)
    }

    func priceHistory(for holding: PortfolioHolding, range: HoldingChartRange) async throws -> HoldingPriceSeries {
        throw URLError(.notConnectedToInternet)
    }

    func portfolioHistory(credentials: SnapTradeCredentials, accountIDs: [String]) async throws -> PortfolioHistory {
        throw URLError(.notConnectedToInternet)
    }

    func registerUser(apiKey: SnapTradeCredentials) async throws -> SnapTradeCredentials {
        throw URLError(.notConnectedToInternet)
    }

    func connectionPortalURL(credentials: SnapTradeCredentials, darkMode: Bool) async throws -> URL {
        throw URLError(.notConnectedToInternet)
    }
}
