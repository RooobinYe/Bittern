//
//  TradingViewSessionCalendar.swift
//  Bittern
//
//  An exchange's trading hours as TradingView publishes them with a symbol:
//  weekly sessions in the exchange's time zone ("0930-1600"), corrections
//  for particular dates ("0930-1300:20261127;dayoff:20250109") and a list of
//  holidays. From these it lays out the trading day around any instant, and
//  the overnight session after it.
//

import Foundation

struct TradingViewSessionCalendar {
    let timeZone: TimeZone
    /// The asset trades every minute of every day, as crypto does.
    let tradesAroundTheClock: Bool
    private let regular: SessionRule
    private let extended: SessionRule?
    /// Overnight hours, keyed by the trading day they lead into: a session
    /// of `2000-0400` on Monday runs from Sunday 20:00 to Monday 04:00.
    private let night: SessionRule?
    private let holidays: Set<Int>
    private let calendar: Calendar

    /// - Parameters:
    ///   - timeZone: The exchange's time zone identifier.
    ///   - subsessions: TradingView's `subsessions`: objects with an `id`,
    ///     a `session` and an optional `session-correction`. The `regular`
    ///     one is required; `extended`, when present, spans pre-market to
    ///     post-market, and `night`, when present, is the overnight session.
    ///   - holidays: Comma-separated `yyyyMMdd` dates.
    init(timeZone: String?, subsessions: JSONValue?, holidays: String?) throws {
        guard let identifier = timeZone, let zone = TimeZone(identifier: identifier) else {
            throw TradingViewError.invalidChartData("Missing exchange time zone.")
        }
        let byID = Dictionary(
            (subsessions?.array ?? []).compactMap { item -> (String, JSONValue)? in
                item["id"]?.string.map { ($0, item) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard let regularSession = byID["regular"]?["session"]?.string else {
            throw TradingViewError.invalidChartData("Missing regular trading hours.")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        self.calendar = calendar
        self.timeZone = zone
        tradesAroundTheClock = regularSession == "24x7"

        if tradesAroundTheClock {
            regular = SessionRule(weekly: [:], corrections: [:])
            extended = nil
            night = nil
            self.holidays = []
            return
        }

        regular = try SessionRule(
            session: regularSession,
            correction: byID["regular"]?["session-correction"]?.string
        )
        extended = try byID["extended"]?["session"]?.string.map {
            try SessionRule(session: $0, correction: byID["extended"]?["session-correction"]?.string)
        }
        night = try byID["night"]?["session"]?.string.map {
            try SessionRule(session: $0, correction: byID["night"]?["session-correction"]?.string)
        }
        self.holidays = try Set(
            (holidays ?? "")
                .split(separator: ",")
                .map { try Self.dateNumber(String($0)) }
        )
    }

    // MARK: - Trading days

    /// The trading day of the exchange-local date `day`, or nil when the
    /// exchange is closed all day.
    func tradingDay(on day: DateComponents) -> HoldingMarketSession? {
        guard !tradesAroundTheClock,
              let year = day.year, let month = day.month, let dayOfMonth = day.day,
              let midnight = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))
        else {
            return nil
        }
        let number = year * 10_000 + month * 100 + dayOfMonth
        let weekday = calendar.component(.weekday, from: midnight)
        let isHoliday = holidays.contains(number)

        guard let regularSpan = regular.span(on: number, weekday: weekday, isHoliday: isHoliday),
              let regularStart = date(minutes: regularSpan.start, on: midnight),
              let regularEnd = date(minutes: regularSpan.end, on: midnight)
        else {
            return nil
        }

        var start = regularStart
        var end = regularEnd
        if let extendedSpan = extended?.span(on: number, weekday: weekday, isHoliday: isHoliday),
           let extendedStart = date(minutes: extendedSpan.start, on: midnight),
           let extendedEnd = date(minutes: extendedSpan.end, on: midnight) {
            start = min(start, extendedStart)
            end = max(end, extendedEnd)
        }
        return HoldingMarketSession(start: start, regularStart: regularStart, regularEnd: regularEnd, end: end)
    }

    /// Every trading day whose exchange-local date falls from `start`
    /// through `end`, in order.
    func tradingDays(from start: Date, through end: Date) -> [HoldingMarketSession] {
        var days: [HoldingMarketSession] = []
        var date = calendar.startOfDay(for: start)
        // Bounded: a decade of dates.
        for _ in 0..<3_700 where date <= end {
            if let day = tradingDay(on: calendar.dateComponents([.year, .month, .day], from: date)) {
                days.append(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return days
    }

    /// The trading day under way at `now`, or else the latest one that has
    /// started: after the close it stays the day that just ended until the
    /// next one begins. It carries the overnight session that follows it.
    func latestTradingDay(startedBy now: Date) -> HoldingMarketSession? {
        guard let from = calendar.date(byAdding: .day, value: -14, to: now),
              let through = calendar.date(byAdding: .day, value: 1, to: now),
              var day = tradingDays(from: from, through: through).last(where: { $0.start <= now })
        else {
            return nil
        }
        day.overnight = overnight(after: day)
        return day
    }

    /// The overnight session between `day` and the next trading day: the
    /// next trading day's night hours, when it has some and they begin no
    /// earlier than `day` ends.
    func overnight(after day: HoldingMarketSession) -> DateInterval? {
        guard let night,
              let from = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day.regularStart)),
              let through = calendar.date(byAdding: .day, value: 14, to: from),
              let next = tradingDays(from: from, through: through).first
        else {
            return nil
        }
        let midnight = calendar.startOfDay(for: next.regularStart)
        let number = dateNumber(of: midnight)
        guard let span = night.span(
                  on: number,
                  weekday: calendar.component(.weekday, from: midnight),
                  isHoliday: holidays.contains(number)
              ),
              let start = date(minutes: span.start, on: midnight),
              let end = date(minutes: span.end, on: midnight),
              start >= day.end
        else {
            return nil
        }
        let clampedEnd = min(end, next.start)
        guard start < clampedEnd else { return nil }
        return DateInterval(start: start, end: clampedEnd)
    }

    /// When a regular-session price that TradingView stamps `time` traded.
    /// Out of session TradingView stamps the close with the end of the whole
    /// trading day; the price itself is the regular close, so it is moved to
    /// the session's last second, where it belongs to the last bar.
    func regularTradeTime(for time: Date) -> Date {
        guard !tradesAroundTheClock,
              let from = calendar.date(byAdding: .day, value: -14, to: time),
              let day = tradingDays(from: from, through: time).last(where: { $0.regularStart <= time }),
              time >= day.regularEnd
        else {
            return time
        }
        return day.regularEnd.addingTimeInterval(-1)
    }

    /// The regular, pre-market and post-market periods of every trading
    /// day from `start` through `end`.
    func schedule(from start: Date, through end: Date) -> ExchangeTradingSchedule {
        let days = tradingDays(from: start, through: end)
        return ExchangeTradingSchedule(
            regular: days.map { PriceChartTimeSegment(start: $0.regularStart, end: $0.regularEnd) },
            preMarket: days.filter { $0.start < $0.regularStart }
                .map { PriceChartTimeSegment(start: $0.start, end: $0.regularStart) },
            postMarket: days.filter { $0.regularEnd < $0.end }
                .map { PriceChartTimeSegment(start: $0.regularEnd, end: $0.end) },
            timeZone: timeZone
        )
    }

    /// `components` added to `date` in the exchange's time zone.
    func date(byAdding components: DateComponents, to date: Date) -> Date {
        calendar.date(byAdding: components, to: date) ?? date
    }

    /// The exchange-local start of the year `date` falls in.
    func startOfYear(containing date: Date) -> Date {
        calendar.dateInterval(of: .year, for: date)?.start ?? date
    }

    /// The exchange-local date of `date` as `yyyyMMdd`.
    func dateNumber(of date: Date) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    private func date(minutes: Int, on midnight: Date) -> Date? {
        // Minutes may be negative for a session that opens the evening
        // before; adding days and then hours keeps local wall-clock times
        // across daylight-saving changes.
        let dayOffset = Int((Double(minutes) / 1_440).rounded(.down))
        let minuteOfDay = minutes - dayOffset * 1_440
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: midnight) else { return nil }
        return calendar.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: day
        )
    }

    fileprivate static func dateNumber(_ text: String) throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 8, let number = Int(trimmed) else {
            throw TradingViewError.invalidChartData("Unreadable session date \(text).")
        }
        return number
    }
}

