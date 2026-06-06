//
//  DemoPortfolio.swift
//  Bittern
//

import Foundation

enum DemoPortfolio {
    static var snapshot: PortfolioSnapshot {
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
                accountName: account.name,
                quantity: 84,
                averageCost: 158.24,
                currentPrice: 202.79,
                previousClose: 199.32,
                currencyCode: "USD"
            ),
            PortfolioHolding(
                id: "demo-msft",
                accountID: account.id,
                symbol: "MSFT",
                name: "Microsoft Corp.",
                accountName: account.name,
                quantity: 41,
                averageCost: 331.16,
                currentPrice: 472.13,
                previousClose: 468.44,
                currencyCode: "USD"
            ),
            PortfolioHolding(
                id: "demo-nvda",
                accountID: account.id,
                symbol: "NVDA",
                name: "NVIDIA Corp.",
                accountName: account.name,
                quantity: 120,
                averageCost: 92.40,
                currentPrice: 142.18,
                previousClose: 145.26,
                currencyCode: "USD"
            ),
            PortfolioHolding(
                id: "demo-voo",
                accountID: account.id,
                symbol: "VOO",
                name: "Vanguard S&P 500 ETF",
                accountName: account.name,
                quantity: 58,
                averageCost: 421.82,
                currentPrice: 537.61,
                previousClose: 534.80,
                currencyCode: "USD"
            ),
            PortfolioHolding(
                id: "demo-tsla",
                accountID: account.id,
                symbol: "TSLA",
                name: "Tesla Inc.",
                accountName: account.name,
                quantity: 32,
                averageCost: 244.20,
                currentPrice: 178.12,
                previousClose: 181.64,
                currencyCode: "USD"
            )
        ]

        return PortfolioSnapshot.make(
            accounts: [account],
            holdings: holdings,
            lastUpdated: Date(),
            isDemo: true
        )
    }
}
