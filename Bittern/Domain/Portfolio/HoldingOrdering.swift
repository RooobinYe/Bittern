//
//  HoldingOrdering.swift
//  Bittern
//

import Foundation

enum PerformanceMode: String, CaseIterable, Identifiable, Sendable {
    case today
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            "Today"
        case .allTime:
            "All-time"
        }
    }
}

enum HoldingSortOption: String, CaseIterable, Identifiable, Sendable {
    case gainAmount
    case lossAmount
    case percent
    case marketValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gainAmount:
            "Gain"
        case .lossAmount:
            "Loss"
        case .percent:
            "Percent"
        case .marketValue:
            "Value"
        }
    }

    /// Orders holdings for the holdings list. Holdings whose sort value is
    /// unknown go last rather than reading as zero.
    func sorted(
        _ holdings: [PortfolioHolding],
        by mode: PerformanceMode
    ) -> [PortfolioHolding] {
        holdings.sorted { lhs, rhs in
            switch self {
            case .gainAmount:
                isOrdered(lhs.performanceAmount(for: mode), before: rhs.performanceAmount(for: mode), ascending: false)
            case .lossAmount:
                isOrdered(lhs.performanceAmount(for: mode), before: rhs.performanceAmount(for: mode), ascending: true)
            case .percent:
                isOrdered(lhs.performancePercent(for: mode), before: rhs.performancePercent(for: mode), ascending: false)
            case .marketValue:
                isOrdered(lhs.marketValue, before: rhs.marketValue, ascending: false)
            }
        }
    }

    private func isOrdered(_ lhs: Double?, before rhs: Double?, ascending: Bool) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            ascending ? lhs < rhs : lhs > rhs
        case (.some, nil):
            true
        case (nil, .some), (nil, nil):
            false
        }
    }
}
