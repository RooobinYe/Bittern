//
//  TradingViewClient+PriceHistory.swift
//  Bittern
//
//  Price history for the holding detail chart. TradingView's bars are
//  checked and cut to each range here; the 1D layout itself is
//  `OneDaySeries`.
//

import Foundation
import OSLog

extension TradingViewClient {
    func priceHistory(
        for symbol: String,
        instrumentKind: PortfolioInstrumentKind?,
        currencyCode: String,
        range: HoldingChartRange
    ) async throws -> HoldingPriceSeries {
        guard let providerSymbol = tradingViewSymbol(for: symbol, instrumentKind: instrumentKind) else {
            throw TradingViewError.emptySymbols
        }
        AppLog.marketData.debug(
            "Price history requested symbol=\(symbol) tradingViewSymbol=\(providerSymbol) instrumentKind=\(logKind(instrumentKind), privacy: .public) range=\(range.title, privacy: .public)"
        )

        do {
            var series = try await history(
                providerSymbol: providerSymbol,
                isCrypto: instrumentKind == .crypto,
                currencyCode: currencyCode,
                range: range
            )
            series.firstTradeDate = await quoteFeed.fields(for: providerSymbol)?["first_bar_time_1d"]?
                .number
                .map { Date(timeIntervalSince1970: $0) }

            let minimumPointCount = range == .oneDay && instrumentKind == .crypto ? 1 : 2
            guard series.points.count >= minimumPointCount else {
                throw TradingViewError.notEnoughPoints(symbol: providerSymbol)
            }
            AppLog.marketData.debug(
                "Price history tradingViewSymbol=\(providerSymbol) range=\(range.title, privacy: .public) returned points=\(series.points.count, privacy: .public)"
            )
            return series
        } catch {
            AppLog.marketData.error(
                "Price history tradingViewSymbol=\(providerSymbol) range=\(range.title, privacy: .public) failed: \(AppLog.describe(error))"
            )
            throw error
        }
    }

    private func history(
        providerSymbol symbol: String,
        isCrypto: Bool,
        currencyCode: String,
        range: HoldingChartRange
    ) async throws -> HoldingPriceSeries {
        let requestedAt = currentDate()
        let mainRequest = TradingViewSeriesRequest(
            symbol: symbol,
            session: range == .oneDay && !isCrypto ? "extended" : "regular",
            resolution: range.tradingViewResolution,
            barCount: range.tradingViewBarCount(isCrypto: isCrypto)
        )
        // The regular closes around the 1D session: the intraday bar at the
        // close holds post-market trades, not the closing auction.
        let needsDailyCloses = range == .oneDay && !isCrypto
        async let mainSeries = connection.series(mainRequest, timeout: Self.chartTimeout)
        async let dailySeries: TradingViewSeries? = needsDailyCloses
            ? connection.series(
                TradingViewSeriesRequest(symbol: symbol, session: "regular", resolution: "1D", barCount: 10),
                timeout: Self.chartTimeout
            )
            : nil
        let main = try await mainSeries
        let daily = try await dailySeries

        let currency = main.symbolInfo["currency_code"]?.string
        guard currency == currencyCode else {
            throw TradingViewError.currencyMismatch(symbol: symbol, expected: currencyCode, actual: currency)
        }
        let calendar = try TradingViewSessionCalendar(
            timeZone: main.symbolInfo["timezone"]?.string,
            subsessions: main.symbolInfo["subsessions"],
            holidays: main.symbolInfo["session_holidays"]?.string
        )
        let points = try Self.points(from: main.bars, symbol: symbol)

        switch range {
        case .oneDay:
            do {
                if isCrypto {
                    return try OneDaySeries.fullDay(observations: points, at: requestedAt)
                }
                return try oneDaySeries(
                    points: points,
                    dailyBars: daily?.bars ?? [],
                    calendar: calendar,
                    at: requestedAt
                )
            } catch let error as OneDaySeriesError {
                throw TradingViewError.invalidChartData(error.reason(for: symbol))
            }
        case .yearToDate:
            let yearStart = calendar.startOfYear(containing: requestedAt)
            guard let baseline = points.last(where: { $0.date < yearStart })?.price else {
                throw TradingViewError.invalidChartData("Missing close before the year for \(symbol).")
            }
            return HoldingPriceSeries(
                points: points.filter { $0.date >= yearStart },
                timeDomain: nil,
                baselinePrice: baseline
            )
        case .fiveDays:
            let days = Set(points.map { calendar.dateNumber(of: $0.date) }).sorted().suffix(5)
            guard let firstDay = days.first else {
                return HoldingPriceSeries(points: [], timeDomain: nil)
            }
            return HoldingPriceSeries(
                points: points.filter { calendar.dateNumber(of: $0.date) >= firstDay },
                timeDomain: nil
            )
        case .oneMonth, .threeMonths, .oneYear, .fiveYears:
            let start = calendar.date(byAdding: range.lookBack, to: requestedAt)
            return HoldingPriceSeries(points: points.filter { $0.date >= start }, timeDomain: nil)
        case .max:
            return HoldingPriceSeries(points: points, timeDomain: nil)
        }
    }