/// One subsession's hours: by weekday, overridden on corrected dates.
private struct SessionRule {
    /// Minutes from the local midnight of the trading day. A start before
    /// zero opens the evening before.
    struct Span {
        let start: Int
        let end: Int
    }

    /// Weekday (1 is Sunday) to the day's span.
    let weekly: [Int: Span]
    /// `yyyyMMdd` to the day's span, or nil for a day off.
    let corrections: [Int: Span?]

    init(weekly: [Int: Span], corrections: [Int: Span?]) {
        self.weekly = weekly
        self.corrections = corrections
    }

    /// Parses `0930-1600`, `0930-1130,1230-1500:23456` or several such
    /// separated by `|`. Without days the session runs Monday to Friday.
    /// Several ranges in a day become one span from the first open to the
    /// last close.
    init(session: String, correction: String?) throws {
        var weekly: [Int: Span] = [:]
        for part in session.split(separator: "|") {
            let pieces = part.split(separator: ":", maxSplits: 1)
            let span = try Self.span(String(pieces[0]))
            let days = pieces.count > 1 ? String(pieces[1]) : "23456"
            for character in days {
                guard let weekday = character.wholeNumberValue, (1...7).contains(weekday) else {
                    throw TradingViewError.invalidChartData("Unreadable session days \(days).")
                }
                weekly[weekday] = span
            }
        }

        var corrections: [Int: Span?] = [:]
        for group in (correction ?? "").split(separator: ";") {
            let pieces = group.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2 else {
                throw TradingViewError.invalidChartData("Unreadable session correction \(group).")
            }
            let span = pieces[0] == "dayoff" ? nil : try Self.span(String(pieces[0]))
            for date in pieces[1].split(separator: ",") {
                corrections[try TradingViewSessionCalendar.dateNumber(String(date))] = span
            }
        }
        self.init(weekly: weekly, corrections: corrections)
    }

    func span(on date: Int, weekday: Int, isHoliday: Bool) -> Span? {
        if let correction = corrections[date] {
            return correction
        }
        return isHoliday ? nil : weekly[weekday]
    }

    private static func span(_ text: String) throws -> Span {
        let ranges = try text.split(separator: ",").map { range -> Span in
            let ends = range.split(separator: "-")
            guard ends.count == 2,
                  let start = minutes(ends[0]),
                  let end = minutes(ends[1])
            else {
                throw TradingViewError.invalidChartData("Unreadable session \(text).")
            }
            // A range that ends at or before its start opened the day before.
            return Span(start: end <= start ? start - 1_440 : start, end: end)
        }
        guard let first = ranges.first, let last = ranges.last else {
            throw TradingViewError.invalidChartData("Empty session.")
        }
        return Span(start: first.start, end: last.end)
    }

    private static func minutes(_ text: Substring) -> Int? {
        guard text.count == 4, let value = Int(text) else { return nil }
        let hours = value / 100
        let minutes = value % 100
        guard (0...24).contains(hours), (0..<60).contains(minutes) else { return nil }
        return hours * 60 + minutes
    }
}
