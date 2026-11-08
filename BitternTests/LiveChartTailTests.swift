import Foundation
import Testing
@testable import Bittern

@Suite
struct LiveChartTailTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func point(_ seconds: TimeInterval, _ price: Double, _ session: PriceChartSession = .regular) -> HoldingPricePoint {
        HoldingPricePoint(date: at(seconds), price: price, session: session)
    }

    private func observation(_ seconds: TimeInterval, _ price: Double, _ session: PriceChartSession = .regular) -> LivePriceObservation {
        LivePriceObservation(date: at(seconds), price: price, session: session)
    }

    private func updated(_ outcome: LiveChartTail.Outcome) -> HoldingPriceSeries? {
        guard case .updated(let series) = outcome else { return nil }
        return series
    }

    // MARK: - Bars

    @Test func everyRangeHasItsBar() {
        #expect(HoldingChartRange.oneDay.barLength == .seconds(300))
        #expect(HoldingChartRange.fiveDays.barLength == .seconds(900))
        #expect(HoldingChartRange.oneMonth.barLength == .seconds(3_600))
        #expect(HoldingChartRange.threeMonths.barLength == .calendar(.day, 1))
        #expect(HoldingChartRange.yearToDate.barLength == .calendar(.day, 1))
        #expect(HoldingChartRange.oneYear.barLength == .calendar(.day, 1))
        #expect(HoldingChartRange.fiveYears.barLength == .calendar(.weekOfYear, 1))
        #expect(HoldingChartRange.max.barLength == .calendar(.month, 1))
    }

    @Test func aTickInsideTheBarMovesOnlyTheLastPoint() throws {
        let series = HoldingPriceSeries(points: [point(0, 100), point(300, 101)], timeDomain: nil)

        let following = try #require(updated(
            LiveChartTail.applying(observation(420, 103), to: series, barLength: .seconds(300))
        ))

        #expect(following.points == [point(0, 100), point(300, 103)])
    }

    @Test func aNewBarAddsOnePointAtItsStart() throws {
        let series = HoldingPriceSeries(points: [point(0, 100), point(300, 101)], timeDomain: nil)

        var following = try #require(updated(
            LiveChartTail.applying(observation(610, 104), to: series, barLength: .seconds(300))
        ))
        #expect(following.points == [point(0, 100), point(300, 101), point(600, 104)])

        // Ticks within the new bar move it, without adding more.
        for (seconds, price) in [(650.0, 105.0), (700, 103), (899, 106)] {
            following = try #require(updated(
                LiveChartTail.applying(observation(seconds, price), to: following, barLength: .seconds(300))
            ))
        }
        #expect(following.points == [point(0, 100), point(300, 101), point(600, 106)])
    }

    @Test func aBarSkippedWhileAwayStartsWhereTheObservationFalls() throws {
        let series = HoldingPriceSeries(points: [point(0, 100)], timeDomain: nil)

        let following = try #require(updated(
            LiveChartTail.applying(observation(3_725, 110), to: series, barLength: .seconds(900))
        ))

        #expect(following.points.last == point(3_600, 110))
        #expect(following.points.count == 2)
    }

    @Test func dailyWeeklyAndMonthlyBarsCountCalendarSteps() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let januaryFirst = utc.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 14, minute: 30))!
        let midMarch = utc.date(from: DateComponents(year: 2026, month: 3, day: 17))!

        let month = ChartBarLength.calendar(.month, 1).start(ofBarContaining: midMarch, anchoredAt: januaryFirst)
        #expect(month == utc.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 14, minute: 30)))

        let day = ChartBarLength.calendar(.day, 1).start(ofBarContaining: midMarch, anchoredAt: januaryFirst)
        #expect(day == utc.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 14, minute: 30)))

        let week = ChartBarLength.calendar(.weekOfYear, 1).start(ofBarContaining: midMarch, anchoredAt: januaryFirst)
        #expect(week == utc.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 14, minute: 30)))
    }

    @Test func anOlderOrEqualObservationChangesNothing() {
        let series = HoldingPriceSeries(points: [point(0, 100), point(300, 101)], timeDomain: nil)

        #expect(LiveChartTail.applying(observation(200, 99), to: series, barLength: .seconds(300)) == .unchanged)
        #expect(LiveChartTail.applying(observation(310, 101), to: series, barLength: .seconds(300)) == .unchanged)
    }

    @Test func yahoosTrailingTradeBecomesTheCloseOfItsBar() throws {
        // 18:00 starts the bar; 18:01:53 is the latest trade inside it.
        let loaded = HoldingPriceSeries(
            points: [point(0, 100), point(300, 101), point(413, 102)],
            timeDomain: nil
        )

        var series = LiveChartTail.barInProgressLast(loaded, barLength: .seconds(300))
        #expect(series.points == [point(0, 100), point(300, 102)])

        // The next bar starts on Yahoo's boundary, not five minutes after
        // the trade.
        series = try #require(updated(
            LiveChartTail.applying(observation(605, 103), to: series, barLength: .seconds(300))
        ))
        #expect(series.points.last == point(600, 103))
    }

    @Test func aSeriesThatEndsOnABarIsLeftAlone() {
        let loaded = HoldingPriceSeries(points: [point(0, 100), point(300, 101)], timeDomain: nil)

        #expect(LiveChartTail.barInProgressLast(loaded, barLength: .seconds(300)) == loaded)
    }

    @Test func theContinuationEndsWhereItsBarStarts() {
        let loaded = HoldingPriceSeries(
            points: [point(0, 100), point(300, 101, .postMarket), point(413, 102, .postMarket)],
            timeDomain: PriceChartTimeDomain(segments: [PriceChartTimeSegment(start: at(0), end: at(413))])
        )

        let series = LiveChartTail.barInProgressLast(loaded, barLength: .seconds(300))

        #expect(series.points.last == point(300, 102, .postMarket))
        #expect(series.timeDomain?.end == at(300))
    }

    // MARK: - 1D on a time axis

    @Test func aSessionInProgressGrowsInsideItsScheduledBounds() throws {
        let domain = PriceChartTimeDomain(start: at(0), end: at(23_400))
        let series = HoldingPriceSeries(points: [point(0, 100), point(300, 101)], timeDomain: domain, baselinePrice: 99)

        let following = try #require(updated(
            LiveChartTail.applying(observation(605, 102), to: series, barLength: .seconds(300))
        ))

        #expect(following.points.last == point(600, 102))
        #expect(following.timeDomain == domain)
        #expect(following.baselinePrice == 99)
    }

    @Test func aBarPastAScheduledEndNeedsAReload() {
        let domain = PriceChartTimeDomain(start: at(0), end: at(600))
        let series = HoldingPriceSeries(points: [point(0, 100), point(300, 101)], timeDomain: domain)

        #expect(LiveChartTail.applying(observation(905, 102), to: series, barLength: .seconds(300)) == .needsReload)
    }

    @Test func theExtendedHoursContinuationGrowsWithEachNewBar() throws {
        let domain = PriceChartTimeDomain(segments: [PriceChartTimeSegment(start: at(0), end: at(1_200))])
        let series = HoldingPriceSeries(
            points: [point(0, 100), point(600, 101), point(900, 101.5, .postMarket), point(1_200, 102, .postMarket)],
            timeDomain: domain
        )

        let following = try #require(updated(
            LiveChartTail.applying(observation(1_520, 103, .postMarket), to: series, barLength: .seconds(300))
        ))

        #expect(following.points.last == point(1_500, 103, .postMarket))
        #expect(following.timeDomain?.end == at(1_500))
    }

    @Test func anotherSessionNeedsAReload() {
        let series = HoldingPriceSeries(
            points: [point(0, 100), point(300, 101)],
            timeDomain: PriceChartTimeDomain(start: at(0), end: at(600))
        )

        #expect(LiveChartTail.applying(observation(610, 102, .postMarket), to: series, barLength: .seconds(300)) == .needsReload)
    }

    // MARK: - What each range follows

    @Test func extendedHoursQuotesOnlyMoveTheOneDayContinuation() throws {
        let session = HoldingMarketSession(start: at(-19_800), regularStart: at(0), regularEnd: at(23_400), end: at(37_800))
        var holding = makeHolding(
            currentPrice: 110,
            marketSession: session,
            regularPriceTime: at(23_400)
        )
        holding = PortfolioHolding(
            id: holding.id,
            accountID: holding.accountID,
            symbol: holding.symbol,
            name: holding.name,
            instrumentKind: holding.instrumentKind,
            logoURL: nil,
            accountName: holding.accountName,
            quantity: holding.quantity,
            quantityDisplay: nil,
            averageCost: holding.averageCost,
            currentPrice: holding.currentPrice,
            previousClose: holding.previousClose,
            preMarketChange: nil,
            postMarketChange: HoldingExtendedHoursChange(
                amount: 20,
                percent: 0.018,
                observedAt: at(25_000),
                sessionStart: at(23_400),
                sessionEnd: at(37_800),
                price: 112
            ),
            currencyCode: holding.currencyCode,
            dividendsReceived: 0,
            marketSession: session,
            regularPriceTime: at(23_400)
        )
        let now = at(25_100)

        #expect(holding.liveObservation(for: .oneDay, at: now) == observation(25_000, 112, .postMarket))
        // 5D and longer follow the regular session, whose close belongs to
        // its last bar.
        let fiveDays = try #require(holding.liveObservation(for: .fiveDays, at: now))
        #expect(fiveDays.price == 110)
        #expect(fiveDays.session == .regular)
        #expect(fiveDays.date < session.regularEnd)
    }

    @Test func cryptoFollowsItsPriceInEveryRange() {
        let holding = makeHolding(symbol: "BTC", currentPrice: 75_000, instrumentKind: .crypto, regularPriceTime: at(100))

        for range in HoldingChartRange.allCases {
            #expect(holding.liveObservation(for: range, at: at(120)) == observation(100, 75_000))
        }
    }

    // MARK: - Value axis

    @Test func theValueAxisWidensOnlyWhenAPriceLeavesIt() {
        let bounds = 100.0...110.0
        let domain = PerformanceChartGeometry.valueDomain(low: 100, high: 110)

        // Inside the headroom: the axis holds still.
        #expect(PerformanceChartGeometry.valueBounds(bounds, including: 111) == bounds)
        #expect(PerformanceChartGeometry.valueBounds(bounds, including: domain.upperBound - 0.01) == bounds)

        // Past it: the axis takes the new price.
        #expect(PerformanceChartGeometry.valueBounds(bounds, including: domain.upperBound + 1) == 100...(domain.upperBound + 1))
        #expect(PerformanceChartGeometry.valueBounds(bounds, including: 90) == 90...110)
    }
}

