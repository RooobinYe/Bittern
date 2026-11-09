import Foundation
import Testing
@testable import Bittern

/// Waits for `condition`, failing after about a second.
private func eventually(_ condition: () async throws -> Bool) async throws {
    for _ in 0..<100 {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Condition never became true")
}

private let eastern = TimeZone(identifier: "America/New_York")!

@Suite
struct TradingViewProtocolTests {
    @Test func framesCountUTF16CodeUnits() throws {
        let packet = TradingViewFraming.encode(#"{"m":"a","p":["トヨタ"]}"#)
            + TradingViewFraming.encode("~h~7")
            + TradingViewFraming.encode(#"{"m":"b","p":["😀"]}"#)

        let frames = try TradingViewFraming.decode(packet)

        #expect(frames == [
            .message(#"{"m":"a","p":["トヨタ"]}"#),
            .heartbeat("~h~7"),
            .message(#"{"m":"b","p":["😀"]}"#)
        ])
    }

    @Test(arguments: ["~m~10~m~short", "~m~x~m~{}", "{}"])
    func aPacketThatDoesNotParseWholeIsRejected(packet: String) {
        #expect(throws: TradingViewError.malformedFrame) {
            try TradingViewFraming.decode(packet)
        }
    }

    @Test func messagesRoundTrip() throws {
        let encoded = try TradingViewFraming.encode(method: "quote_add_symbols", params: [.string("qs_1"), .string("NASDAQ:AAPL")])
        let frame = try #require(try TradingViewFraming.decode(encoded).first)
        guard case .message(let payload) = frame else {
            Issue.record("Expected a message")
            return
        }

        let message = try #require(try TradingViewFraming.message(from: payload))

        #expect(message.method == "quote_add_symbols")
        #expect(message.sessionID == "qs_1")
        #expect(message.params.last?.string == "NASDAQ:AAPL")
    }

    @Test func theGreetingIsNotAMessage() throws {
        #expect(try TradingViewFraming.message(from: #"{"session_id":"x","protocol":"json"}"#) == nil)
    }
}

@Suite
struct TradingViewSessionCalendarTests {
    private let calendar = try! TradingViewSessionCalendar(
        timeZone: "America/New_York",
        subsessions: FakeMarket.usStockSubsessions,
        holidays: FakeMarket.usHolidays
    )

    private func day(_ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: 2026, month: month, day: day)
    }

    private func time(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func aWeekdayRunsFromPreMarketToPostMarket() throws {
        let friday = try #require(calendar.tradingDay(on: day(11, 6)))

        #expect(friday.start == time(11, 6, 4))
        #expect(friday.regularStart == time(11, 6, 9, 30))
        #expect(friday.regularEnd == time(11, 6, 16))
        #expect(friday.end == time(11, 6, 20))
    }

    @Test func weekendsAndHolidaysHaveNoTradingDay() {
        #expect(calendar.tradingDay(on: day(11, 7)) == nil)
        #expect(calendar.tradingDay(on: day(11, 8)) == nil)
        #expect(calendar.tradingDay(on: day(11, 26)) == nil)
    }

    @Test func aCorrectionShortensTheDay() throws {
        let blackFriday = try #require(calendar.tradingDay(on: day(11, 27)))

        #expect(blackFriday.regularEnd == time(11, 27, 13))
        #expect(blackFriday.end == time(11, 27, 17))
    }

    /// Hours are exchange wall-clock times, so they hold across a change of
    /// daylight-saving time.
    @Test func hoursFollowTheExchangeClockAcrossDaylightSaving() throws {
        let beforeChange = try #require(calendar.tradingDay(on: day(10, 30)))
        let afterChange = try #require(calendar.tradingDay(on: day(11, 2)))

        #expect(beforeChange.regularStart == time(10, 30, 9, 30))
        #expect(afterChange.regularStart == time(11, 2, 9, 30))
        #expect(afterChange.regularStart.timeIntervalSince(beforeChange.regularStart) == 3 * 86_400 + 3_600)
    }

    @Test func afterTheCloseTheLatestDayStaysUntilTheNextBegins() throws {
        let sunday = try #require(calendar.latestTradingDay(startedBy: time(11, 8, 11)))
        let mondayPreMarket = try #require(calendar.latestTradingDay(startedBy: time(11, 9, 4, 30)))

        #expect(sunday.regularStart == time(11, 6, 9, 30))
        #expect(mondayPreMarket.regularStart == time(11, 9, 9, 30))
    }

    /// The overnight session leads into the next trading day: after Friday
    /// it runs from Sunday 20:00 to Monday's pre-market.
    @Test func theOvernightSessionFollowsTheTradingDay() throws {
        let sundayNight = try #require(calendar.latestTradingDay(startedBy: time(11, 8, 23, 15)))
        let tuesdayNight = try #require(calendar.latestTradingDay(startedBy: time(11, 10, 21)))

        #expect(sundayNight.regularStart == time(11, 6, 9, 30))
        #expect(sundayNight.overnight == DateInterval(start: time(11, 8, 20), end: time(11, 9, 4)))
        #expect(tuesdayNight.overnight == DateInterval(start: time(11, 10, 20), end: time(11, 11, 4)))
    }

    /// Before a holiday the overnight session leads into the next trading
    /// day instead.
    @Test func aHolidayHasNoOvernightSession() throws {
        let wednesday = try #require(calendar.tradingDay(on: day(11, 25)))

        #expect(calendar.overnight(after: wednesday) == DateInterval(start: time(11, 26, 20), end: time(11, 27, 4)))
    }

    /// Out of session TradingView stamps the regular close with the end of
    /// the trading day; it belongs to the session's last second.
    @Test func aCloseStampedAfterHoursMovesIntoTheSession() {
        #expect(calendar.regularTradeTime(for: time(11, 6, 19, 59)) == time(11, 6, 16).addingTimeInterval(-1))
        #expect(calendar.regularTradeTime(for: time(11, 6, 11, 15)) == time(11, 6, 11, 15))
    }

    @Test func aroundTheClockHasNoTradingDay() throws {
        let crypto = try TradingViewSessionCalendar(
            timeZone: "Etc/UTC",
            subsessions: FakeMarket.cryptoSubsessions,
            holidays: nil
        )

        #expect(crypto.tradesAroundTheClock)
        #expect(crypto.latestTradingDay(startedBy: time(11, 8, 11)) == nil)
    }

    @Test(arguments: ["0930-1600:89", "9:30-16:00", "2500-2600"])
    func unreadableHoursFail(session: String) {
        let subsessions = JSONValue.array([.object(["id": .string("regular"), "session": .string(session)])])
        #expect(throws: TradingViewError.self) {
            try TradingViewSessionCalendar(timeZone: "America/New_York", subsessions: subsessions, holidays: nil)
        }
    }
}

@Suite
struct TradingViewQuoteTests {
    @Test func quotesAreKeyedByTheHoldingsOwnSymbol() async throws {
        let server = FakeTradingViewServer(quotes: [
            "AAPL": FakeMarket.stockQuote(price: 110, previousClose: 105),
            "CRYPTO:BTCUSD": FakeMarket.cryptoQuote(price: 75_000, previousClose: 74_000)
        ])
        let client = server.client(at: marketTime(day: 8, hour: 11))

        let batch = try await client.quotes(for: [
            MarketQuoteRequest(symbol: "aapl", instrumentKind: .stock),
            MarketQuoteRequest(symbol: "BTC", instrumentKind: .crypto)
        ])

        let apple = try #require(batch.quotes["AAPL"])
        #expect(apple.regularMarketPrice == 110)
        #expect(apple.regularMarketPreviousClose == 105)
        #expect(apple.currency == "USD")
        // Sunday: the trading day is still Friday's, and the close it
        // stamps at 19:59 belongs to the regular session.
        #expect(apple.marketSession?.regularStart == marketTime(day: 6, hour: 9, minute: 30))
        #expect(apple.regularMarketTime == marketTime(day: 6, hour: 16).addingTimeInterval(-1))
        #expect(apple.preMarket == nil && apple.postMarket == nil)

        let bitcoin = try #require(batch.quotes["BTC"])
        #expect(bitcoin.regularMarketPrice == 75_000)
        #expect(bitcoin.marketSession == nil)
        #expect(!batch.didFailExtendedHours)

        let added = server.messages(named: "quote_add_symbols").flatMap { $0.params.dropFirst().compactMap(\.string) }
        #expect(Set(added) == ["AAPL", "CRYPTO:BTCUSD"])
    }

    @Test func aRejectedSymbolIsLeftOutAndAllRejectedFails() async throws {
        let server = FakeTradingViewServer(quotes: ["AAPL": FakeMarket.stockQuote()])
        let client = server.client(at: marketTime(day: 6, hour: 11))

        let batch = try await client.quotes(for: [
            MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock),
            MarketQuoteRequest(symbol: "NOPE", instrumentKind: .stock)
        ])
        #expect(Set(batch.quotes.keys) == ["AAPL"])

        await #expect(throws: TradingViewError.noMarketData) {
            try await client.quotes(for: [MarketQuoteRequest(symbol: "NOPE", instrumentKind: .stock)])
        }
    }

    @Test func aPostMarketTradeIsTheExtendedHoursQuote() async throws {
        let server = FakeTradingViewServer(quotes: [
            "AAPL": FakeMarket.stockQuote(
                price: 110,
                extendedPrice: 112,
                extendedTime: marketTime(day: 6, hour: 17, minute: 20)
            )
        ])
        let client = server.client(at: marketTime(day: 6, hour: 17, minute: 30))

        let batch = try await client.quotes(for: [MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock)])
        let postMarket = try #require(batch.quotes["AAPL"]?.postMarket)

        #expect(postMarket.price == 112)
        #expect(postMarket.regularClose == 110)
        #expect(postMarket.observedAt == marketTime(day: 6, hour: 17, minute: 20))
        #expect(postMarket.sessionStart == marketTime(day: 6, hour: 16))
        #expect(postMarket.sessionEnd == marketTime(day: 6, hour: 20))
        #expect(batch.quotes["AAPL"]?.preMarket == nil)
    }

    /// An extended-hours price from an earlier session isn't a trade in this
    /// one: until the first, the session's change is zero.
    @Test func anOldExtendedHoursPriceIsNotATradeInThisSession() async throws {
        let server = FakeTradingViewServer(quotes: [
            "AAPL": FakeMarket.stockQuote(
                price: 110,
                extendedPrice: 99,
                extendedTime: marketTime(day: 5, hour: 19)
            )
        ])
        let client = server.client(at: marketTime(day: 9, hour: 5))

        let batch = try await client.quotes(for: [MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock)])
        let preMarket = try #require(batch.quotes["AAPL"]?.preMarket)

        #expect(preMarket.price == 110)
        #expect(preMarket.observedAt == nil)
        #expect(preMarket.sessionStart == marketTime(day: 9, hour: 4))
        #expect(preMarket.sessionEnd == marketTime(day: 9, hour: 9, minute: 30))
    }

    @Test func anOvernightTradeIsTheOvernightQuote() async throws {
        let server = FakeTradingViewServer(quotes: [
            "AAPL": FakeMarket.stockQuote(
                price: 110,
                overnightPrice: 111.5,
                overnightTime: marketTime(day: 8, hour: 23, minute: 14)
            )
        ])
        let client = server.client(at: marketTime(day: 8, hour: 23, minute: 15))

        let batch = try await client.quotes(for: [MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock)])
        let quote = try #require(batch.quotes["AAPL"])
        let overnight = try #require(quote.overnight)

        #expect(overnight.price == 111.5)
        #expect(overnight.regularClose == 110)
        #expect(overnight.observedAt == marketTime(day: 8, hour: 23, minute: 14))
        #expect(overnight.sessionStart == marketTime(day: 8, hour: 20))
        #expect(overnight.sessionEnd == marketTime(day: 9, hour: 4))
        #expect(quote.preMarket == nil && quote.postMarket == nil)
        // The regular price and its trading day stay Friday's.
        #expect(quote.regularMarketPrice == 110)
        #expect(quote.marketSession?.regularStart == marketTime(day: 6, hour: 9, minute: 30))
        #expect(!batch.didFailExtendedHours)
    }

    /// An overnight price from an earlier night isn't a trade in this one,
    /// and a post-market price is never an overnight one.
    @Test func anOldOvernightPriceIsNotATradeTonight() async throws {
        let server = FakeTradingViewServer(quotes: [
            "AAPL": FakeMarket.stockQuote(
                price: 110,
                extendedPrice: 112,
                extendedTime: marketTime(day: 6, hour: 19, minute: 50),
                overnightPrice: 99,
                overnightTime: marketTime(day: 6, hour: 3)
            )
        ])
        let client = server.client(at: marketTime(day: 8, hour: 21))

        let batch = try await client.quotes(for: [MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock)])
        let overnight = try #require(batch.quotes["AAPL"]?.overnight)

        #expect(overnight.price == 110)
        #expect(overnight.observedAt == nil)
    }

    @Test func unreadableHoursKeepTheRegularPriceAndSaySo() async throws {
        var fields = FakeMarket.stockQuote(price: 110)
        fields["subsessions"] = .null
        let server = FakeTradingViewServer(quotes: ["AAPL": fields])
        let client = server.client(at: marketTime(day: 6, hour: 17, minute: 30))

        let batch = try await client.quotes(for: [MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock)])

        #expect(batch.quotes["AAPL"]?.regularMarketPrice == 110)
        #expect(batch.quotes["AAPL"]?.marketSession == nil)
        #expect(batch.quotes["AAPL"]?.postMarket == nil)
        #expect(batch.didFailExtendedHours)
    }

    @Test func pushedChangesAreReadWithoutAskingAgain() async throws {
        let server = FakeTradingViewServer(quotes: [
            "CRYPTO:BTCUSD": FakeMarket.cryptoQuote(price: 75_000, previousClose: 74_000)
        ])
        let client = server.client(at: marketTime(day: 8, hour: 11))
        let request = [MarketQuoteRequest(symbol: "BTC", instrumentKind: .crypto)]
        _ = try await client.quotes(for: request)

        server.update("CRYPTO:BTCUSD", ["lp": .number(75_123)])

        try await eventually {
            try await client.quotes(for: request).quotes["BTC"]?.regularMarketPrice == 75_123
        }
        #expect(server.messages(named: "quote_add_symbols").count == 1)
        #expect(server.socketCount == 1)
    }

    @Test func aDroppedSocketIsReplacedAndSubscribedAgain() async throws {
        let server = FakeTradingViewServer(quotes: ["AAPL": FakeMarket.stockQuote()])
        let client = server.client(at: marketTime(day: 6, hour: 11))
        let request = [MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock)]
        _ = try await client.quotes(for: request)

        server.dropConnections()

        try await eventually {
            (try? await client.quotes(for: request).quotes["AAPL"]) != nil && server.socketCount == 2
        }
        #expect(server.messages(named: "quote_create_session").count == 2)
        #expect(server.messages(named: "quote_add_symbols").count == 2)
    }

    @Test func noNetworkIsReportedAsOffline() async throws {
        let server = FakeTradingViewServer(quotes: ["AAPL": FakeMarket.stockQuote()])
        server.setRefusesConnections(true)
        let client = server.client(at: marketTime(day: 6, hour: 11))

        do {
            _ = try await client.quotes(for: [MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock)])
            Issue.record("Expected the request to fail")
        } catch {
            #expect(RefreshFailure(error) == .offline)
        }
    }

    @Test func heartbeatsAreEchoed() async throws {
        let server = FakeTradingViewServer(quotes: ["AAPL": FakeMarket.stockQuote()])
        let client = server.client(at: marketTime(day: 6, hour: 11))
        _ = try await client.quotes(for: [MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock)])

        server.pushHeartbeat(3)

        try await eventually { server.heartbeats == ["~h~3"] }
    }
}

