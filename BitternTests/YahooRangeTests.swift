import Foundation
import Testing
@testable import Bittern

extension NetworkTests {
    /// Ranges past 1D: what Yahoo is asked for, and where YTD starts.
    @Suite struct YahooRangeTests {
        private func series(_ data: Data, range: HoldingChartRange) async throws -> HoldingPriceSeries {
            let session = StubURLProtocol.session { _ in (200, data) }
            let client = YahooFinanceClient(session: session, currentDate: { marketTime(day: 6, hour: 22) })
            return try await client.priceHistory(for: "TEST", instrumentKind: .stock, currencyCode: "USD", range: range)
        }

        private func yearToDate(replacing original: String, with replacement: String) throws -> Data {
            let fixture = String(decoding: try Fixture.data("yahoo-history-ytd"), as: UTF8.self)
            let tampered = fixture.replacingOccurrences(of: original, with: replacement)
            #expect(tampered != fixture)
            return Data(tampered.utf8)
        }

        @Test func yearToDateIsMeasuredFromLastYearsFinalClose() async throws {
            let series = try await series(try Fixture.data("yahoo-history-ytd"), range: .yearToDate)

            #expect(series.points.map(\.price) == [82, 84, 108.5])
            // 31 December's close, not 2 January's first point.
            #expect(series.baselinePrice == 80)
            let request = try #require(StubURLProtocol.requests.last)
            #expect(request.queryValue("range") == "ytd")
            #expect(request.queryValue("interval") == "1d")
        }

        @Test func yearToDateWithoutLastYearsCloseFails() async throws {
            let data = try yearToDate(replacing: "\"chartPreviousClose\": 80.0", with: "\"chartPreviousClose\": null")

            await #expect(throws: YahooFinanceError.self) {
                try await series(data, range: .yearToDate)
            }
        }

        /// Yahoo's previous close is the one before the chart's first point,
        /// so it is last year's only on a year-to-date chart.
        @Test func yearToDateRefusesAChartOfAnotherRange() async throws {
            let data = try yearToDate(replacing: "\"range\": \"ytd\"", with: "\"range\": \"1y\"")

            await #expect(throws: YahooFinanceError.self) {
                try await series(data, range: .yearToDate)
            }
        }

        @Test func oneMonthAsksForHourlyBarsAndStartsFromItsFirstPoint() async throws {
            let series = try await series(try Fixture.data("yahoo-history-ytd"), range: .oneMonth)

            #expect(series.baselinePrice == nil)
            let request = try #require(StubURLProtocol.requests.last)
            #expect(request.queryValue("range") == "1mo")
            #expect(request.queryValue("interval") == "1h")
            #expect(request.queryValue("includePrePost") == "false")
        }
    }
}