@Suite
struct HoldingDetailModelTests {
    private final class HistoryRepository: PortfolioRepository {
        var series: HoldingPriceSeries
        var error: (any Error)?

        init(series: HoldingPriceSeries) {
            self.series = series
        }

        func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioLoadResult {
            throw URLError(.unsupportedURL)
        }

        func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioLoadResult {
            throw URLError(.unsupportedURL)
        }

        func priceHistory(for holding: PortfolioHolding, range: HoldingChartRange) async throws -> HoldingPriceSeries {
            if let error { throw error }
            return series
        }

        func portfolioHistory(credentials: SnapTradeCredentials, accountIDs: [String]) async throws -> PortfolioHistory {
            throw URLError(.unsupportedURL)
        }

        func registerUser(apiKey: SnapTradeCredentials) async throws -> SnapTradeCredentials {
            throw URLError(.unsupportedURL)
        }

        func connectionPortalURL(credentials: SnapTradeCredentials, darkMode: Bool) async throws -> URL {
            throw URLError(.unsupportedURL)
        }
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func crypto(price: Double, at seconds: TimeInterval) -> PortfolioHolding {
        makeHolding(
            symbol: "BTC",
            currentPrice: price,
            previousClose: 100,
            instrumentKind: .crypto,
            regularPriceTime: t0.addingTimeInterval(seconds)
        )
    }