@Suite
struct TradingViewPriceHistoryTests {
    private let holding = makeHolding(symbol: "AAPL")

    /// Five-minute bars over the trading hours of each weekday from
    /// `firstDay` to `lastDay`, stopping at `end`.
    private func intradayBars(days: ClosedRange<Int>, until end: Date) -> [(time: Date, close: Double)] {
        days.flatMap { day -> [(time: Date, close: Double)] in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = eastern
            let weekday = calendar.component(.weekday, from: marketTime(day: day, hour: 12))
            guard (2...6).contains(weekday) else { return [] }
            return FakeMarket.bars(
                from: marketTime(day: day, hour: 4),
                to: min(marketTime(day: day, hour: 20), end),
                every: 300,
                price: { 100 + Double(day) + Double($0) / 1_000 }
            )
        }
    }

    private func dailyBars(_ closes: [(day: Int, close: Double)]) -> [(time: Date, close: Double)] {
        closes.map { (marketTime(day: $0.day, hour: 9, minute: 30), $0.close) }
    }

    private func oneDayServer(until end: Date, days: ClosedRange<Int>) -> FakeTradingViewServer {
        FakeTradingViewServer(series: [
            "AAPL@5": .init(info: FakeMarket.stockInfo(), bars: intradayBars(days: days, until: end)),
            "AAPL@1D": .init(
                info: FakeMarket.stockInfo(),
                bars: dailyBars([(4, 103), (5, 104), (6, 106.5), (9, 107)].filter { marketTime(day: $0.day, hour: 9, minute: 30) <= end })
            )
        ])
    }

