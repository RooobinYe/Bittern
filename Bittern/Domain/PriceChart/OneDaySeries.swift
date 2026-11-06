//
//  OneDaySeries.swift
//  Bittern
//
//  Lays out the 1D chart from observations and an exchange schedule. Pure:
//  every input, including the current time, is passed in. Terms follow
//  CONTEXT.md (Full-Day 1D Window, Bounded 1D Session, 1D Display Cycle,
//  Extended-Hours Continuation).
//

import Foundation

/// The trading periods an exchange published around the requested time,
/// each list sorted by start.
struct ExchangeTradingSchedule {
    let regular: [PriceChartTimeSegment]
    let preMarket: [PriceChartTimeSegment]
    let postMarket: [PriceChartTimeSegment]
    let timeZone: TimeZone
}

enum OneDaySeriesError: Error, Equatable {
    case noRegularPeriods
    case noRelevantRegularPeriod
    case noRegularObservations
    case missingRegularClose
    case noCurrentDayObservations
}

enum OneDaySeries {
    /// A Full-Day 1D Window over the current UTC day, for assets that trade
    /// around the clock. The chart spans the whole day; observations keep
    /// their true positions in it.
    ///
    /// The baseline is left to the holding quote, so the detail view shows the
    /// same previous close as the holding row.
    static func fullDay(
        observations: [HoldingPricePoint],
        at now: Date
    ) throws -> HoldingPriceSeries {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw OneDaySeriesError.noCurrentDayObservations
        }

        let points = observations
            .filter { start <= $0.date && $0.date <= now && $0.date < end }
            .map { $0.inSession(.regular) }
        guard !points.isEmpty else {
            throw OneDaySeriesError.noCurrentDayObservations
        }

        return HoldingPriceSeries(
            points: points,
            timeDomain: PriceChartTimeDomain(start: start, end: end),
            baselinePrice: nil
        )
    }

    /// The 1D Display Cycle for `now`: the regular session in progress, or the
    /// latest one with its post-market and, before the next open, the next
    /// pre-market attached as an Extended-Hours Continuation.
    ///
    /// - Parameters:
    ///   - granularity: The spacing between observations. It also separates
    ///     post-market from the next pre-market on the time axis.
    ///   - previousClose: The close before the shown regular session.
    ///   - regularClose: The shown session's regular close, which ends a
    ///     completed session in place of the bar stamped at its close.
    static func displayCycle(
        observations: [HoldingPricePoint],
        schedule: ExchangeTradingSchedule,
        granularity: TimeInterval,
        previousClose: Double?,
        regularClose: Double?,
        at now: Date
    ) throws -> HoldingPriceSeries {
        let layout = Layout(
            observations: observations,
            granularity: granularity,
            previousClose: previousClose,
            regularClose: regularClose,
            now: now
        )
        let regularPeriods = schedule.regular
        guard !regularPeriods.isEmpty else {
            throw OneDaySeriesError.noRegularPeriods
        }

        if let regular = regularPeriods.first(where: { $0.contains(now) }) {
            return try layout.regularSession(regular, timeZone: schedule.timeZone)
        }

        if let postMarket = schedule.postMarket.first(where: { $0.contains(now) }),
           let regular = precedingRegularPeriod(for: postMarket, in: regularPeriods) {
            return try layout.extendedSession(regular, postMarket: postMarket, preMarket: nil)
        }

        if let preMarket = schedule.preMarket.first(where: { $0.contains(now) }),
           let regular = precedingRegularPeriod(for: preMarket, in: regularPeriods) {
            let postMarket = followingPostMarketPeriod(
                for: regular,
                before: preMarket.start,
                in: schedule.postMarket
            )
            return try layout.extendedSession(regular, postMarket: postMarket, preMarket: preMarket)
        }

        guard let regular = regularPeriods.last(where: { $0.end <= now })
            ?? regularPeriods.last(where: { period in
                observations.contains { period.contains($0.date) }
            })
        else {
            throw OneDaySeriesError.noRelevantRegularPeriod
        }

        if let postMarket = followingPostMarketPeriod(
            for: regular,
            before: now,
            in: schedule.postMarket
        ) {
            return try layout.extendedSession(regular, postMarket: postMarket, preMarket: nil)
        }

        return try layout.regularSession(regular, timeZone: schedule.timeZone)
    }

    private static func precedingRegularPeriod(
        for period: PriceChartTimeSegment,
        in regularPeriods: [PriceChartTimeSegment]
    ) -> PriceChartTimeSegment? {
        regularPeriods.last { $0.end <= period.start }
    }

    private static func followingPostMarketPeriod(
        for regular: PriceChartTimeSegment,
        before upperBound: Date,
        in postMarketPeriods: [PriceChartTimeSegment]
    ) -> PriceChartTimeSegment? {
        postMarketPeriods.first {
            regular.end <= $0.start && $0.start < upperBound
        }
    }
}

