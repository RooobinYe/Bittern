//
//  LiveChartTail.swift
//  Bittern
//
//  Keeps a loaded chart's last bar on the live price. Each point of a range
//  is the close of one bar of fixed length; the last is the bar in progress,
//  whose close is the price now. A new point starts only when a new bar
//  does. Pure: the observation and its time are passed in.
//

import Foundation

/// A price as it trades, with when it traded and in which session.
struct LivePriceObservation: Equatable {
    let date: Date
    let price: Double
    let session: PriceChartSession
}

/// How long one bar of a chart range lasts.
enum ChartBarLength: Equatable {
    case seconds(TimeInterval)
    /// Calendar days, weeks or months, counted in UTC.
    case calendar(Calendar.Component, Int)

    /// When the bar that starts at `start` ends.
    func end(ofBarStartingAt start: Date) -> Date {
        switch self {
        case .seconds(let length):
            return start.addingTimeInterval(length)
        case .calendar(let component, let value):
            return Self.utcCalendar.date(byAdding: component, value: value, to: start)
                ?? .distantFuture
        }
    }

    /// The start of the bar `date` falls in, counting whole bars on from
    /// `anchor`, the start of a known bar. `date` is at or after `anchor`.
    func start(ofBarContaining date: Date, anchoredAt anchor: Date) -> Date {
        switch self {
        case .seconds(let length):
            let bars = (date.timeIntervalSince(anchor) / length).rounded(.down)
            return anchor.addingTimeInterval(max(bars, 0) * length)
        case .calendar:
            var start = anchor
            // Bounded, though even a decade of months is far fewer steps.
            for _ in 0..<10_000 {
                let next = end(ofBarStartingAt: start)
                guard next <= date else { break }
                start = next
            }
            return start
        }
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}

extension HoldingChartRange {
    /// The bar each point of the range stands for, as the provider
    /// aggregates it.
    var barLength: ChartBarLength {
        switch self {
        case .oneDay:
            .seconds(5 * 60)
        case .fiveDays:
            .seconds(15 * 60)
        case .oneMonth:
            .seconds(60 * 60)
        case .threeMonths, .yearToDate, .oneYear:
            .calendar(.day, 1)
        case .fiveYears:
            .calendar(.weekOfYear, 1)
        case .max:
            .calendar(.month, 1)
        }
    }
}

enum LiveChartTail {
    enum Outcome: Equatable {
        /// The observation adds nothing: it is older than the last point or
        /// matches it.
        case unchanged
        case updated(HoldingPriceSeries)
        /// The observation belongs to a layout the series doesn't have, such
        /// as a session that began after it loaded. Only a fresh load can
        /// place it.
        case needsReload
    }

    /// `series` with its last bar following `observation`: the last point
    /// takes the observed price while the bar is still in progress, and a
    /// new point starts when the observation falls in a later bar.
    ///
    /// On a time axis (1D) a new point must fit the axis. A segment that
    /// ends at its last observation, such as an Extended-Hours
    /// Continuation, grows to take it; a scheduled end does not move.
    static func applying(
        _ observation: LivePriceObservation,
        to series: HoldingPriceSeries,
        barLength: ChartBarLength
    ) -> Outcome {
        guard let last = series.points.last,
              observation.price.isFinite,
              observation.price > 0,
              observation.date >= last.date
        else {
            return .unchanged
        }
        guard observation.session == last.session else {
            return .needsReload
        }

        var points = series.points
        if observation.date < barLength.end(ofBarStartingAt: last.date) {
            guard observation.price != last.price else { return .unchanged }
            points[points.count - 1] = HoldingPricePoint(
                date: last.date,
                price: observation.price,
                session: last.session
            )
            return .updated(series.replacingPoints(points, timeDomain: series.timeDomain))
        }

        let barStart = barLength.start(ofBarContaining: observation.date, anchoredAt: last.date)
        points.append(
            HoldingPricePoint(date: barStart, price: observation.price, session: observation.session)
        )

        guard let timeDomain = series.timeDomain else {
            return .updated(series.replacingPoints(points, timeDomain: nil))
        }
        if timeDomain.elapsedTime(for: barStart) != nil {
            return .updated(series.replacingPoints(points, timeDomain: timeDomain))
        }
        guard let lastSegment = timeDomain.segments.last,
              barStart > lastSegment.end,
              lastSegment.end == last.date
        else {
            return .needsReload
        }
        var segments = timeDomain.segments
        segments[segments.count - 1] = PriceChartTimeSegment(
            start: lastSegment.start,
            end: barStart,
            spacingBefore: lastSegment.spacingBefore
        )
        return .updated(
            series.replacingPoints(points, timeDomain: PriceChartTimeDomain(segments: segments))
        )
    }
}

extension HoldingPriceSeries {
    func replacingPoints(
        _ points: [HoldingPricePoint],
        timeDomain: PriceChartTimeDomain?
    ) -> HoldingPriceSeries {
        var series = HoldingPriceSeries(
            points: points,
            timeDomain: timeDomain,
            baselinePrice: baselinePrice
        )
        series.firstTradeDate = firstTradeDate
        return series
    }
}

extension PortfolioHolding {
    /// The price a chart of `range` follows now. 1D follows an active pre- or
    /// post-market trade on its Extended-Hours Continuation; every other
    /// range, and 1D otherwise, follows the regular price. A regular trade
    /// at or after the close belongs to the session's last bar, as the
    /// provider aggregates it, except on 1D, whose completed session ends on
    /// a point at the close.
    func liveObservation(for range: HoldingChartRange, at now: Date) -> LivePriceObservation? {
        if range == .oneDay {
            for (change, session) in [
                (activePostMarketChange(at: now), PriceChartSession.postMarket),
                (activePreMarketChange(at: now), .preMarket)
            ] {
                if let change, let price = change.price, let observedAt = change.observedAt {
                    return LivePriceObservation(date: observedAt, price: price, session: session)
                }
            }
        }

        guard let currentPrice else { return nil }
        var date = regularPriceTime ?? now
        if range != .oneDay, let marketSession, date >= marketSession.regularEnd {
            date = marketSession.regularEnd.addingTimeInterval(-1)
        }
        return LivePriceObservation(date: date, price: currentPrice, session: .regular)
    }
}
