import Foundation
import Testing
@testable import Bittern

@Suite
struct PortfolioHistoryAggregatorTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day))!
    }

    private func history(
        currency: String? = "USD",
        _ points: [(Int?, Double?)]
    ) -> AccountBalanceHistory {
        AccountBalanceHistory(
            currencyCode: currency,
            readings: points.map { day, value in
                AccountBalanceHistory.Reading(
                    date: day.map { self.date($0) },
                    totalValue: value
                )
            }
        )
    }

    private func aggregate(
        _ histories: [AccountBalanceHistory]
    ) throws -> PortfolioHistory {
        try PortfolioHistoryAggregator.aggregate(histories: histories, calendar: calendar)
    }

    @Test func sumsAccountsPerDay() throws {
        let result = try aggregate([
            history([(1, 100), (2, 110)]),
            history([(1, 10), (2, 20)])
        ])

        #expect(result.points.map(\.totalValue) == [110, 130])
        #expect(result.points.map(\.date) == [date(1), date(2)])
        #expect(result.currencyCode == "USD")
    }

    /// Account B has no point on day 2. Summing only A would draw a cliff from
    /// 1000 to 900 that never happened.
    @Test func omitsDatesAnAccountHasNoDataFor() throws {
        let result = try aggregate([
            history([(1, 900), (2, 900), (3, 900)]),
            history([(1, 100), (3, 100)])
        ])

        #expect(result.points.map(\.date) == [date(1), date(3)])
        #expect(result.points.map(\.totalValue) == [1_000, 1_000])
    }

    @Test func aLaterAccountLimitsHowFarBackTheTotalGoes() throws {
        let result = try aggregate([
            history([(1, 900), (2, 900), (3, 900)]),
            history([(3, 100)])
        ])

        #expect(result.points.map(\.date) == [date(3)])
    }

    @Test func twoPointsOnOneDayCountOnce() throws {
        let later = date(1).addingTimeInterval(3_600)
        let history = AccountBalanceHistory(
            currencyCode: "USD",
            readings: [
                AccountBalanceHistory.Reading(date: date(1), totalValue: 100),
                AccountBalanceHistory.Reading(date: later, totalValue: 120)
            ]
        )

        let result = try aggregate([history])

        #expect(result.points.map(\.totalValue) == [120])
    }

    @Test(arguments: [
        [(Int?.some(1), Double?.none)],
        [(Int?.none, Double?.some(100))],
        [(Int?.some(1), Double?.some(.nan))]
    ])
    func badPointFailsInsteadOfBeingSkipped(points: [(Int?, Double?)]) {
        #expect(throws: PortfolioHistoryError.self) {
            try aggregate([history(points)])
        }
    }

    @Test func negativeValueIsKept() throws {
        let result = try aggregate([history([(1, -50)]), history([(1, 100)])])

        #expect(result.points.map(\.totalValue) == [50])
    }

    @Test func mixedCurrenciesFail() {
        #expect(throws: PortfolioHistoryError.self) {
            try aggregate([
                history(currency: "USD", [(1, 100)]),
                history(currency: "CAD", [(1, 100)])
            ])
        }
    }

    @Test func missingCurrencyFails() {
        #expect(throws: PortfolioHistoryError.self) {
            try aggregate([history(currency: nil, [(1, 100)])])
        }
    }

    @Test func noCommonDatesFail() {
        #expect(throws: PortfolioHistoryError.self) {
            try aggregate([history([(1, 100)]), history([(2, 100)])])
        }
    }
}