    @Test func postMarketContinuesTheSessionThatEndsOnItsClose() async throws {
        let now = marketTime(day: 6, hour: 17, minute: 30)
        let client = oneDayServer(until: now, days: 5...6).client(at: now)

        let series = try await client.priceHistory(for: "AAPL", instrumentKind: .stock, currencyCode: "USD", range: .oneDay)

        let regular = series.points.filter { $0.session == .regular }
        let postMarket = series.points.filter { $0.session == .postMarket }
        #expect(regular.first?.date == marketTime(day: 6, hour: 9, minute: 30))
        #expect(regular.last == HoldingPricePoint(date: marketTime(day: 6, hour: 16), price: 106.5))
        #expect(postMarket.first?.date == marketTime(day: 6, hour: 16, minute: 5))
        #expect(postMarket.last?.date == marketTime(day: 6, hour: 17, minute: 25))
        #expect(series.baselinePrice == 104)
        #expect(series.timeDomain?.start == marketTime(day: 6, hour: 9, minute: 30))
    }

    @Test func preMarketFollowsTheLastSessionAndItsPostMarket() async throws {
        let now = marketTime(day: 9, hour: 8)
        let client = oneDayServer(until: now, days: 5...9).client(at: now)

        let series = try await client.priceHistory(for: "AAPL", instrumentKind: .stock, currencyCode: "USD", range: .oneDay)

        #expect(series.points.first?.date == marketTime(day: 6, hour: 9, minute: 30))
        #expect(series.points.filter { $0.session == .postMarket }.last?.date == marketTime(day: 6, hour: 19, minute: 55))
        let preMarket = series.points.filter { $0.session == .preMarket }
        #expect(preMarket.first?.date == marketTime(day: 9, hour: 4))
        #expect(preMarket.last?.date == marketTime(day: 9, hour: 7, minute: 55))
        #expect(series.baselinePrice == 104)
        #expect(series.timeDomain?.segments.count == 2)
    }

