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

enum HoldingChartRange: String, CaseIterable, Identifiable, Codable {
    case oneDay = "1D"
    case fiveDays = "5D"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case fiveYears = "5Y"
    case max = "MAX"

    var id: String { rawValue }

    var title: String { rawValue }

    var yahooRange: String {
        switch self {
        case .oneDay:
            "1d"
        case .fiveDays:
            "5d"
        case .threeMonths:
            "3mo"
        case .oneYear:
            "1y"
        case .fiveYears:
            "5y"
        case .max:
            "max"
        }
    }

    var yahooInterval: String {
        switch self {
        case .oneDay:
            "5m"
        case .fiveDays:
            "15m"
        case .threeMonths, .oneYear:
            "1d"
        case .fiveYears:
            "1wk"
        case .max:
            "1mo"
        }
    }

    var summaryLabel: String {
        switch self {
        case .oneDay:
            "Today"
        case .fiveDays:
            "Last week"
        case .threeMonths:
            "3 months"
        case .oneYear:
            "1 year"
        case .fiveYears:
            "5 years"
        case .max:
            "Max"
        }
    }
}

struct HoldingPricePoint: Identifiable, Hashable {
    let date: Date
    let price: Double

    var id: TimeInterval {
        date.timeIntervalSince1970
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

struct PortfolioAccount: Identifiable, Hashable, Codable {
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

struct PortfolioHolding: Identifiable, Hashable, Codable {
    let id: String
    let accountID: String
    let symbol: String
    let name: String
    let accountName: String
    let quantity: Double
    let quantityDisplay: String?
    let averageCost: Double?
    let currentPrice: Double
    let previousClose: Double?
    let currencyCode: String
    let dividendsReceived: Double?

    var marketValue: Double {
        quantity * currentPrice
    }

    var costBasis: Double? {
        guard let averageCost, averageCost > 0 else { return nil }
        return quantity * averageCost
    }

    var dayGainAmount: Double? {
        guard let previousClose, previousClose > 0 else { return nil }
        return quantity * (currentPrice - previousClose)
    }

    var dayGainPercent: Double? {
        guard let previousClose, previousClose > 0 else { return nil }
        return (currentPrice - previousClose) / abs(previousClose)
    }

    var allTimeGainAmount: Double? {
        guard let costBasis else { return nil }
        return marketValue - costBasis
    }

    var allTimeGainPercent: Double? {
        guard let costBasis, costBasis != 0, let allTimeGainAmount else { return nil }
        return allTimeGainAmount / abs(costBasis)
    }

    var dividendReturnPercent: Double? {
        guard let dividendsReceived, let costBasis, costBasis != 0 else { return nil }
        return dividendsReceived / abs(costBasis)
    }

    var totalReturnAmount: Double? {
        guard let dividendsReceived, let allTimeGainAmount else { return nil }
        return allTimeGainAmount + dividendsReceived
    }

    var totalReturnPercent: Double? {
        guard let totalReturnAmount, let costBasis, costBasis != 0 else { return nil }
        return totalReturnAmount / abs(costBasis)
    }

    func performanceAmount(for mode: PerformanceMode) -> Double? {
        switch mode {
        case .today:
            dayGainAmount
        case .allTime:
            allTimeGainAmount
        }
    }

    func performancePercent(for mode: PerformanceMode) -> Double? {
        switch mode {
        case .today:
            dayGainPercent
        case .allTime:
            allTimeGainPercent
        }
    }
}

struct PortfolioSnapshot: Codable {
    let accounts: [PortfolioAccount]
    let holdings: [PortfolioHolding]
    let totalAssets: Double
    let totalMarketValue: Double
    let dayGainAmount: Double?
    let dayGainPercent: Double?
    let allTimeGainAmount: Double?
    let allTimeGainPercent: Double?
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
        var totalMarketValue: Double = 0
        var hasCompleteCostBasis = true
        var totalCostBasis: Double = 0
        var hasCompleteDayGain = true
        var totalDayGain: Double = 0
        var currencyCodes: Set<String> = []

        for h in holdings {
            totalMarketValue += h.marketValue
            if let cb = h.costBasis {
                totalCostBasis += cb
            } else {
                hasCompleteCostBasis = false
            }
            if let dg = h.dayGainAmount {
                totalDayGain += dg
            } else {
                hasCompleteDayGain = false
            }
            currencyCodes.insert(h.currencyCode)
        }
        for a in accounts {
            currencyCodes.insert(a.currencyCode)
        }

        let dayGainAmount = hasCompleteDayGain ? totalDayGain : nil
        let dayGainPercent = dayGainAmount.flatMap { amount in
            let previousMarketValue = totalMarketValue - amount
            return previousMarketValue == 0 ? 0 : amount / abs(previousMarketValue)
        }
        let allTimeGainAmount = hasCompleteCostBasis ? totalMarketValue - totalCostBasis : nil
        let allTimeGainPercent = allTimeGainAmount.flatMap { amount in
            totalCostBasis == 0 ? 0 : amount / abs(totalCostBasis)
        }
        let currencyCode = holdings.first?.currencyCode ?? accounts.first?.currencyCode ?? "USD"

        return PortfolioSnapshot(
            accounts: accounts,
            holdings: holdings,
            totalAssets: totalMarketValue,
            totalMarketValue: totalMarketValue,
            dayGainAmount: dayGainAmount,
            dayGainPercent: dayGainPercent,
            allTimeGainAmount: allTimeGainAmount,
            allTimeGainPercent: allTimeGainPercent,
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
    func performanceAmount(for mode: PerformanceMode) -> Double? {
        switch mode {
        case .today:
            dayGainAmount
        case .allTime:
            allTimeGainAmount
        }
    }

    func performancePercent(for mode: PerformanceMode) -> Double? {
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
