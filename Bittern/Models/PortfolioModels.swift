//
//  PortfolioModels.swift
//  Bittern
//

import Foundation

enum PerformanceMode: String, CaseIterable, Identifiable {
    case today
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            "Today"
        case .allTime:
            "All-time"
        }
    }
}

enum HoldingSortOption: String, CaseIterable, Identifiable {
    case gainAmount
    case lossAmount
    case percent
    case marketValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gainAmount:
            "Gain"
        case .lossAmount:
            "Loss"
        case .percent:
            "Percent"
        case .marketValue:
            "Value"
        }
    }

    var systemImage: String {
        switch self {
        case .gainAmount:
            "arrow.up.right"
        case .lossAmount:
            "arrow.down.right"
        case .percent:
            "percent"
        case .marketValue:
            "chart.pie"
        }
    }
}

struct SnapTradeCredentials: Codable, Equatable {
    var clientId: String
    var consumerKey: String
    var userId: String
    var userSecret: String

    var isComplete: Bool {
        hasAPIKey && hasSnapTradeUser
    }

    var hasAPIKey: Bool {
        !clientId.trimmed.isEmpty
            && !consumerKey.trimmed.isEmpty
    }

    var hasSnapTradeUser: Bool {
        !userId.trimmed.isEmpty
            && !userSecret.trimmed.isEmpty
    }

    static let empty = SnapTradeCredentials(
        clientId: "",
        consumerKey: "",
        userId: "",
        userSecret: ""
    )

    var sanitized: SnapTradeCredentials {
        SnapTradeCredentials(
            clientId: clientId.trimmed,
            consumerKey: consumerKey.trimmed,
            userId: userId.trimmed,
            userSecret: userSecret.trimmed
        )
    }
}

struct PortfolioAccount: Identifiable, Hashable {
    let id: String
    let connectionID: String?
    let name: String
    let institutionName: String
    let providerLogoURL: URL?
    let isConnectionDisabled: Bool
    let totalBalance: Double?
    let currencyCode: String

    var providerName: String {
        let institution = institutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !institution.isEmpty {
            return institution
        }

        let accountName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return accountName.isEmpty ? "Account" : accountName
    }
}

struct PortfolioHolding: Identifiable, Hashable {
    let id: String
    let accountID: String
    let symbol: String
    let name: String
    let accountName: String
    let quantity: Double
    let averageCost: Double
    let currentPrice: Double
    let previousClose: Double
    let currencyCode: String

    var marketValue: Double {
        quantity * currentPrice
    }

    var costBasis: Double {
        quantity * averageCost
    }

    var dayGainAmount: Double {
        quantity * (currentPrice - previousClose)
    }

    var dayGainPercent: Double {
        guard previousClose != 0 else { return 0 }
        return (currentPrice - previousClose) / abs(previousClose)
    }

    var allTimeGainAmount: Double {
        marketValue - costBasis
    }

    var allTimeGainPercent: Double {
        guard costBasis != 0 else { return 0 }
        return allTimeGainAmount / abs(costBasis)
    }

    func performanceAmount(for mode: PerformanceMode) -> Double {
        switch mode {
        case .today:
            dayGainAmount
        case .allTime:
            allTimeGainAmount
        }
    }

    func performancePercent(for mode: PerformanceMode) -> Double {
        switch mode {
        case .today:
            dayGainPercent
        case .allTime:
            allTimeGainPercent
        }
    }
}

struct PortfolioSnapshot {
    let accounts: [PortfolioAccount]
    let holdings: [PortfolioHolding]
    let totalAssets: Double
    let totalMarketValue: Double
    let dayGainAmount: Double
    let dayGainPercent: Double
    let allTimeGainAmount: Double
    let allTimeGainPercent: Double
    let currencyCode: String
    let hasMixedCurrencies: Bool
    let lastUpdated: Date
    let isDemo: Bool

    static func make(
        accounts: [PortfolioAccount],
        holdings: [PortfolioHolding],
        lastUpdated: Date = Date(),
        isDemo: Bool = false
    ) -> PortfolioSnapshot {
        let totalMarketValue = holdings.reduce(0) { $0 + $1.marketValue }
        let totalCostBasis = holdings.reduce(0) { $0 + $1.costBasis }
        let dayGainAmount = holdings.reduce(0) { $0 + $1.dayGainAmount }
        let previousMarketValue = totalMarketValue - dayGainAmount
        let allTimeGainAmount = totalMarketValue - totalCostBasis
        let accountBalance = accounts.compactMap(\.totalBalance).reduce(0, +)
        let currencyCodes = Set(holdings.map(\.currencyCode) + accounts.map(\.currencyCode))
        let currencyCode = holdings.first?.currencyCode ?? accounts.first?.currencyCode ?? "USD"

        return PortfolioSnapshot(
            accounts: accounts,
            holdings: holdings,
            totalAssets: accountBalance > 0 ? accountBalance : totalMarketValue,
            totalMarketValue: totalMarketValue,
            dayGainAmount: dayGainAmount,
            dayGainPercent: previousMarketValue == 0 ? 0 : dayGainAmount / abs(previousMarketValue),
            allTimeGainAmount: allTimeGainAmount,
            allTimeGainPercent: totalCostBasis == 0 ? 0 : allTimeGainAmount / abs(totalCostBasis),
            currencyCode: currencyCode,
            hasMixedCurrencies: currencyCodes.count > 1,
            lastUpdated: lastUpdated,
            isDemo: isDemo
        )
    }

    static let empty = PortfolioSnapshot.make(accounts: [], holdings: [], isDemo: true)
    static let emptyLive = PortfolioSnapshot.make(accounts: [], holdings: [], isDemo: false)
}

extension PortfolioSnapshot {
    func performanceAmount(for mode: PerformanceMode) -> Double {
        switch mode {
        case .today:
            dayGainAmount
        case .allTime:
            allTimeGainAmount
        }
    }

    func performancePercent(for mode: PerformanceMode) -> Double {
        switch mode {
        case .today:
            dayGainPercent
        case .allTime:
            allTimeGainPercent
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
