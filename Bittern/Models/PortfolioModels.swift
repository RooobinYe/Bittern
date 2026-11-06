//
//  PortfolioModels.swift
//  Bittern
//

import Foundation

enum PerformanceMode: String, CaseIterable, Identifiable, Sendable {
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

enum HoldingSortOption: String, CaseIterable, Identifiable, Sendable {
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

enum PortfolioInstrumentKind: String, Codable, Sendable {
    case stock
    case etf
    case crypto
    case mutualFund = "mutualfund"
    case adr
    case closedEndFund = "cef"
    case future
    case option
    case cfd
    case other

    init?(snapTradeValue: String?) {
        guard let value = snapTradeValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !value.isEmpty
        else {
            return nil
        }

        switch value {
        case "stock": self = .stock
        case "etf": self = .etf
        case "crypto": self = .crypto
        case "mutualfund": self = .mutualFund
        case "adr": self = .adr
        case "cef": self = .closedEndFund
        case "future": self = .future
        case "option": self = .option
        case "cfd": self = .cfd
        default: self = .other
        }
    }
}

enum HoldingQuantityUnit: String, Sendable {
    case shares
    case tokens

    var title: String {
        rawValue.capitalized
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

    func detailChangeBasePrice(previousClose: Double?, seriesFirstPrice: Double?) -> Double? {
        switch self {
        case .oneDay:
            return previousClose
        case .fiveDays, .threeMonths, .oneYear, .fiveYears, .max:
            return seriesFirstPrice
        }
    }
}

enum PriceChartSession: Hashable {
    case regular
    case preMarket
    case postMarket

    var isExtendedHours: Bool {
        self != .regular
    }
}

struct HoldingPricePoint: Identifiable, Hashable {
    let date: Date
    let price: Double
    let session: PriceChartSession

    init(
        date: Date,
        price: Double,
        session: PriceChartSession = .regular
    ) {
        self.date = date
        self.price = price
        self.session = session
    }

    var id: TimeInterval {
        date.timeIntervalSince1970
    }
}

struct PriceChartTimeSegment: Hashable {
    let start: Date
    let end: Date
    let spacingBefore: TimeInterval

    init(
        start: Date,
        end: Date,
        spacingBefore: TimeInterval = 0
    ) {
        self.start = start
        self.end = end
        self.spacingBefore = spacingBefore
    }
}

struct PriceChartTimeDomain: Hashable {
    let segments: [PriceChartTimeSegment]

    init(start: Date, end: Date) {
        segments = [PriceChartTimeSegment(start: start, end: end)]
    }

    init(segments: [PriceChartTimeSegment]) {
        self.segments = segments
    }

    var start: Date {
        segments.first?.start ?? .distantFuture
    }

    var end: Date {
        segments.last?.end ?? .distantPast
    }

    var duration: TimeInterval {
        segments.reduce(0) { total, segment in
            total
                + max(0, segment.spacingBefore)
                + max(0, segment.end.timeIntervalSince(segment.start))
        }
    }

    func elapsedTime(for date: Date) -> TimeInterval? {
        var elapsed: TimeInterval = 0

        for segment in segments {
            elapsed += max(0, segment.spacingBefore)
            if segment.start <= date, date <= segment.end {
                return elapsed + date.timeIntervalSince(segment.start)
            }
            elapsed += max(0, segment.end.timeIntervalSince(segment.start))
        }

        return nil
    }
}

struct HoldingPriceSeries {
    let points: [HoldingPricePoint]
    let timeDomain: PriceChartTimeDomain?
    let baselinePrice: Double?

    init(
        points: [HoldingPricePoint],
        timeDomain: PriceChartTimeDomain?,
        baselinePrice: Double? = nil
    ) {
        self.points = points
        self.timeDomain = timeDomain
        self.baselinePrice = baselinePrice
    }

    static let empty = HoldingPriceSeries(
        points: [],
        timeDomain: nil,
        baselinePrice: nil
    )
}

enum PortfolioHistoryRange: String, CaseIterable, Identifiable {
    case fiveDays = "5D"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case yearToDate = "YTD"

    var id: String { rawValue }

    var title: String { rawValue }
}

struct PortfolioHistoryPoint: Identifiable, Hashable {
    let date: Date
    let totalValue: Double

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

struct PortfolioAccount: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let institutionName: String
    let providerLogoURL: URL?
    let isConnectionDisabled: Bool
    /// The balance's currency, which SnapTrade may omit. Holdings carry their
    /// own currency, so this never decides how a holding is valued.
    let currencyCode: String?

    var providerName: String {
        let institution = institutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !institution.isEmpty {
            return institution
        }

        let accountName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return accountName.isEmpty ? "Account" : accountName
    }
}

struct HoldingExtendedHoursChange: Hashable, Codable, Sendable {
    let amount: Double
    let percent: Double
    let observedAt: Date?
    let sessionStart: Date
    let sessionEnd: Date

    func isActive(at date: Date) -> Bool {
        sessionStart <= date && date < sessionEnd
    }
}

struct PortfolioHolding: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let accountID: String
    let symbol: String
    let name: String
    let instrumentKind: PortfolioInstrumentKind?
    let logoURL: URL?
    let accountName: String
    let quantity: Double
    let quantityDisplay: String?
    let averageCost: Double?
    let currentPrice: Double?
    let previousClose: Double?
    let preMarketChange: HoldingExtendedHoursChange?
    let postMarketChange: HoldingExtendedHoursChange?
    let currencyCode: String
    let dividendsReceived: Double?

