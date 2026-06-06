//
//  PortfolioFormat.swift
//  Bittern
//

import Foundation

enum PortfolioFormat {
    static func money(
        _ value: Double,
        currencyCode: String = "USD",
        signed: Bool = false,
        compact: Bool = false
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = compact ? .currencyAccounting : .currency
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.currencyCode = currencyCode
        if currencyCode == "USD" {
            formatter.currencySymbol = "$"
        }
        formatter.maximumFractionDigits = compact && abs(value) >= 10_000 ? 0 : 2
        formatter.minimumFractionDigits = compact && abs(value) >= 10_000 ? 0 : 2

        let rendered = formatter.string(from: NSNumber(value: abs(value))) ?? "\(currencyCode) \(abs(value))"

        guard signed else {
            return value < 0 ? "-\(rendered)" : rendered
        }

        if value > 0 {
            return "+\(rendered)"
        }

        if value < 0 {
            return "-\(rendered)"
        }

        return rendered
    }

    static func price(_ value: Double, currencyCode: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.currencyCode = currencyCode
        if currencyCode == "USD" {
            formatter.currencySymbol = "$"
        }
        formatter.maximumFractionDigits = value >= 100 ? 2 : 3
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(currencyCode) \(value)"
    }

    static func percent(_ value: Double, signed: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        let rendered = formatter.string(from: NSNumber(value: abs(value))) ?? "\(abs(value) * 100)%"

        guard signed else {
            return value < 0 ? "-\(rendered)" : rendered
        }

        if value > 0 {
            return "+\(rendered)"
        }

        if value < 0 {
            return "-\(rendered)"
        }

        return rendered
    }

    static func shares(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