    @Test func cryptoShowsItsWholeUTCDay() async throws {
        let now = marketTime(day: 8, hour: 11)
        let server = FakeTradingViewServer(series: [
            "CRYPTO:BTCUSD@5": .init(
                info: FakeMarket.cryptoInfo,
                bars: FakeMarket.bars(from: marketTime(day: 7, hour: 12), to: now, every: 300)
            )
        ])

        let series = try await server.client(at: now)
            .priceHistory(for: "BTC", instrumentKind: .crypto, currencyCode: "USD", range: .oneDay)

        // Midnight UTC is 19:00 the evening before in New York.
        #expect(series.points.first?.date == marketTime(day: 7, hour: 19))
        #expect(series.timeDomain?.end.timeIntervalSince(series.timeDomain!.start) == 86_400)
    }

    @Test func yearToDateIsMeasuredFromLastYearsFinalClose() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        let start = calendar.date(from: DateComponents(year: 2025, month: 12, day: 29, hour: 9, minute: 30))!
        let bars = FakeMarket.bars(from: start, to: marketTime(day: 6, hour: 12), every: 86_400) { 50 + Double($0) }
        let server = FakeTradingViewServer(series: ["AAPL@1D": .init(info: FakeMarket.stockInfo(), bars: bars)])

        let series = try await server.client(at: marketTime(day: 6, hour: 12))
            .priceHistory(for: "AAPL", instrumentKind: .stock, currencyCode: "USD", range: .yearToDate)

