//
//  YahooChartDTOs.swift
//  Bittern
//
//  Shapes of Yahoo Finance's v8 chart API, and the quotes built from them.
//

import Foundation

// MARK: - v8 Chart API DTOs

struct YahooChartResponseDTO: Decodable {
    let chart: YahooChartDTO
}

struct YahooChartDTO: Decodable {
    let result: [YahooChartResultDTO]?
    let error: YahooChartErrorDTO?
}

struct YahooChartErrorDTO: Decodable {
    let code: String?
    let description: String?
}

struct YahooChartResultDTO: Decodable {
    let meta: YahooChartMetaDTO?
    let timestamp: [Int]?
    let indicators: YahooChartIndicatorsDTO?
}

struct YahooChartMetaDTO: Decodable {
    let currency: String?
    let symbol: String?
    let regularMarketPrice: Double?
    /// Unix seconds of the trade `regularMarketPrice` comes from.
    let regularMarketTime: Int?
    let chartPreviousClose: Double?
    let previousClose: Double?
    let exchangeTimezoneName: String?
    let dataGranularity: String?
    let range: String?
    let tradingPeriods: YahooTradingPeriodsDTO?
    let hasPrePostMarketData: Bool?
    let currentTradingPeriod: YahooCurrentTradingPeriodsDTO?
    /// Unix seconds of the first trade Yahoo has for the symbol.
    let firstTradeDate: Int?
}

struct YahooTradingPeriodDTO: Decodable {
    let start: Int?
    let end: Int?
}

enum YahooTradingPeriodsDTO: Decodable {
    case regular([[YahooTradingPeriodDTO]])
    case extended(YahooExtendedTradingPeriodsDTO)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let regular = try? container.decode(
            [[YahooTradingPeriodDTO]].self
        ) {
            self = .regular(regular)
            return
        }

        self = .extended(
            try container.decode(YahooExtendedTradingPeriodsDTO.self)
        )
    }
}

struct YahooExtendedTradingPeriodsDTO: Decodable {
    let pre: [[YahooTradingPeriodDTO]]?
    let regular: [[YahooTradingPeriodDTO]]?
    let post: [[YahooTradingPeriodDTO]]?
}

struct YahooCurrentTradingPeriodsDTO: Decodable {
    let pre: YahooCurrentTradingPeriodDTO?
    let regular: YahooCurrentTradingPeriodDTO?
    let post: YahooCurrentTradingPeriodDTO?
}

struct YahooCurrentTradingPeriodDTO: Decodable {
    let start: Int?
    let end: Int?
}

struct YahooChartIndicatorsDTO: Decodable {
    let quote: [YahooChartQuoteDTO]?
}

struct YahooChartQuoteDTO: Decodable {
    let close: [Double?]?
}

// MARK: - Quote results

struct YahooQuoteDTO: Sendable {
    let symbol: String
    let currency: String?
    let regularMarketPrice: Double?
    let regularMarketPreviousClose: Double?
    let preMarket: YahooExtendedHoursQuoteDTO?
    let postMarket: YahooExtendedHoursQuoteDTO?
    /// When `regularMarketPrice` traded.
    var regularMarketTime: Date? = nil
    /// The trading day the quote belongs to.
    var marketSession: HoldingMarketSession? = nil
}

struct YahooExtendedHoursQuoteDTO: Sendable {
    let extendedHoursSession: YahooExtendedHoursSession
    let price: Double
    let regularClose: Double
    let observedAt: Date?
    let sessionStart: Date
    let sessionEnd: Date
}
