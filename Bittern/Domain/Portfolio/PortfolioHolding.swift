//
//  PortfolioHolding.swift
//  Bittern
//

import Foundation

/// What kind of instrument a holding is. The raw values are persisted in the
/// portfolio cache, so they must not change.
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
}

enum HoldingQuantityUnit: String, Sendable {
    case shares
    case tokens

    var title: String {
        rawValue.capitalized
    }
}

struct HoldingExtendedHoursChange: Hashable, Codable, Sendable {
    let amount: Double
    let percent: Double
    let observedAt: Date?
    let sessionStart: Date
    let sessionEnd: Date
    /// The quote itself, which the 1D chart's continuation follows. Nil in
    /// data cached before it was kept.
    var price: Double? = nil

    func isActive(at date: Date) -> Bool {
        sessionStart <= date && date < sessionEnd
    }
}

/// The trading day an exchange published with a holding's quote: from the
/// start of pre-market to the end of post-market, with the regular session
/// inside. Assets without extended hours have all three on the regular
/// session's bounds.
struct HoldingMarketSession: Hashable, Codable, Sendable {
    let start: Date
    let regularStart: Date
    let regularEnd: Date
    let end: Date

    /// Pre-market, regular session or post-market is under way.
    func isActive(at date: Date) -> Bool {
        start <= date && date < end
    }

    func isRegular(at date: Date) -> Bool {
        regularStart <= date && date < regularEnd
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
    /// The exchange's trading day around the last quote. Nil until a quote
    /// brought one, as in data cached before it was kept.
    var marketSession: HoldingMarketSession? = nil
    /// When `currentPrice` traded, as the quote reports it.
    var regularPriceTime: Date? = nil

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

    /// Whether the price can move now: crypto always trades; anything else
    /// only from the start of pre-market to the end of post-market. Without
    /// a known trading day it is treated as closed until a quote says more.
    func isInActiveSession(at date: Date) -> Bool {
        instrumentKind == .crypto || marketSession?.isActive(at: date) == true
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

    /// The same position with freshly quoted price fields.
    func repriced(
        currentPrice: Double?,
        previousClose: Double?,
        preMarketChange: HoldingExtendedHoursChange?,
        postMarketChange: HoldingExtendedHoursChange?,
        marketSession: HoldingMarketSession?,
        regularPriceTime: Date?
    ) -> PortfolioHolding {
        PortfolioHolding(
            id: id,
            accountID: accountID,
            symbol: symbol,
            name: name,
            instrumentKind: instrumentKind,
            logoURL: logoURL,
            accountName: accountName,
            quantity: quantity,
            quantityDisplay: quantityDisplay,
            averageCost: averageCost,
            currentPrice: currentPrice,
            previousClose: previousClose,
            preMarketChange: preMarketChange,
            postMarketChange: postMarketChange,
            currencyCode: currencyCode,
            dividendsReceived: dividendsReceived,
            marketSession: marketSession,
            regularPriceTime: regularPriceTime
        )
    }

    /// The same position with the price fields of `priced`, a fresher copy
    /// of it.
    func repriced(from priced: PortfolioHolding) -> PortfolioHolding {
        repriced(
            currentPrice: priced.currentPrice,
            previousClose: priced.previousClose,
            preMarketChange: priced.preMarketChange,
            postMarketChange: priced.postMarketChange,
            marketSession: priced.marketSession,
            regularPriceTime: priced.regularPriceTime
        )
    }
}
