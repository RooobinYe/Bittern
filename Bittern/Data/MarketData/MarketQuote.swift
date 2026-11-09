//
//  MarketQuote.swift
//  Bittern
//
//  Quotes as the repository uses them, whatever market data provider
//  supplied them.
//

import Foundation

struct MarketQuoteRequest: Sendable {
    let symbol: String
    let instrumentKind: PortfolioInstrumentKind?
}

/// One holding's quote, keyed by the holding's own symbol (for example
/// "BTC"), not the provider's.
struct MarketQuote: Sendable {
    let symbol: String
    let currency: String?
    let regularMarketPrice: Double?
    let regularMarketPreviousClose: Double?
    let preMarket: ExtendedHoursQuote?
    let postMarket: ExtendedHoursQuote?
    /// When `regularMarketPrice` traded.
    var regularMarketTime: Date? = nil
    /// The trading day the quote belongs to.
    var marketSession: HoldingMarketSession? = nil
    /// The overnight quote, while the overnight session is under way.
    var overnight: ExtendedHoursQuote? = nil
}

enum ExtendedHoursSession: Equatable, Sendable {
    case preMarket
    case postMarket
    case overnight

    var logName: String {
        switch self {
        case .preMarket: "pre-market"
        case .postMarket: "post-market"
        case .overnight: "overnight"
        }
    }
}

/// The active pre-market, post-market or overnight quote. With no trade in the session yet,
/// `price` is the regular close and `observedAt` is nil.
struct ExtendedHoursQuote: Sendable {
    let extendedHoursSession: ExtendedHoursSession
    let price: Double
    let regularClose: Double
    let observedAt: Date?
    let sessionStart: Date
    let sessionEnd: Date
}

struct MarketQuoteBatch: Sendable {
    let quotes: [String: MarketQuote]
    let didFailExtendedHours: Bool

    static let empty = MarketQuoteBatch(
        quotes: [:],
        didFailExtendedHours: false
    )
}
