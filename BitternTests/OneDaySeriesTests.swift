import Foundation
import Testing
@testable import Bittern

/// The 1D layout on its own, with no provider in between. The TradingView
/// price history tests cover the same rules end to end.
@Suite
struct OneDaySeriesTests {
    private let eastern = TimeZone(secondsFromGMT: -18_000)!

    private func period(day: Int, from start: (Int, Int), to end: (Int, Int)) -> PriceChartTimeSegment {
        PriceChartTimeSegment(
            start: marketTime(day: day, hour: start.0, minute: start.1),
            end: marketTime(day: day, hour: end.0, minute: end.1)
        )
    }

    private func point(day: Int = 6, _ hour: Int, _ minute: Int = 0, _ price: Double) -> HoldingPricePoint {
        HoldingPricePoint(date: marketTime(day: day, hour: hour, minute: minute), price: price)
    }

    private var schedule: ExchangeTradingSchedule {
        ExchangeTradingSchedule(
            regular: [period(day: 5, from: (9, 30), to: (16, 0)), period(day: 6, from: (9, 30), to: (16, 0))],
            preMarket: [period(day: 5, from: (4, 0), to: (9, 30)), period(day: 6, from: (4, 0), to: (9, 30))],
            postMarket: [period(day: 5, from: (16, 0), to: (20, 0)), period(day: 6, from: (16, 0), to: (20, 0))],
            timeZone: eastern
        )
    }

    private func displayCycle(
        _ observations: [HoldingPricePoint],
        at now: Date
    ) throws -> HoldingPriceSeries {
        try OneDaySeries.displayCycle(
            observations: observations,
            schedule: schedule,
            granularity: 300,
            previousClose: 100,
            regularClose: 108.5,
            at: now
        )
    }

    @Test func aSessionInProgressKeepsItsBoundsAndShowsOnlyItself() throws {
        let series = try displayCycle(
            [point(day: 5, 15, 0, 99), point(9, 30, 101), point(10, 0, 102)],
            at: marketTime(day: 6, hour: 11)
        )

        #expect(series.points.map(\.price) == [101, 102])
        #expect(series.timeDomain == PriceChartTimeDomain(start: marketTime(day: 6, hour: 9, minute: 30), end: marketTime(day: 6, hour: 16)))
        #expect(series.baselinePrice == 100)
    }

    /// The bar stamped at the close holds post-market trades. The regular
    /// close replaces it, and post-market follows as a continuation.
    @Test func aCompletedSessionEndsOnTheRegularCloseBeforePostMarket() throws {
        let series = try displayCycle(
            [point(15, 55, 107), point(16, 0, 160), point(16, 30, 109)],
            at: marketTime(day: 6, hour: 17)
        )

        #expect(series.points.map(\.price) == [107, 108.5, 109])
        #expect(series.points.map(\.session) == [.regular, .regular, .postMarket])
        #expect(series.timeDomain?.end == marketTime(day: 6, hour: 16, minute: 30))
    }

    @Test func preMarketJoinsThePreviousCycleAfterOneStepOfSpacing() throws {
        let series = try displayCycle(
            [point(day: 5, 15, 55, 100), point(day: 5, 17, 0, 101), point(5, 0, 102), point(7, 0, 103)],
            at: marketTime(day: 6, hour: 8)
        )

        #expect(series.points.map(\.session) == [.regular, .regular, .postMarket, .preMarket, .preMarket])
        let segments = try #require(series.timeDomain?.segments)
        #expect(segments.count == 2)
        #expect(segments[1].start == marketTime(day: 6, hour: 4))
        #expect(segments[1].end == marketTime(day: 6, hour: 7))
        #expect(segments[1].spacingBefore == 300)
    }

    @Test func aCompletedSessionWithoutARegularCloseFails() {
        #expect(throws: OneDaySeriesError.missingRegularClose) {
            try OneDaySeries.displayCycle(
                observations: [point(15, 55, 107)],
                schedule: schedule,
                granularity: 300,
                previousClose: 100,
                regularClose: nil,
                at: marketTime(day: 6, hour: 22)
            )
        }
    }

    @Test func noRegularPeriodsFail() {
        let empty = ExchangeTradingSchedule(regular: [], preMarket: [], postMarket: [], timeZone: eastern)

        #expect(throws: OneDaySeriesError.noRegularPeriods) {
            try OneDaySeries.displayCycle(
                observations: [point(10, 0, 100)],
                schedule: empty,
                granularity: 300,
                previousClose: nil,
                regularClose: nil,
                at: marketTime(day: 6, hour: 11)
            )
        }
    }

    @Test func aFullDayWindowSpansTheWholeUTCDay() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = utc.date(from: DateComponents(year: 2026, month: 11, day: 6))!

        let series = try OneDaySeries.fullDay(
            observations: [
                HoldingPricePoint(date: midnight.addingTimeInterval(-300), price: 1),
                HoldingPricePoint(date: midnight.addingTimeInterval(300), price: 2),
                HoldingPricePoint(date: midnight.addingTimeInterval(7_200), price: 3)
            ],
            at: midnight.addingTimeInterval(3_600)
        )

        #expect(series.points.map(\.price) == [2])
        #expect(series.timeDomain == PriceChartTimeDomain(start: midnight, end: midnight.addingTimeInterval(86_400)))
        #expect(series.baselinePrice == nil)
    }
}