    var quantityUnit: HoldingQuantityUnit {
        instrumentKind == .crypto ? .tokens : .shares
    }

    func activePreMarketChange(at date: Date) -> HoldingExtendedHoursChange? {
        guard let preMarketChange,
              preMarketChange.isActive(at: date)
        else {
            return nil
        }
        return preMarketChange
    }

    func activePostMarketChange(at date: Date) -> HoldingExtendedHoursChange? {
        guard let postMarketChange,
              postMarketChange.isActive(at: date)
        else {
            return nil
        }
        return postMarketChange
    }

    var marketValue: Double? {
        guard let currentPrice else { return nil }
        return quantity * currentPrice
    }

    /// A zero cost means the broker doesn't know it (for example after a
    /// transfer), not that the position was free.
    var costBasis: Double? {
        guard let averageCost, averageCost > 0 else { return nil }
        return quantity * averageCost
    }

    var dayGainAmount: Double? {
        guard let currentPrice, let previousClose, previousClose > 0 else { return nil }
        return quantity * (currentPrice - previousClose)
    }

    var dayGainPercent: Double? {
        guard let dayGainAmount, let previousClose, previousClose > 0, quantity != 0 else { return nil }
        return dayGainAmount / abs(quantity * previousClose)
    }

    var allTimeGainAmount: Double? {
        guard let marketValue, let costBasis else { return nil }
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
            totalReturnAmount
        }
    }

    func performancePercent(for mode: PerformanceMode) -> Double? {
        switch mode {
        case .today:
            dayGainPercent
        case .allTime:
            totalReturnPercent
        }
    }
}

struct PortfolioSnapshot: nonisolated Codable, Sendable {
    let accounts: [PortfolioAccount]
    let holdings: [PortfolioHolding]
    let totalMarketValue: Double?
    let dayGainAmount: Double?
    let dayGainPercent: Double?
    let allTimeGainAmount: Double?
    let allTimeGainPercent: Double?
    /// The currency of the totals. Meaningless while `hasMixedCurrencies`, when
    /// every total is nil, and a placeholder when there are no holdings.
    let currencyCode: String
    let hasMixedCurrencies: Bool
    /// When every holding last had a price; nil if that has never been true.
    let lastUpdated: Date?

    /// Totals are nil unless every holding contributes to them in one shared
    /// currency: Bittern never converts, so there is no honest sum otherwise
    /// (docs/adr/0002-single-currency-portfolio.md).
    static func make(
        accounts: [PortfolioAccount],
        holdings: [PortfolioHolding],
        lastUpdated: Date? = Date()
    ) -> PortfolioSnapshot {
        let currencyCodes = Set(holdings.map(\.currencyCode))
        let hasMixedCurrencies = currencyCodes.count > 1

        func total(_ value: (PortfolioHolding) -> Double?) -> Double? {
            guard !holdings.isEmpty, !hasMixedCurrencies else { return nil }
            var sum = 0.0
            for holding in holdings {
                guard let amount = value(holding) else { return nil }
                sum += amount
            }
            return sum
        }

        func ratio(_ amount: Double?, of base: Double?) -> Double? {
            guard let amount, let base, base != 0 else { return nil }
            return amount / abs(base)
        }

        let totalMarketValue = total(\.marketValue)
        let dayGainAmount = totalMarketValue == nil ? nil : total(\.dayGainAmount)
        let previousMarketValue = totalMarketValue.flatMap { value in
            dayGainAmount.map { value - $0 }
        }
        let totalCostBasis = total(\.costBasis)
        let allTimeGainAmount = totalCostBasis == nil ? nil : total(\.totalReturnAmount)

        return PortfolioSnapshot(
            accounts: accounts,
            holdings: holdings,
            totalMarketValue: totalMarketValue,
            dayGainAmount: dayGainAmount,
            dayGainPercent: ratio(dayGainAmount, of: previousMarketValue),
            allTimeGainAmount: allTimeGainAmount,
            allTimeGainPercent: ratio(allTimeGainAmount, of: totalCostBasis),
            currencyCode: holdings.first?.currencyCode ?? "USD",
            hasMixedCurrencies: hasMixedCurrencies,
            lastUpdated: lastUpdated
        )
    }

    /// Symbols of holdings that have no usable price.
    var unpricedSymbols: [String] {
        Array(Set(holdings.filter { $0.currentPrice == nil }.map(\.symbol))).sorted()
    }

    /// The same inputs with totals recomputed by today's rules. Used on data
    /// persisted by an earlier version.
    func recomputed() -> PortfolioSnapshot {
        .make(accounts: accounts, holdings: holdings, lastUpdated: lastUpdated)
    }

    /// A partial refresh has no `lastUpdated` of its own, so it keeps showing
    /// when the prices were last complete.
    func inheritingLastUpdated(from previous: PortfolioSnapshot?) -> PortfolioSnapshot {
        guard lastUpdated == nil, let previous else { return self }
        return .make(
            accounts: accounts,
            holdings: holdings,
            lastUpdated: previous.lastUpdated
        )
    }
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
