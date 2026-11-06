//
//  PortfolioHistory.swift
//  Bittern
//

import Foundation

struct PortfolioHistoryPoint: Identifiable, Hashable {
    let date: Date
    let totalValue: Double

    var id: TimeInterval {
        date.timeIntervalSince1970
    }
}

/// The portfolio's combined value over time, in one currency.
struct PortfolioHistory: Equatable {
    /// Oldest first.
    let points: [PortfolioHistoryPoint]
    let currencyCode: String
}

/// One account's balance readings as the broker reported them. A reading
/// without a date or value is kept so the aggregator can refuse it rather
/// than quietly skip it.
struct AccountBalanceHistory: Equatable {
    struct Reading: Equatable {
        let date: Date?
        let totalValue: Double?
    }

    let currencyCode: String?
    let readings: [Reading]
}

enum PortfolioHistoryRange: String, CaseIterable, Identifiable {
    case fiveDays = "5D"
    case threeMonths = "3M"
    case oneYear = "1Y"
    case yearToDate = "YTD"

    var id: String { rawValue }

    var title: String { rawValue }

    /// The points inside this range, counted back from the latest point
    /// rather than from today, so a history that stops early still shows.
    func points(
        in points: [PortfolioHistoryPoint],
        calendar: Calendar = .current
    ) -> [PortfolioHistoryPoint] {
        guard let latestDate = points.last?.date else { return [] }

        let startDate: Date?
        switch self {
        case .fiveDays:
            startDate = calendar.date(byAdding: .day, value: -5, to: latestDate)
        case .threeMonths:
            startDate = calendar.date(byAdding: .month, value: -3, to: latestDate)
        case .oneYear:
            startDate = calendar.date(byAdding: .year, value: -1, to: latestDate)
        case .yearToDate:
            startDate = calendar.dateInterval(of: .year, for: latestDate)?.start
        }

        guard let startDate else { return points }
        return points.filter { $0.date >= startDate }
    }
}
