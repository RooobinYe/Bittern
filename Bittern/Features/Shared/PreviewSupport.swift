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

    /// A credentials store holding made-up credentials, kept in memory.
    static func demoCredentialsStore() -> CredentialsStore {
        let store = credentialsStore()
        try? store.save(
            SnapTradeCredentials(
                clientId: "DEMO-CLIENT",
                consumerKey: "demo-consumer-key",
                userId: "demo-user",
                userSecret: "demo-user-secret"
            )
        )
        return store
    }

    /// A dashboard model showing `snapshot`, with no cache and no network.
    static func dashboardViewModel(
        credentialsStore: CredentialsStore,
        snapshot: PortfolioSnapshot? = DemoPortfolio.snapshot
    ) -> DashboardViewModel {
        DashboardViewModel(
            credentialsStore: credentialsStore,
            repository: DemoPortfolioRepository(),
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

/// The demo portfolio with made-up price and balance history. Refreshing
/// leaves the data as it is; connecting a brokerage is offline.
struct DemoPortfolioRepository: PortfolioRepository {
    private let offline = UnavailablePortfolioRepository()

    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult {
        PortfolioLoadResult(snapshot: DemoPortfolio.snapshot, partialFailure: PortfolioLoadPartialFailure())
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult {
        PortfolioLoadResult(snapshot: snapshot, partialFailure: PortfolioLoadPartialFailure())
    }

    func priceHistory(for holding: PortfolioHolding, range: HoldingChartRange) async throws -> HoldingPriceSeries {
        let price = holding.currentPrice ?? 100
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        guard range == .oneDay else {
            let daysThisYear = calendar.dateComponents(
                [.day],
                from: calendar.dateInterval(of: .year, for: today)?.start ?? today,
                to: today
            ).day ?? 0
            let count = switch range {
            case .oneDay, .fiveDays: 5 * 78
            case .oneMonth: 30 * 16
            case .threeMonths: 63
            case .yearToDate: max(daysThisYear, 2)
            case .oneYear: 252
            case .fiveYears: 260
            case .max: 400
            }
            let step: TimeInterval = switch range {
            case .oneDay, .fiveDays: 5 * 60
            // Every 90 minutes around the clock: a month, with no gap
            // long enough to read as a trading session's end.
            case .oneMonth: 5_400
            case .threeMonths, .yearToDate, .oneYear: 86_400
            case .fiveYears, .max: 7 * 86_400
            }
            let points = (0..<count).map { index in
                let progress = Double(index) / Double(count - 1)
                return HoldingPricePoint(
                    date: today.addingTimeInterval(-Double(count - 1 - index) * step),
                    price: price * (0.82 + 0.18 * progress + 0.04 * sin(Double(index) / 7))
                )
            }
            return HoldingPriceSeries(
                points: points,
                timeDomain: nil,
                baselinePrice: range == .yearToDate ? price * 0.8 : nil
            )
        }

        // 04:00 to 20:00, with regular trading from 09:30 to 16:00.
        let start = today.addingTimeInterval(4 * 3_600)
        let end = today.addingTimeInterval(20 * 3_600)
        let regularOpen = today.addingTimeInterval(9.5 * 3_600)
        let regularClose = today.addingTimeInterval(16 * 3_600)
        let close = holding.previousClose ?? price
        let points = stride(from: start, through: end, by: 5 * 60).map { date in
            let elapsed = date.timeIntervalSince(start) / end.timeIntervalSince(start)
            let session: PriceChartSession = date < regularOpen
                ? .preMarket
                : date >= regularClose ? .postMarket : .regular
            return HoldingPricePoint(
                date: date,
                price: close + (price - close) * elapsed + close * 0.006 * sin(elapsed * 18),
                session: session
            )
        }
        return HoldingPriceSeries(
            points: points,
            timeDomain: PriceChartTimeDomain(start: start, end: end),
            baselinePrice: close
        )
    }

    func portfolioHistory(credentials: SnapTradeCredentials, accountIDs: [String]) async throws -> PortfolioHistory {
        let today = Calendar(identifier: .gregorian).startOfDay(for: Date())
        let points = (0..<400).map { index in
            PortfolioHistoryPoint(
                date: today.addingTimeInterval(-Double(399 - index) * 86_400),
                totalValue: 70_000 + Double(index) * 55 + 2_500 * sin(Double(index) / 11)
            )
        }
        return PortfolioHistory(points: points, currencyCode: "USD")
    }

    func registerUser(apiKey: SnapTradeCredentials) async throws -> SnapTradeCredentials {
        try await offline.registerUser(apiKey: apiKey)
    }

    func connectionPortalURL(credentials: SnapTradeCredentials, darkMode: Bool) async throws -> URL {
        try await offline.connectionPortalURL(credentials: credentials, darkMode: darkMode)
    }
}
#endif