        // Dec 29, 30 and 31 come before the year.
        #expect(series.baselinePrice == 52)
        #expect(series.points.first?.price == 53)
        #expect(series.points.allSatisfy { calendar.component(.year, from: $0.date) == 2026 })
    }

    @Test func fiveDaysKeepsTheLastFiveTradingDates() async throws {
        let bars = (28...31).flatMap { day -> [(time: Date, close: Double)] in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = eastern
            let open = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 9, minute: 30))!
            return FakeMarket.bars(from: open, to: open.addingTimeInterval(6.5 * 3_600), every: 900)
        } + (2...6).flatMap { day in
            FakeMarket.bars(from: marketTime(day: day, hour: 9, minute: 30), to: marketTime(day: day, hour: 16), every: 900)
        }
        let server = FakeTradingViewServer(series: ["AAPL@15": .init(info: FakeMarket.stockInfo(), bars: bars)])

        let series = try await server.client(at: marketTime(day: 7, hour: 12))
            .priceHistory(for: "AAPL", instrumentKind: .stock, currencyCode: "USD", range: .fiveDays)

        #expect(series.points.first?.date == marketTime(day: 2, hour: 9, minute: 30))
        #expect(series.points.count == 5 * 26)
    }

    @Test func theFirstTradeDateComesFromTheQuote() async throws {
        let now = marketTime(day: 6, hour: 22)
        let server = FakeTradingViewServer(
            quotes: ["AAPL": FakeMarket.stockQuote()],
            series: [
                "AAPL@1M": .init(
                    info: FakeMarket.stockInfo(),
                    bars: [(marketTime(day: 2, hour: 9, minute: 30), 100), (marketTime(day: 3, hour: 9, minute: 30), 101)]
                )
            ]
        )
        let client = server.client(at: now)
        _ = try await client.quotes(for: [MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock)])

        let series = try await client.priceHistory(for: "AAPL", instrumentKind: .stock, currencyCode: "USD", range: .max)

        #expect(series.firstTradeDate == Date(timeIntervalSince1970: 454_896_000))
    }

    @Test func aChartInAnotherCurrencyIsRefused() async throws {
        let server = FakeTradingViewServer(series: [
            "VOD@1M": .init(info: FakeMarket.stockInfo(currency: "GBX"), bars: [(marketTime(day: 2, hour: 9), 70)])
        ])

        await #expect(throws: TradingViewError.currencyMismatch(symbol: "VOD", expected: "GBP", actual: "GBX")) {
            try await server.client(at: marketTime(day: 6, hour: 12))
                .priceHistory(for: "VOD", instrumentKind: .stock, currencyCode: "GBP", range: .max)
        }
    }

    @Test func anUnknownSymbolFailsAndLeavesTheSocketOpen() async throws {
        let server = FakeTradingViewServer(quotes: ["AAPL": FakeMarket.stockQuote()])
        let client = server.client(at: marketTime(day: 6, hour: 12))

        await #expect(throws: TradingViewError.invalidSymbol(symbol: "NOPE", reason: "invalid symbol")) {
            try await client.priceHistory(for: "NOPE", instrumentKind: .stock, currencyCode: "USD", range: .max)
        }
        _ = try await client.quotes(for: [MarketQuoteRequest(symbol: "AAPL", instrumentKind: .stock)])
        #expect(server.socketCount == 1)
    }
}
