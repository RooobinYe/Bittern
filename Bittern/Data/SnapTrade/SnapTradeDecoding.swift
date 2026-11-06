//
//  SnapTradeDecoding.swift
//  Bittern
//

import Foundation

private let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private let iso8601WithFractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let dateOnlyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

extension KeyedDecodingContainer {
    /// SnapTrade sends decimals as strings on newer endpoints and numbers on
    /// older ones. Absent or null is nil; anything else unreadable throws.
    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }

        let value: Double?
        if let number = try? decode(Double.self, forKey: key) {
            value = number
        } else if let string = try? decode(String.self, forKey: key) {
            value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            value = nil
        }

        guard let value, value.isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Expected a finite decimal number."
            )
        }
        return value
    }

    /// Absent or null is nil; a date in an unknown format throws.
    func decodeDateOnlyIfPresent(forKey key: Key) throws -> Date? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else {
            return nil
        }

        let date = dateOnlyFormatter.date(from: value)
            ?? iso8601Formatter.date(from: value)
            ?? iso8601WithFractionalFormatter.date(from: value)
        guard let date else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Unrecognized date format."
            )
        }
        return date
    }

    func decodeFlexibleNumberTextIfPresent(forKey key: Key) throws -> String? {
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }

        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = 12
            formatter.minimumFractionDigits = 0
            return formatter.string(from: NSNumber(value: doubleValue)) ?? "\(doubleValue)"
        }

        return nil
    }
}
