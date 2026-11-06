//
//  YahooFinanceClient+PriceHistory.swift
//  Bittern
//
//  Price history for the holding detail chart. Yahoo's response is checked
//  and translated here; the 1D layout itself is `OneDaySeries`.
//

import Foundation
import OSLog

extension YahooFinanceClient {
    func priceHistory(
        for symbol: String,
        instrumentKind: PortfolioInstrumentKind?,
        currencyCode: String,
        range: HoldingChartRange
    ) async throws -> HoldingPriceSeries {
        guard let yahooSymbol = yahooSymbol(for: symbol, instrumentKind: instrumentKind) else {
            throw YahooFinanceError.emptySymbols
        }

        AppLog.marketData.debug(
            "Price history requested symbol=\(symbol) yahooSymbol=\(yahooSymbol) instrumentKind=\(logKind(instrumentKind), privacy: .public) range=\(range.title, privacy: .public)"
        )

        do {
            let history = try await fetchHistory(
                yahooSymbol: yahooSymbol,
                instrumentKind: instrumentKind,
                currencyCode: currencyCode,
                range: range
            )
            AppLog.marketData.debug(
                "Price history yahooSymbol=\(yahooSymbol) returned points=\(history.points.count, privacy: .public)"
            )
            return history
        } catch {
            AppLog.marketData.error(
                "Price history yahooSymbol=\(yahooSymbol) failed: \(AppLog.describe(error))"
            )
            throw error
        }
    }

    private func fetchHistory(
        yahooSymbol symbol: String,
        instrumentKind: PortfolioInstrumentKind?,
        currencyCode: String,
        range: HoldingChartRange
    ) async throws -> HoldingPriceSeries {
        let requestedAt = currentDate()
        // Yahoo's 1d response contains only the current pre-market before the
        // open. Five trading days provide enough context to reconstruct one
        // display cycle without exposing older observations to the chart.
        let requestRange = range == .oneDay ? "5d" : range.yahooRange
        let result = try await chart(
            for: symbol,
            query: [
                URLQueryItem(name: "interval", value: range.yahooInterval),
                URLQueryItem(name: "range", value: requestRange),
                URLQueryItem(name: "includePrePost", value: range == .oneDay ? "true" : "false"),
                URLQueryItem(name: "events", value: "history")
            ],
            timeout: 8,
            operation: "price-history candidate=\(symbol) range=\(range.title)"
        )

        guard let timestamps = result.timestamp,
              let closes = result.indicators?.quote?.first?.close
        else {
            throw YahooFinanceError.emptyResult(symbol: symbol)
        }
        guard result.meta?.currency == currencyCode else {
            throw YahooFinanceError.currencyMismatch(
                symbol: symbol,
                expected: currencyCode,
                actual: result.meta?.currency
            )
        }
        guard timestamps.count == closes.count else {
            throw YahooFinanceError.invalidChartMetadata(
                "Timestamp and close counts differ for \(symbol)."
            )
        }
        guard zip(timestamps, timestamps.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw YahooFinanceError.invalidChartMetadata(
                "Unordered timestamps for \(symbol)."
            )
        }

        let points = zip(timestamps, closes).compactMap { timestamp, close -> HoldingPricePoint? in
            guard let close, close.isFinite, close > 0 else { return nil }
            return HoldingPricePoint(
                date: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                price: close
            )
        }

        let series = range == .oneDay
            ? try oneDaySeries(
                meta: result.meta,
                points: points,
                requestRange: requestRange,
                requestedAt: requestedAt,
                instrumentKind: instrumentKind,
                symbol: symbol
            )
            : HoldingPriceSeries(points: points, timeDomain: nil)

        let minimumPointCount = range == .oneDay && instrumentKind == .crypto ? 1 : 2
        guard series.points.count >= minimumPointCount else {
            throw YahooFinanceError.notEnoughPoints(symbol: symbol)
        }
        return series
    }

