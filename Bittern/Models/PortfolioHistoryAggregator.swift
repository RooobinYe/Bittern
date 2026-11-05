//
//  PortfolioHistoryAggregator.swift
//  Bittern
//

import Foundation

enum PortfolioHistoryError: LocalizedError, Equatable {
    case noAccounts
    case emptyHistory
    case missingCurrency
    case mixedCurrencies([String])
    case invalidDataPoint

    var errorDescription: String? {
        switch self {
        case .noAccounts:
            "No connected portfolio accounts were found."
        case .emptyHistory:
            "SnapTrade did not return balance history covering these accounts on any shared date."
        case .missingCurrency:
            "SnapTrade did not say which currency this balance history is in."
        case .mixedCurrencies(let codes):
            "Account history can’t be combined across currencies (\(codes.joined(separator: ", ")))."
        case .invalidDataPoint:
            "SnapTrade returned an unreadable balance history entry."
        }
    }
}

/// Combines per-account balance histories into one portfolio value series.
/// SnapTrade documents that this data can have gaps. A date is only shown when
/// every account has a value for it, because summing the accounts that do would
/// draw a drop that never happened, and filling the gap would be an estimate.
enum PortfolioHistoryAggregator {
    struct Result: Equatable {
        let points: [PortfolioHistoryPoint]
        let currencyCode: String
    }

    static func aggregate(
        histories: [SnapTradeAccountBalanceHistoryDTO],
        calendar: Calendar = .current
    ) throws -> Result {
        guard !histories.isEmpty else { throw PortfolioHistoryError.noAccounts }

        var currencyCodes: Set<String> = []
        for history in histories {
            guard let code = history.currency?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased(),
                  !code.isEmpty
            else {
                throw PortfolioHistoryError.missingCurrency
            }
            currencyCodes.insert(code)
        }
        guard currencyCodes.count == 1, let currencyCode = currencyCodes.first else {
            throw PortfolioHistoryError.mixedCurrencies(currencyCodes.sorted())
        }

        var totalsByDay: [Date: Double] = [:]
        var accountCountByDay: [Date: Int] = [:]
        for history in histories {
            // The latest reading of a day stands for that day, so an account
            // reporting twice isn't counted twice.
            var valueByDay: [Date: (date: Date, value: Double)] = [:]
            for point in history.history {
                guard let date = point.date,
                      let value = point.totalValue,
                      value.isFinite
                else {
                    throw PortfolioHistoryError.invalidDataPoint
                }

                let day = calendar.startOfDay(for: date)
                if let existing = valueByDay[day], existing.date > date {
                    continue
                }
                valueByDay[day] = (date, value)
            }

            for (day, reading) in valueByDay {
                totalsByDay[day, default: 0] += reading.value
                accountCountByDay[day, default: 0] += 1
            }
        }

        let points = totalsByDay
            .filter { accountCountByDay[$0.key] == histories.count }
            .map { PortfolioHistoryPoint(date: $0.key, totalValue: $0.value) }
            .sorted { $0.date < $1.date }
        guard !points.isEmpty else { throw PortfolioHistoryError.emptyHistory }

        return Result(points: points, currencyCode: currencyCode)
    }
}
