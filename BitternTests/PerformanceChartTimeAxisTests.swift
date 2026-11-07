import Foundation
import Testing
@testable import Bittern

@Suite
struct PerformanceChartTimeAxisTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func hours(_ dates: [Date], in calendar: Calendar) -> [Int] {
        dates.map { calendar.component(.hour, from: $0) }
    }

    /// Bars every `step` from `start` to `end`, both included.
    private func bars(from start: Date, to end: Date, every step: TimeInterval) -> [Date] {
        Array(stride(from: start.timeIntervalSince1970, through: end.timeIntervalSince1970, by: step))
            .map(Date.init(timeIntervalSince1970:))
    }

    // MARK: - Hours

    @Test func aUSSessionInSummerIsLabelledOnWholeLocalHours() {
        // 9:30–16:00 EDT is 21:30–04:00 in Shanghai.
        let shanghai = calendar("Asia/Shanghai")
        let boundaries = PerformanceChartTimeAxis.hourBoundaries(
            from: utc(2026, 7, 15, 13, 30),
            to: utc(2026, 7, 15, 20),
            visibleDuration: 6.5 * 3600,
            calendar: shanghai
        )

        #expect(hours(boundaries, in: shanghai) == [22, 0, 2, 4])
    }

    @Test func theSameSessionInWinterMovesAnHourButStaysOnWholeHours() {
        // 9:30–16:00 EST is 22:30–05:00 in Shanghai.
        let shanghai = calendar("Asia/Shanghai")
        let boundaries = PerformanceChartTimeAxis.hourBoundaries(
            from: utc(2026, 11, 6, 14, 30),
            to: utc(2026, 11, 6, 21),
            visibleDuration: 6.5 * 3600,
            calendar: shanghai
        )

        #expect(hours(boundaries, in: shanghai) == [0, 2, 4])
    }

    @Test func theDayClocksGoBackHasNoRepeatedLabel() {
        // On 1 Nov 2026 New York's 1 AM happens twice.
        let newYork = calendar("America/New_York")
        let start = newYork.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let boundaries = PerformanceChartTimeAxis.hourBoundaries(
            from: start,
            to: start.addingTimeInterval(13 * 3600),
            visibleDuration: 12 * 3600,
            calendar: newYork
        )

        #expect(hours(boundaries, in: newYork) == [0, 3, 6, 9, 12])
    }

    @Test func theDayClocksGoForwardSkipsTheMissingHour() {
        // On 8 Mar 2026 New York goes from 1:59 AM to 3 AM.
        let newYork = calendar("America/New_York")
        let start = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let boundaries = PerformanceChartTimeAxis.hourBoundaries(
            from: start,
            to: start.addingTimeInterval(3 * 3600),
            visibleDuration: 3 * 3600,
            calendar: newYork
        )

        #expect(hours(boundaries, in: newYork) == [0, 1, 3, 4])
    }

    @Test func aZoneOffsetByHalfAnHourStillGetsWholeHours() {
        let kolkata = calendar("Asia/Kolkata")
        let boundaries = PerformanceChartTimeAxis.hourBoundaries(
            from: utc(2026, 11, 6, 14, 30),
            to: utc(2026, 11, 6, 21),
            visibleDuration: 6.5 * 3600,
            calendar: kolkata
        )

        #expect(!boundaries.isEmpty)
        #expect(boundaries.allSatisfy { kolkata.component(.minute, from: $0) == 0 })
    }

    @Test func aRoundTheClockDayIsLabelledEverySixHours() {
        // A crypto 1D chart spans the UTC day: 08:00 to 08:00 in Shanghai.
        let shanghai = calendar("Asia/Shanghai")
        let boundaries = PerformanceChartTimeAxis.hourBoundaries(
            from: utc(2026, 11, 7, 0),
            to: utc(2026, 11, 8, 0),
            visibleDuration: 24 * 3600,
            calendar: shanghai
        )

        #expect(hours(boundaries, in: shanghai) == [12, 18, 0, 6])
    }

    // MARK: - Days

    @Test func eachUSTradingDayIsLabelledWithItsDateAcrossTheClockChange() {
        // Thu 29 and Fri 30 Oct in EDT, then Mon 2 to Wed 4 Nov in EST, seen
        // from Shanghai where each session crosses local midnight.
        let shanghai = calendar("Asia/Shanghai")
        let sessions = [
            (utc(2026, 10, 29, 13, 30), utc(2026, 10, 29, 20)),
            (utc(2026, 10, 30, 13, 30), utc(2026, 10, 30, 20)),
            (utc(2026, 11, 2, 14, 30), utc(2026, 11, 2, 21)),
            (utc(2026, 11, 3, 14, 30), utc(2026, 11, 3, 21)),
            (utc(2026, 11, 4, 14, 30), utc(2026, 11, 4, 21)),
        ]
        let dates = sessions.flatMap { bars(from: $0.0, to: $0.1, every: 1800) }

        let ticks = PerformanceChartTimeAxis.indexedTicks(dates: dates, unit: .days, calendar: shanghai)

        #expect(ticks.map { shanghai.component(.day, from: $0.date) } == [29, 30, 2, 3, 4])
        #expect(ticks.allSatisfy { $0.kind == .day })
        #expect(ticks.first?.position == 0)
    }

    @Test func aRoundTheClockAssetChangesDayAtLocalMidnight() {
        let shanghai = calendar("Asia/Shanghai")
        var dates = bars(from: utc(2026, 11, 3, 0), to: utc(2026, 11, 6, 0), every: 900)
        // One outage doesn't make it a stock.
        dates.removeAll { utc(2026, 11, 4, 6) < $0 && $0 < utc(2026, 11, 4, 9) }

        let ticks = PerformanceChartTimeAxis.indexedTicks(dates: dates, unit: .days, calendar: shanghai)

        #expect(ticks.map { shanghai.component(.day, from: $0.date) } == [4, 5, 6])
        #expect(ticks.allSatisfy { shanghai.component(.hour, from: $0.date) == 0 })
    }

    // MARK: - Months and years

    @Test func threeMonthsGetEachMonthStart() {
        let shanghai = calendar("Asia/Shanghai")
        let dates = bars(from: utc(2026, 8, 10, 13, 30), to: utc(2026, 11, 6, 13, 30), every: 86_400)

        let ticks = PerformanceChartTimeAxis.indexedTicks(dates: dates, unit: .months, calendar: shanghai)

        #expect(ticks.map { shanghai.component(.month, from: $0.date) } == [9, 10, 11])
        #expect(ticks.allSatisfy { $0.kind == .month })
    }

    @Test func aYearGetsQuartersWithTheYearAtJanuary() {
        let shanghai = calendar("Asia/Shanghai")
        let dates = bars(from: utc(2025, 11, 7, 13, 30), to: utc(2026, 11, 6, 13, 30), every: 86_400)

        let ticks = PerformanceChartTimeAxis.indexedTicks(dates: dates, unit: .months, calendar: shanghai)

        #expect(ticks.map { shanghai.component(.month, from: $0.date) } == [1, 4, 7, 10])
        #expect(ticks.map(\.kind) == [.year, .month, .month, .month])
    }

    @Test func everyYearIsLabelledWithNoneSkipped() {
        let shanghai = calendar("Asia/Shanghai")
        let dates = bars(from: utc(2021, 6, 15, 13, 30), to: utc(2026, 11, 6, 13, 30), every: 7 * 86_400)

        let ticks = PerformanceChartTimeAxis.indexedTicks(dates: dates, unit: .years, calendar: shanghai)

        #expect(ticks.map { shanghai.component(.year, from: $0.date) } == [2022, 2023, 2024, 2025, 2026])
    }

    @Test func decadesOfHistoryAreLabelledOnRoundYears() {
        let shanghai = calendar("Asia/Shanghai")
        let dates = bars(from: utc(1996, 3, 1, 14, 30), to: utc(2026, 11, 6, 14, 30), every: 30 * 86_400)

        let ticks = PerformanceChartTimeAxis.indexedTicks(dates: dates, unit: .years, calendar: shanghai)

        #expect(ticks.map { shanghai.component(.year, from: $0.date) } == [2000, 2010, 2020])
    }

    // MARK: - Spacing

    @Test func ticksTooCloseToTheEndOrToEachOtherAreLeftOut() {
        let date = Date(timeIntervalSince1970: 0)
        let ticks = [0, 5, 30, 60, 90].map {
            PerformanceChartTimeTick(position: Double($0), date: date, kind: .day)
        }

        let spaced = PerformanceChartTimeAxis.spaced(ticks, in: 0...100)

        #expect(spaced.map(\.position) == [0, 30, 60])
    }
}