    private var monthOfHours: HoldingPriceSeries {
        HoldingPriceSeries(
            points: (0..<3).map { HoldingPricePoint(date: t0.addingTimeInterval(Double($0) * 3_600), price: 100 + Double($0)) },
            timeDomain: nil
        )
    }

    @Test func aLoadedRangeFollowsTheLivePrice() async {
        let model = HoldingDetailModel()
        model.selectedRange = .oneMonth
        let repository = HistoryRepository(series: monthOfHours)
        await model.load(.oneMonth, for: crypto(price: 102, at: 7_300), using: repository, at: t0.addingTimeInterval(7_300))

        let reloads = model.follow(crypto(price: 104, at: 7_400), at: t0.addingTimeInterval(7_400))

        #expect(reloads.isEmpty)
        #expect(model.visibleSeries?.points.count == 3)
        #expect(model.visibleSeries?.points.last?.price == 104)

        _ = model.follow(crypto(price: 105, at: 10_900), at: t0.addingTimeInterval(10_900))
        #expect(model.visibleSeries?.points.count == 4)
    }

    @Test func theChartHoldsStillWhileAPointIsSelected() async throws {
        let model = HoldingDetailModel()
        model.selectedRange = .oneMonth
        let repository = HistoryRepository(series: monthOfHours)
        await model.load(.oneMonth, for: crypto(price: 102, at: 7_300), using: repository, at: t0.addingTimeInterval(7_300))
        let before = try #require(model.visibleSeries)

        model.selectedPoint = before.points[1]
        _ = model.follow(crypto(price: 130, at: 10_900), at: t0.addingTimeInterval(10_900))

        #expect(model.visibleSeries == before)

        model.selectedPoint = nil
        #expect(model.visibleSeries?.points.last?.price == 130)
        #expect(model.visibleSeries?.points.count == 4)
    }

