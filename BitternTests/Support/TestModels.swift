import Foundation
@testable import Bittern

func makeHolding(
    symbol: String = "AAPL",
    accountID: String = "a1",
    quantity: Double = 10,
    averageCost: Double? = 100,
    currentPrice: Double? = 110,
    previousClose: Double? = 105,
    currencyCode: String = "USD",
    dividendsReceived: Double? = 0
) -> PortfolioHolding {
    PortfolioHolding(
        id: "\(accountID)-\(symbol)",
        accountID: accountID,
        symbol: symbol,
        name: symbol,
        instrumentKind: .stock,
        logoURL: nil,
        accountName: "Account",
        quantity: quantity,
        quantityDisplay: nil,
        averageCost: averageCost,
        currentPrice: currentPrice,
        previousClose: previousClose,
        preMarketChange: nil,
        postMarketChange: nil,
        currencyCode: currencyCode,
        dividendsReceived: dividendsReceived
    )
}

func makeAccount(id: String = "a1", currencyCode: String = "USD") -> PortfolioAccount {
    PortfolioAccount(
        id: id,
        name: "Account \(id)",
        institutionName: "Broker \(id)",
        providerLogoURL: nil,
        isConnectionDisabled: false,
        currencyCode: currencyCode
    )
}

/// The live repository with every client on `session`.
func makeLiveRepository(
    session: URLSession,
    currentDate: @escaping @Sendable () -> Date
) -> LivePortfolioRepository {
    LivePortfolioRepository(
        makeSnapTradeClient: { credentials in
            SnapTradeClient(credentials: credentials, session: session, currentDate: currentDate)
        },
        yahoo: YahooFinanceClient(session: session, currentDate: currentDate),
        brandfetch: BrandfetchClient(session: session),
        currentDate: currentDate
    )
}
