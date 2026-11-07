//
//  PerformanceChartTimeAxis.swift
//  Bittern
//
//  Where the line charts put their time labels: on calendar boundaries of
//  the device's own calendar and time zone (whole hours, trading days,
//  months, years), never at fixed fractions of the width. Working in the
//  local calendar keeps the labels right through daylight-saving changes,
//  both the device's own and the exchange's.
//

import Foundation

/// The calendar unit a chart's time axis is labelled in.
nonisolated enum PerformanceChartAxisUnit: Equatable, Sendable {
    /// Whole hours of the local clock. Only on a time scale.
    case hours
    /// Each trading day: every session after an overnight break, or every
    /// local day for an asset that trades around the clock.
    case days
    /// Month starts, every 1, 2, 3, 6 or 12 months.
    case months
    /// Year starts, every 1, 2, 5, 10 or more years.
    case years

    /// The unit for a chart whose length depends on its data, such as MAX:
    /// days under two months, months under two years, years beyond.
    static func fitting(_ dates: [Date]) -> PerformanceChartAxisUnit {
        guard let first = dates.first, let last = dates.last else { return .days }
        let span = last.timeIntervalSince(first)
        let day: TimeInterval = 86_400
        if span < 60 * day { return .days }
        if span < 730 * day { return .months }
        return .years
    }
}

/// One labelled place on the time axis.
nonisolated struct PerformanceChartTimeTick: Equatable {
    enum Kind: Equatable {
        case time
        case day
        case month
        /// A month start that begins a year, labelled with the year.
        case year
    }

    /// Where the tick sits on the chart's horizontal scale.
    let position: Double
    /// The boundary the tick marks.
    let date: Date
    let kind: Kind
}

nonisolated enum PerformanceChartTimeAxis {
    /// A gap between two points longer than this ends a trading session.
    /// Bars come at most an hour apart within a session; nights and
    /// weekends are far longer.
    static let sessionBreak: TimeInterval = 2 * 3600

    /// Labels start at their tick and run right, so a tick this close to the
    /// end would push its label past the plot.
    static let trailingMargin = 0.15

    /// The closest two ticks may be, as a share of the axis: room for a
    /// label such as "Nov 13" on the narrowest chart, five at most.
    static let minimumSpacing = 0.18

    // MARK: - Time scale

    /// Whole local hours between `start` and `end`, every 1, 2, 3, 4, 6 or
    /// 12 hours so no more than four fall on `visibleDuration` (the time
    /// the axis shows, which leaves out any no-trade gap). Hours are matched
    /// by the local clock, so they stay whole across a daylight-saving
    /// change and in zones offset by half an hour.
    static func hourBoundaries(
        from start: Date,
        to end: Date,
        visibleDuration: TimeInterval,
        calendar: Calendar
    ) -> [Date] {
        guard end > start, visibleDuration > 0 else { return [] }

        let hours = visibleDuration / 3600
        let stride = [1, 2, 3, 4, 6, 12].first { hours / Double($0) <= 4 } ?? 24
        let wholeHour = DateComponents(minute: 0, second: 0)

        var boundaries: [Date] = []
        var candidate = calendar.nextDate(
            after: start.addingTimeInterval(-1),
            matching: wholeHour,
            matchingPolicy: .nextTime
        )
        while let hour = candidate, hour <= end {
            if calendar.component(.hour, from: hour) % stride == 0 {
                boundaries.append(hour)
            }
            candidate = calendar.nextDate(after: hour, matching: wholeHour, matchingPolicy: .nextTime)
        }
        return boundaries
    }

    // MARK: - Index scale

    /// Ticks for points spaced one unit apart, so nights and weekends take
    /// no room. Each tick sits on the first point of its day, month or year.
    static func indexedTicks(
        dates: [Date],
        unit: PerformanceChartAxisUnit,
        calendar: Calendar
    ) -> [PerformanceChartTimeTick] {
        guard dates.count > 1 else { return [] }

        switch unit {
        case .hours:
            return []
        case .days:
            return dayTicks(dates: dates, calendar: calendar)
        case .months:
            return monthTicks(dates: dates, calendar: calendar)
        case .years:
            return yearTicks(dates: dates, calendar: calendar)
        }
    }

    /// A tick on the first point of each trading day.
    ///
    /// Stocks break overnight, so a day starts after each break; its label
    /// is the local date of its first point, which is the exchange's date
    /// for a US session seen from anywhere between the Americas and Asia.
    /// A local midnight would fall inside a US session when seen from Asia,
    /// so it isn't used for them. An asset that trades around the clock
    /// has no breaks (one outage aside) and changes day at local midnight.
    private static func dayTicks(dates: [Date], calendar: Calendar) -> [PerformanceChartTimeTick] {
        let breaks = dates.indices.dropFirst().filter {
            dates[$0].timeIntervalSince(dates[$0 - 1]) >= sessionBreak
        }

        if breaks.count >= 2 {
            return ([0] + breaks).map {
                PerformanceChartTimeTick(position: Double($0), date: dates[$0], kind: .day)
            }
        }

        return dates.indices.dropFirst()
            .filter { !calendar.isDate(dates[$0], inSameDayAs: dates[$0 - 1]) }
            .map {
                PerformanceChartTimeTick(
                    position: Double($0),
                    date: calendar.startOfDay(for: dates[$0]),
                    kind: .day
                )
            }
    }

    private static func monthTicks(dates: [Date], calendar: Calendar) -> [PerformanceChartTimeTick] {
        let starts = dates.indices.dropFirst().filter {
            calendar.component(.month, from: dates[$0]) != calendar.component(.month, from: dates[$0 - 1])
                || calendar.component(.year, from: dates[$0]) != calendar.component(.year, from: dates[$0 - 1])
        }
        let months = starts.map { calendar.component(.month, from: dates[$0]) }
        let stride = [1, 2, 3, 6, 12].first { stride in
            months.filter { ($0 - 1) % stride == 0 }.count <= 4
        } ?? 12

        return zip(starts, months)
            .filter { ($0.1 - 1) % stride == 0 }
            .map { index, month in
                PerformanceChartTimeTick(
                    position: Double(index),
                    date: dates[index],
                    kind: month == 1 ? .year : .month
                )
            }
    }

    private static func yearTicks(dates: [Date], calendar: Calendar) -> [PerformanceChartTimeTick] {
        let starts = dates.indices.dropFirst().filter {
            calendar.component(.year, from: dates[$0]) != calendar.component(.year, from: dates[$0 - 1])
        }
        let years = starts.map { calendar.component(.year, from: dates[$0]) }
        let stride = [1, 2, 5, 10, 25, 50, 100].first { stride in
            years.filter { $0 % stride == 0 }.count <= 5
        } ?? 100

        return zip(starts, years)
            .filter { $0.1 % stride == 0 }
            .map { PerformanceChartTimeTick(position: Double($0.0), date: dates[$0.0], kind: .year) }
    }

    // MARK: - Spacing

    /// Leaves out ticks whose labels would run past the end of `domain` or
    /// crowd the tick before them.
    static func spaced(
        _ ticks: [PerformanceChartTimeTick],
        in domain: ClosedRange<Double>
    ) -> [PerformanceChartTimeTick] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return [] }

        var kept: [PerformanceChartTimeTick] = []
        for tick in ticks.sorted(by: { $0.position < $1.position }) {
            let fraction = (tick.position - domain.lowerBound) / span
            guard fraction >= 0, fraction <= 1 - trailingMargin else { continue }
            if let last = kept.last, (tick.position - last.position) / span < minimumSpacing {
                continue
            }
            kept.append(tick)
        }
        return kept
    }
}