    @Test func aRangeThatNeverLoadedWaitsForTheNetworkWithoutAMessage() async {
        let model = HoldingDetailModel()
        model.selectedRange = .oneMonth
        let repository = HistoryRepository(series: monthOfHours)
        repository.error = URLError(.notConnectedToInternet)
        let holding = crypto(price: 102, at: 7_300)

        await model.load(.oneMonth, for: holding, using: repository)

        #expect(model.isVisibleRangeUnavailableOffline)
        #expect(model.errorMessage == nil)

        repository.error = nil
        await model.load(.oneMonth, for: holding, using: repository)
        #expect(!model.isVisibleRangeUnavailableOffline)
        #expect(model.visibleSeries?.points.isEmpty == false)
    }

    @Test func offlineARangeIsntRequested() async {
        let model = HoldingDetailModel()
        model.selectedRange = .fiveYears
        let repository = HistoryRepository(series: monthOfHours)

        await model.load(.fiveYears, for: crypto(price: 102, at: 0), using: repository, isOnline: false)

        #expect(model.isVisibleRangeUnavailableOffline)
        #expect(model.visibleSeries == nil)
    }

    @Test func theAxisOfALoadedRangeCoversItsChangeBaseline() async {
        let model = HoldingDetailModel()
        model.selectedRange = .oneDay
        let series = HoldingPriceSeries(
            points: [HoldingPricePoint(date: t0, price: 120), HoldingPricePoint(date: t0.addingTimeInterval(300), price: 121)],
            timeDomain: PriceChartTimeDomain(start: t0, end: t0.addingTimeInterval(86_400))
        )
        await model.load(.oneDay, for: crypto(price: 121, at: 400), using: HistoryRepository(series: series), at: t0.addingTimeInterval(400))

        #expect(model.visibleValueBounds == 100...121)
    }
}

@Suite
struct RefreshFailureTests {
    @Test func noPathIsOffline() {
        #expect(RefreshFailure(URLError(.notConnectedToInternet)) == .offline)
        #expect(RefreshFailure(URLError(.networkConnectionLost)) == .offline)
    }

    @Test func timeoutsBusyServersAndThrottlingAreRetried() {
        #expect(RefreshFailure(URLError(.timedOut)) == .transient)
        #expect(RefreshFailure(SnapTradeError.httpStatus(503, "")) == .transient)
        #expect(RefreshFailure(YahooFinanceError.httpStatus(429, "")) == .transient)
        #expect(RefreshFailure(YahooFinanceError.noMarketData) == .transient)
    }

    @Test func refusedCredentialsNeedTheUser() {
        let rejected = RefreshFailure.needsAction(PortfolioAttention(reason: .credentialsRejected))
        #expect(RefreshFailure(SnapTradeError.httpStatus(401, "")) == rejected)
        #expect(RefreshFailure(SnapTradeError.httpStatus(403, "")) == rejected)
        #expect(RefreshFailure(SnapTradeError.httpStatus(400, "{\"code\":\"1083\"}")) == rejected)
    }

    @Test func anythingElseIsPermanent() {
        #expect(RefreshFailure(SnapTradeError.httpStatus(404, "")) == .permanent)
        #expect(RefreshFailure(SnapTradeError.decodingFailed(operation: "listAccounts", reason: "")) == .permanent)
        #expect(RefreshFailure(PortfolioDataError.unreadablePositions(count: 1, accountNames: ["A"])) == .permanent)
    }
}
