//
//  DemoPortfolio.swift
//  Bittern
//

import Foundation

#if DEBUG
/// Sample data for SwiftUI previews only; never part of a release build.
enum DemoPortfolio {
    static var snapshot: PortfolioSnapshot {
        let now = Date()
        let preMarketSessionStart = now.addingTimeInterval(-30 * 60)
        let preMarketSessionEnd = now.addingTimeInterval(6 * 60 * 60)
        let postMarketSessionStart = now.addingTimeInterval(-30 * 60)
        let postMarketSessionEnd = now.addingTimeInterval(4 * 60 * 60)
        let account = PortfolioAccount(
            id: "demo-brokerage",
            name: "Personal Brokerage",
            institutionName: "SnapTrade Demo",
            providerLogoURL: nil,
            isConnectionDisabled: false,
            currencyCode: "USD"
        )

        let exchange = PortfolioAccount(
            id: "demo-exchange",
            name: "Crypto Wallet",
            institutionName: "Demo Exchange",
            providerLogoURL: nil,
            isConnectionDisabled: false,
            currencyCode: "USD"
        )

        let holdings = [
            PortfolioHolding(
                id: "demo-aapl",
                accountID: account.id,
                symbol: "AAPL",
                name: "Apple Inc.",
                instrumentKind: .stock,
                logoURL: nil,
                accountName: account.name,
                quantity: 84,
                quantityDisplay: "84",
                averageCost: 158.24,
                currentPrice: 202.79,
                previousClose: 199.32,
                preMarketChange: extendedHoursChange(
                    quantity: 84,
                    regularClose: 202.79,
                    extendedHoursPrice: 204.12,
                    observedAt: now,
                    sessionStart: preMarketSessionStart,
                    sessionEnd: preMarketSessionEnd
                ),
                postMarketChange: nil,
                currencyCode: "USD",
                dividendsReceived: 82.32
            ),
            PortfolioHolding(
                id: "demo-msft",
                accountID: account.id,
                symbol: "MSFT",
                name: "Microsoft Corp.",
                instrumentKind: .stock,
                logoURL: nil,
                accountName: account.name,
                quantity: 41,
                quantityDisplay: "41",
                averageCost: 331.16,
                currentPrice: 472.13,
                previousClose: 468.44,
                preMarketChange: nil,
                postMarketChange: extendedHoursChange(
                    quantity: 41,
                    regularClose: 472.13,
                    extendedHoursPrice: 469.80,
                    observedAt: now,
                    sessionStart: postMarketSessionStart,
                    sessionEnd: postMarketSessionEnd
                ),
                currencyCode: "USD",
                dividendsReceived: 54.70
            ),
            PortfolioHolding(
                id: "demo-nvda",
                accountID: account.id,
                symbol: "NVDA",
                name: "NVIDIA Corp.",
                instrumentKind: .stock,
                logoURL: nil,
                accountName: account.name,
                quantity: 120,
                quantityDisplay: "120",
                averageCost: 92.40,
                currentPrice: 142.18,
                previousClose: 145.26,
                preMarketChange: nil,
                postMarketChange: extendedHoursChange(
                    quantity: 120,
                    regularClose: 142.18,
                    extendedHoursPrice: 142.18,
                    observedAt: nil,
                    sessionStart: postMarketSessionStart,
                    sessionEnd: postMarketSessionEnd
                ),
                currencyCode: "USD",
                dividendsReceived: 12.96
            ),
            PortfolioHolding(
                id: "demo-voo",
                accountID: account.id,
                symbol: "VOO",
                name: "Vanguard S&P 500 ETF",
                instrumentKind: .etf,
                logoURL: nil,
                accountName: account.name,
                quantity: 58,
                quantityDisplay: "58",
                averageCost: 421.82,
                currentPrice: 537.61,
                previousClose: 534.80,
                preMarketChange: nil,
                postMarketChange: nil,
                currencyCode: "USD",
                dividendsReceived: 446.18
            ),
            PortfolioHolding(
                id: "demo-tsla",
                accountID: account.id,
                symbol: "TSLA",
                name: "Tesla Inc.",
                instrumentKind: .stock,
                logoURL: nil,
                accountName: account.name,
                quantity: 32,
                quantityDisplay: "32",
                averageCost: 244.20,
                currentPrice: 178.12,
                previousClose: 181.64,
                preMarketChange: nil,
                postMarketChange: nil,
                currencyCode: "USD",
                dividendsReceived: 0
            ),
            crypto(id: "demo-btc", symbol: "BTC", name: "Bitcoin", quantity: 0.07, price: 95_120, previousClose: 93_870, account: exchange),
            crypto(id: "demo-eth", symbol: "ETH", name: "Ethereum", quantity: 1.6, price: 3_512.40, previousClose: 3_560.10, account: exchange),
            crypto(id: "demo-sol", symbol: "SOL", name: "Solana", quantity: 26, price: 182.35, previousClose: 176.90, account: exchange),
            crypto(id: "demo-doge", symbol: "DOGE", name: "Dogecoin", quantity: 2, price: 0.21, previousClose: 0.2, account: exchange)
        ]

        return PortfolioSnapshot.make(
            accounts: [account, exchange],
            holdings: holdings,
            lastUpdated: Date()
        )
    }

    private static func crypto(
        id: String,
        symbol: String,
        name: String,
        quantity: Double,
        price: Double,
        previousClose: Double,
        account: PortfolioAccount
    ) -> PortfolioHolding {
        PortfolioHolding(
            id: id,
            accountID: account.id,
            symbol: symbol,
            name: name,
            instrumentKind: .crypto,
            logoURL: nil,
            accountName: account.name,
            quantity: quantity,
            quantityDisplay: nil,
            averageCost: price * 0.8,
            currentPrice: price,
            previousClose: previousClose,
            preMarketChange: nil,
            postMarketChange: nil,
            currencyCode: "USD",
            dividendsReceived: 0
        )
    }

    private static func extendedHoursChange(
        quantity: Double,
        regularClose: Double,
        extendedHoursPrice: Double,
        observedAt: Date?,
        sessionStart: Date,
        sessionEnd: Date
    ) -> HoldingExtendedHoursChange {
        let amount = quantity * (extendedHoursPrice - regularClose)
        return HoldingExtendedHoursChange(
            amount: amount,
            percent: amount / abs(quantity * regularClose),
            observedAt: observedAt,
            sessionStart: sessionStart,
            sessionEnd: sessionEnd
        )
    }
}
#endif