private struct Layout {
    let observations: [HoldingPricePoint]
    let granularity: TimeInterval
    let previousClose: Double?
    let regularClose: Double?
    let now: Date

    /// A Bounded 1D Session keeps its true bounds, so a session in progress
    /// stops mid-chart. A session that covers the whole calendar day is
    /// treated as a Full-Day 1D Window and spans only its observations.
    func regularSession(
        _ period: PriceChartTimeSegment,
        timeZone: TimeZone
    ) throws -> HoldingPriceSeries {
        let points = try regularPoints(in: period)
        guard let first = points.first, let last = points.last else {
            throw OneDaySeriesError.noRegularObservations
        }

        let timeDomain = coversFullCalendarDay(period, in: timeZone)
            ? PriceChartTimeDomain(start: first.date, end: last.date)
            : PriceChartTimeDomain(start: period.start, end: period.end)

        return HoldingPriceSeries(
            points: points,
            timeDomain: timeDomain,
            baselinePrice: previousClose
        )
    }

    /// A regular session followed by its Extended-Hours Continuation. The
    /// no-trade gap between post-market and the next pre-market is left out of
    /// the time axis, replaced by one observation's worth of spacing.
    func extendedSession(
        _ regular: PriceChartTimeSegment,
        postMarket: PriceChartTimeSegment?,
        preMarket: PriceChartTimeSegment?
    ) throws -> HoldingPriceSeries {
        let regularPoints = try regularPoints(in: regular)
        guard !regularPoints.isEmpty else {
            throw OneDaySeriesError.noRegularObservations
        }

        // The bar at the opening instant of post-market is the regular close's
        // bar, which `regularPoints` already replaced.
        let postMarketPoints = postMarket.map { period in
            observations
                .filter { period.start < $0.date && $0.date < period.end }
                .map { $0.inSession(.postMarket) }
        } ?? []
        let preMarketPoints = preMarket.map { period in
            observations
                .filter { period.contains($0.date) }
                .map { $0.inSession(.preMarket) }
        } ?? []

        var segments = [
            PriceChartTimeSegment(
                start: regular.start,
                end: max(regular.end, postMarketPoints.last?.date ?? regular.end)
            )
        ]
        if let preMarket, let lastPreMarketPoint = preMarketPoints.last {
            segments.append(
                PriceChartTimeSegment(
                    start: preMarket.start,
                    end: lastPreMarketPoint.date,
                    spacingBefore: granularity
                )
            )
        }

        return HoldingPriceSeries(
            points: regularPoints + postMarketPoints + preMarketPoints,
            timeDomain: PriceChartTimeDomain(segments: segments),
            baselinePrice: previousClose
        )
    }

    /// With extended hours included, the bar stamped at a session's closing
    /// boundary holds post-market trades, so its close is not the regular
    /// close (e.g. an earnings gap). A completed session therefore ends on
    /// the regular close, the value the holding quote uses.
    private func regularPoints(in period: PriceChartTimeSegment) throws -> [HoldingPricePoint] {
        let observed = observations
            .filter { period.contains($0.date) }
            .map { $0.inSession(.regular) }
        guard !observed.isEmpty, period.end <= now else {
            return observed
        }
        guard let regularClose, regularClose.isFinite, regularClose > 0 else {
            throw OneDaySeriesError.missingRegularClose
        }
        return observed + [HoldingPricePoint(date: period.end, price: regularClose, session: .regular)]
    }

    private func coversFullCalendarDay(
        _ period: PriceChartTimeSegment,
        in timeZone: TimeZone
    ) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let startOfDay = calendar.startOfDay(for: period.start)
        guard period.start == startOfDay,
              let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
        else {
            return false
        }

        let remaining = nextDay.timeIntervalSince(period.end)
        return remaining >= 0 && remaining <= granularity
    }
}