    /// Checks that Yahoo answered the 1D question that was asked, then hands
    /// its schedule to `OneDaySeries`.
    private func oneDaySeries(
        meta: YahooChartMetaDTO?,
        points: [HoldingPricePoint],
        requestRange: String,
        requestedAt: Date,
        instrumentKind: PortfolioInstrumentKind?,
        symbol: String
    ) throws -> HoldingPriceSeries {
        guard let meta else {
            throw YahooFinanceError.invalidChartMetadata("Missing metadata for \(symbol).")
        }
        guard meta.range == requestRange else {
            throw YahooFinanceError.invalidChartMetadata("Unexpected range for \(symbol).")
        }
        guard meta.dataGranularity == HoldingChartRange.oneDay.yahooInterval,
              let granularity = duration(forYahooInterval: meta.dataGranularity)
        else {
            throw YahooFinanceError.invalidChartMetadata("Unexpected granularity for \(symbol).")
        }

        do {
            if instrumentKind == .crypto {
                return try OneDaySeries.fullDay(observations: points, at: requestedAt)
            }

            return try OneDaySeries.displayCycle(
                observations: points,
                schedule: try schedule(from: meta, symbol: symbol),
                granularity: granularity,
                previousClose: meta.previousClose,
                regularClose: meta.regularMarketPrice,
                at: requestedAt
            )
        } catch let error as OneDaySeriesError {
            throw YahooFinanceError.invalidChartMetadata(error.reason(for: symbol))
        }
    }

    private func schedule(
        from meta: YahooChartMetaDTO,
        symbol: String
    ) throws -> ExchangeTradingSchedule {
        guard let timeZoneName = meta.exchangeTimezoneName,
              let timeZone = TimeZone(identifier: timeZoneName)
        else {
            throw YahooFinanceError.invalidChartMetadata("Missing exchange timezone for \(symbol).")
        }
        guard let tradingPeriods = meta.tradingPeriods else {
            throw YahooFinanceError.invalidChartMetadata("Missing trading periods for \(symbol).")
        }

        switch tradingPeriods {
        case .regular(let groups):
            return ExchangeTradingSchedule(
                regular: try periods(groups, name: "regular", symbol: symbol),
                preMarket: [],
                postMarket: [],
                timeZone: timeZone
            )
        case .extended(let periods):
            return ExchangeTradingSchedule(
                regular: try self.periods(periods.regular ?? [], name: "regular", symbol: symbol),
                preMarket: try self.periods(periods.pre ?? [], name: "pre-market", symbol: symbol),
                postMarket: try self.periods(periods.post ?? [], name: "post-market", symbol: symbol),
                timeZone: timeZone
            )
        }
    }

    private func periods(
        _ groups: [[YahooTradingPeriodDTO]],
        name: String,
        symbol: String
    ) throws -> [PriceChartTimeSegment] {
        try groups.flatMap { $0 }
            .map { rawPeriod in
                guard let start = rawPeriod.start,
                      let end = rawPeriod.end,
                      start < end
                else {
                    throw YahooFinanceError.invalidChartMetadata(
                        "Malformed \(name) trading period for \(symbol)."
                    )
                }

                return PriceChartTimeSegment(
                    start: Date(timeIntervalSince1970: TimeInterval(start)),
                    end: Date(timeIntervalSince1970: TimeInterval(end))
                )
            }
            .sorted { $0.start < $1.start }
    }

    private func duration(forYahooInterval interval: String?) -> TimeInterval? {
        guard let interval,
              let unit = interval.last,
              let amount = Double(interval.dropLast()),
              amount > 0
        else {
            return nil
        }

        switch unit {
        case "m":
            return amount * 60
        case "h":
            return amount * 60 * 60
        case "d":
            return amount * 24 * 60 * 60
        default:
            return nil
        }
    }
}

/// Yahoo's names for each chart range.
private extension HoldingChartRange {
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
}

private extension OneDaySeriesError {
    func reason(for symbol: String) -> String {
        switch self {
        case .noRegularPeriods:
            "Empty trading periods for \(symbol)."
        case .noRelevantRegularPeriod:
            "No relevant regular trading period for \(symbol)."
        case .noRegularObservations:
            "No regular-session observations for \(symbol)."
        case .missingRegularClose:
            "Missing regular close for \(symbol)."
        case .noCurrentDayObservations:
            "No current UTC-day observations for \(symbol)."
        }
    }
}
