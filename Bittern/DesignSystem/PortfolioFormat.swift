//
//  PortfolioFormat.swift
//  Bittern
//
//  Every number and date the interface shows, formatted for the person's
//  region: their separators, currency placement and 12- or 24-hour clock.
//

import Foundation

enum PortfolioFormat {
    /// Shown wherever a value is unknown. Never a zero or an estimate.
    static let missing = "N/A"

    /// Joins pieces of secondary information on one line.
    static let separator = " · "

    static func hiddenMoney(currencyCode: String = "USD") -> String {
        currencyCode == "USD" ? "$••••" : "\(currencyCode) ••••"
    }

    static func hiddenChange(
        amount: Double,
        percent: Double,
        currencyCode: String = "USD",
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        "\(sign(of: amount))\(hiddenMoney(currencyCode: currencyCode)) (\(PortfolioFormat.percent(percent, signed: true, locale: locale)))"
    }

    /// A hidden amount that still shows which way it moved.
    static func hiddenSignedMoney(_ amount: Double, currencyCode: String = "USD") -> String {
        "\(sign(of: amount))\(hiddenMoney(currencyCode: currencyCode))"
    }

    static func money(
        _ value: Double,
        currencyCode: String = "USD",
        signed: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        currency(value, currencyCode: currencyCode, fractionDigits: 2...2, signed: signed, locale: locale)
    }

    /// Two decimals, or three below 100 where cents hide real movement.
    static func price(
        _ value: Double,
        currencyCode: String = "USD",
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        currency(
            value,
            currencyCode: currencyCode,
            fractionDigits: value >= 100 ? 2...2 : 2...3,
            signed: false,
            locale: locale
        )
    }

    /// Whole-dollar money with no decimal places.
    static func wholeMoney(
        _ value: Double,
        currencyCode: String = "USD",
        signed: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        currency(value, currencyCode: currencyCode, fractionDigits: 0...0, signed: signed, locale: locale)
    }

    static func percent(
        _ value: Double,
        signed: Bool = false,
        fractionDigits: Int = 2,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        value.formatted(
            .percent
                .precision(.fractionLength(fractionDigits))
                .sign(strategy: signed ? .always(includingZero: false) : .automatic)
                .locale(locale)
        )
    }

    /// A change in whole currency units with its percentage, such as
    /// "+$1,234 (+1.20%)", short enough for the donut's centre.
    static func change(
        _ amount: Double,
        percent: Double,
        currencyCode: String = "USD",
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        "\(wholeMoney(amount, currencyCode: currencyCode, signed: true, locale: locale)) (\(PortfolioFormat.percent(percent, signed: true, locale: locale)))"
    }

    static func shares(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let fractionDigits = value.rounded() == value ? 0...5 : 2...5
        return value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    static func tokens(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.precision(.fractionLength(0...5)).locale(locale))
    }

    static func quantity(
        _ value: Double,
        unit: HoldingQuantityUnit,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch unit {
        case .shares:
            shares(value, locale: locale)
        case .tokens:
            tokens(value, locale: locale)
        }
    }

    /// Every digit the broker reported, without grouping.
    static func preciseQuantity(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...12))
                .grouping(.never)
                .locale(locale)
        )
    }

    /// A persisted snapshot can be days old, so anything before today states
    /// its date; a bare time of day would read as just refreshed.
    static func lastUpdated(
        _ date: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(
                .dateTime.hour().minute().second()
                    .locale(locale)
            )
        }

        let style: Date.FormatStyle = calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? .dateTime.day().month(.abbreviated).hour().minute()
            : .dateTime.day().month(.abbreviated).year().hour().minute()
        return date.formatted(style.locale(locale))
    }

    /// A day, such as "7 Nov".
    static func day(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// A day with its year, such as "7 Nov 2026".
    static func dayWithYear(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    /// A day and time of day, such as "7 Nov, 14:30" or "7 Nov, 2:30 PM".
    static func dayAndTime(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
    }

    /// A time of day, such as "14:30" or "2:30 PM".
    static func time(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// A month with its year, such as "Nov 2026".
    static func monthWithYear(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(.dateTime.month(.abbreviated).year().locale(locale))
    }

    /// A year, such as "2026".
    static func year(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(.dateTime.year().locale(locale))
    }

    private static func currency(
        _ value: Double,
        currencyCode: String,
        fractionDigits: ClosedRange<Int>,
        signed: Bool,
        locale: Locale
    ) -> String {
        value.formatted(
            .currency(code: currencyCode)
                .precision(.fractionLength(fractionDigits))
                .sign(strategy: signed ? .always(showZero: false) : .automatic)
                .locale(locale)
        )
    }

    private static func sign(of amount: Double) -> String {
        amount < 0 ? "-" : amount > 0 ? "+" : ""
    }
}
