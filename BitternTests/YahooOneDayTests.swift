import Foundation
import Testing
@testable import Bittern

extension NetworkTests {
    /// The 1D chart at each point of a trading day, from JSON fixtures and an
    /// injected clock.
    @Suite struct YahooOneDayTests {
        private func series(
            fixture: String,
            at date: Date,
            kind: PortfolioInstrumentKind? = .stock
        ) async throws -> HoldingPriceSeries {
            let data = try Fixture.data(fixture)
            let session = StubURLProtocol.session { _ in (200, data) }
            let client = YahooFinanceClient(session: session, currentDate: { date })
            return try await client.priceHistory(for: "TEST", instrumentKind: kind, currencyCode: "USD", range: .oneDay)
        }

        @Test func duringTheRegularSessionShowsOnlyThatSession() async throws {
            let series = try await series(
                fixture: "yahoo-history-regular",
                at: marketTime(day: 6, hour: 11)
            )

            #expect(series.points.map(\.price) == [106, 107])
            #expect(series.points.allSatisfy { $0.session == .regular })
            #expect(series.baselinePrice == 102.5)
            // The session keeps its true bounds so the trace stops mid-chart.
            #expect(series.timeDomain?.start == marketTime(day: 6, hour: 9, minute: 30))
            #expect(series.timeDomain?.end == marketTime(day: 6, hour: 16))
        }

        @Test func afterTheCloseEndsOnTheRegularCloseThenPostMarket() async throws {
            let series = try await series(
                fixture: "yahoo-history-postmarket",
                at: marketTime(day: 6, hour: 17, minute: 30)
            )

            // 160, the bar stamped at the closing boundary, holds post-market
            // trades and must not stand in for the 108.5 regular close.
            #expect(series.points.map(\.price) == [106, 107, 108, 108.5, 109])
            #expect(series.points.map(\.session) == [.regular, .regular, .regular, .regular, .postMarket])
            #expect(series.points[3].date == marketTime(day: 6, hour: 16))
            #expect(series.baselinePrice == 102.5)
            #expect(series.timeDomain?.segments.count == 1)
            #expect(series.timeDomain?.end == marketTime(day: 6, hour: 17))
        }

        @Test func beforeTheOpenContinuesThePreviousCycleIntoPreMarket() async throws {
            let series = try await series(
                fixture: "yahoo-history-premarket",
                at: marketTime(day: 6, hour: 8)
            )

            #expect(series.points.map(\.price) == [100, 101, 102, 102.5, 103, 104])
            #expect(
                series.points.map(\.session)
                    == [.regular, .regular, .regular, .regular, .postMarket, .preMarket]
            )
            #expect(series.baselinePrice == 99)

            let segments = try #require(series.timeDomain?.segments)
            #expect(segments.count == 2)
            #expect(segments[0].end == marketTime(day: 5, hour: 17))
            #expect(segments[1].start == marketTime(day: 6, hour: 4))
            #expect(segments[1].end == marketTime(day: 6, hour: 7))
            #expect(segments[1].spacingBefore == 300)
        }

        @Test(arguments: [
            marketTime(day: 6, hour: 22),
            marketTime(day: 7, hour: 12)
        ])
        func whileClosedKeepsTheLastCycle(at date: Date) async throws {
            let series = try await series(fixture: "yahoo-history-closed", at: date)

            #expect(series.points.map(\.price) == [106, 107, 108, 108.5, 109])
            #expect(series.points.last?.session == .postMarket)
        }

