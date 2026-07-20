//
//  DemoPortfolio.swift
//  Bittern
//

import Foundation

enum DemoPortfolio {
    static var snapshot: PortfolioSnapshot {
        let brandfetch = BrandfetchClient()
        let now = Date()
        let preMarketSessionStart = now.addingTimeInterval(-30 * 60)
        let preMarketSessionEnd = now.addingTimeInterval(6 * 60 * 60)
        let postMarketSessionStart = now.addingTimeInterval(-30 * 60)
        let postMarketSessionEnd = now.addingTimeInterval(4 * 60 * 60)
        let account = PortfolioAccount(
            id: "demo-brokerage",
            connectionID: "demo-connection",
            name: "Personal Brokerage",
            institutionName: "SnapTrade Demo",
            providerLogoURL: nil,
            isConnectionDisabled: false,
            totalBalance: 94_426.74,
            currencyCode: "USD"
        )

        let holdings = [
            PortfolioHolding(
                id: "demo-aapl",
                accountID: account.id,
                symbol: "AAPL",
                name: "Apple Inc.",
                instrumentKind: .stock,
                logoURL: brandfetch.logoURL(for: "AAPL", kind: .stock),
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
                logoURL: brandfetch.logoURL(for: "MSFT", kind: .stock),
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
                logoURL: brandfetch.logoURL(for: "NVDA", kind: .stock),
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
                logoURL: brandfetch.logoURL(for: "VOO", kind: .etf),
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
                logoURL: brandfetch.logoURL(for: "TSLA", kind: .stock),
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
            )
        ]

        return PortfolioSnapshot.make(
            accounts: [account],
            holdings: holdings,
            lastUpdated: Date(),
            isDemo: true
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
        let priceChange = extendedHoursPrice - regularClose
        return HoldingExtendedHoursChange(
            amount: quantity * priceChange,
            percent: priceChange / abs(regularClose),
            observedAt: observedAt,
            sessionStart: sessionStart,
            sessionEnd: sessionEnd
        )
    }
}