    /// Lays out the 1D Display Cycle from extended-hours bars, the
    /// exchange's schedule around them and the daily regular closes.
    private func oneDaySeries(
        points: [HoldingPricePoint],
        dailyBars: [TradingViewBar],
        calendar: TradingViewSessionCalendar,
        at now: Date
    ) throws -> HoldingPriceSeries {
        let start = points.first?.date ?? now
        let schedule = calendar.schedule(
            from: calendar.date(byAdding: DateComponents(day: -1), to: start),
            through: calendar.date(byAdding: DateComponents(day: 1), to: now)
        )

        // The 1D chart shows the latest regular session that has started.
        // Its close and the close before it come from the daily bars, which
        // TradingView stamps with the session's local date.
        var regularClose: Double?
        var previousClose: Double?
        if let shown = schedule.regular.last(where: { $0.start <= now }) {
            let shownDay = calendar.dateNumber(of: shown.start)
            regularClose = dailyBars.last { calendar.dateNumber(of: $0.time) == shownDay }?.close
            previousClose = dailyBars.last { calendar.dateNumber(of: $0.time) < shownDay }?.close
        }

        return try OneDaySeries.displayCycle(
            observations: points,
            schedule: schedule,
            granularity: 5 * 60,
            previousClose: previousClose,
            regularClose: regularClose,
            at: now
        )
    }

    /// The bars' closes, in order. Bars out of order or without a usable
    /// close mean the series can't be trusted, so they fail it.
    private static func points(from bars: [TradingViewBar], symbol: String) throws -> [HoldingPricePoint] {
        guard zip(bars, bars.dropFirst()).allSatisfy({ $0.time < $1.time }) else {
            throw TradingViewError.invalidChartData("Unordered bars for \(symbol).")
        }
        return try bars.map { bar in
            guard bar.close.isFinite, bar.close > 0 else {
                throw TradingViewError.invalidChartData("Invalid close for \(symbol).")
            }
            return HoldingPricePoint(date: bar.time, price: bar.close)
        }
    }
}

private extension HoldingChartRange {
    /// The bar each range is drawn from, matching `barLength`.
    var tradingViewResolution: String {
        switch self {
        case .oneDay: "5"
        case .fiveDays: "15"
        case .oneMonth: "60"
        case .threeMonths, .yearToDate, .oneYear: "1D"
        case .fiveYears: "1W"
        case .max: "1M"
        }
    }

    /// Enough bars to cover the range, which is then cut to its start.
    /// 1D covers the last two or three trading days of 5-minute bars from
    /// 4:00 to 20:00, or a whole day around the clock.
    func tradingViewBarCount(isCrypto: Bool) -> Int {
        switch self {
        case .oneDay: isCrypto ? 300 : 600
        case .fiveDays: 500
        case .oneMonth: 800
        case .threeMonths: 120
        case .yearToDate, .oneYear: 400
        case .fiveYears: 300
        case .max: 5_000
        }
    }

    var lookBack: DateComponents {
        switch self {
        case .oneMonth: DateComponents(month: -1)
        case .threeMonths: DateComponents(month: -3)
        case .oneYear: DateComponents(year: -1)
        case .fiveYears: DateComponents(year: -5)
        case .oneDay, .fiveDays, .yearToDate, .max: DateComponents()
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