        @Test func cryptoUsesTheCurrentUTCDayWithAFullWidthChart() async throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6))!

            let series = try await series(
                fixture: "yahoo-history-crypto",
                at: start.addingTimeInterval(7_300),
                kind: .crypto
            )

            #expect(series.points.map(\.price) == [70_000, 70_100, 70_300])
            #expect(series.timeDomain?.start == start)
            #expect(series.timeDomain?.end == start.addingTimeInterval(86_400))
            #expect(series.baselinePrice == nil)
        }

        @Test func unexpectedMetadataFailsInsteadOfGuessing() async throws {
            let original = try Fixture.data("yahoo-history-regular")
            let tampered = String(decoding: original, as: UTF8.self)
                .replacingOccurrences(of: "\"range\": \"5d\"", with: "\"range\": \"1d\"")
            let session = StubURLProtocol.session { _ in (200, Data(tampered.utf8)) }
            let now = marketTime(day: 6, hour: 11)
            let client = YahooFinanceClient(session: session, currentDate: { now })

            await #expect(throws: YahooFinanceError.self) {
                try await client.priceHistory(for: "TEST", instrumentKind: .stock, currencyCode: "USD", range: .oneDay)
            }
        }
    }

    @Suite struct YahooPriceHistoryCurrencyTests {
        @Test func refusesAChartQuotedInAnotherCurrency() async throws {
            let data = try Fixture.data("yahoo-history-regular")
            let session = StubURLProtocol.session { _ in (200, data) }
            let now = marketTime(day: 6, hour: 11)
            let client = YahooFinanceClient(session: session, currentDate: { now })

            await #expect(throws: YahooFinanceError.self) {
                try await client.priceHistory(
                    for: "TEST",
                    instrumentKind: .stock,
                    currencyCode: "GBP",
                    range: .threeMonths
                )
            }
        }
    }

    /// Extended-hours enrichment of the quote used for holding values.
    @Suite struct YahooExtendedHoursQuoteTests {
        private func batch(
            at date: Date,
            intraday: String?
        ) async throws -> YahooQuoteBatch {
            let quote = try Fixture.data("yahoo-quote-extended-hours")
            let detail = try intraday.map { try Fixture.data($0) }
            let session = StubURLProtocol.session { request in
                if request.queryValue("interval") == "1d" {
                    return (200, quote)
                }
                guard let detail else { return (500, Data()) }
                return (200, detail)
            }
            let client = YahooFinanceClient(session: session, currentDate: { date })
            return try await client.quotes(
                for: [YahooQuoteRequest(symbol: "test", instrumentKind: .stock)]
            )
        }

        @Test func regularSessionHasNoExtendedQuote() async throws {
            let batch = try await batch(at: marketTime(day: 6, hour: 11), intraday: nil)
            let quote = try #require(batch.quotes["TEST"])

            #expect(quote.regularMarketPrice == 108.5)
            #expect(quote.preMarket == nil)
            #expect(quote.postMarket == nil)
            #expect(!batch.didFailExtendedHours)
            #expect(StubURLProtocol.requests.count == 1)
        }

        @Test func postMarketUsesLatestObservationInsideTheSession() async throws {
            let batch = try await batch(
                at: marketTime(day: 6, hour: 17, minute: 30),
                intraday: "yahoo-intraday-postmarket-trades"
            )
            let postMarket = try #require(batch.quotes["TEST"]?.postMarket)

            #expect(postMarket.price == 109)
            #expect(postMarket.regularClose == 108.5)
            #expect(postMarket.observedAt == marketTime(day: 6, hour: 17))
            #expect(batch.quotes["TEST"]?.preMarket == nil)
        }

        @Test func activeSessionWithoutTradesIsUnchangedFromTheClose() async throws {
            let batch = try await batch(
                at: marketTime(day: 6, hour: 16, minute: 1),
                intraday: "yahoo-intraday-postmarket-no-trades"
            )
            let postMarket = try #require(batch.quotes["TEST"]?.postMarket)

            #expect(postMarket.price == 108.5)
            #expect(postMarket.observedAt == nil)
        }

        @Test func preMarketUsesLatestObservationInsideTheSession() async throws {
            let batch = try await batch(
                at: marketTime(day: 6, hour: 8),
                intraday: "yahoo-intraday-premarket-trades"
            )
            let preMarket = try #require(batch.quotes["TEST"]?.preMarket)

            #expect(preMarket.price == 104)
            #expect(batch.quotes["TEST"]?.postMarket == nil)
        }

        @Test func enrichmentFailureKeepsRegularQuotesAndSaysSo() async throws {
            let batch = try await batch(
                at: marketTime(day: 6, hour: 17, minute: 30),
                intraday: nil
            )

            #expect(batch.didFailExtendedHours)
            #expect(batch.quotes["TEST"]?.regularMarketPrice == 108.5)
            #expect(batch.quotes["TEST"]?.postMarket == nil)
        }
    }
}
