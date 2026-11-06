//
//  ContributionPlan.swift
//  Bittern
//

import Foundation

/// The single persisted set of holding elections and Target Percentages.
/// The Contribution Amount is never part of the plan (see CONTEXT.md).
struct ContributionPlan: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var accountID: String
        var symbol: String
        var targetPercent: Double?
    }

    var entries: [Entry] = []

    static let empty = ContributionPlan()

    private func entryIndex(accountID: String, symbol: String) -> Int? {
        entries.firstIndex { $0.accountID == accountID && $0.symbol == symbol }
    }

    func isElected(accountID: String, symbol: String) -> Bool {
        entryIndex(accountID: accountID, symbol: symbol) != nil
    }

    func targetPercent(accountID: String, symbol: String) -> Double? {
        entryIndex(accountID: accountID, symbol: symbol).flatMap { entries[$0].targetPercent }
    }

    mutating func toggleElection(accountID: String, symbol: String) {
        if let index = entryIndex(accountID: accountID, symbol: symbol) {
            entries.remove(at: index)
        } else {
            entries.append(Entry(accountID: accountID, symbol: symbol, targetPercent: nil))
        }
    }

    mutating func setTargetPercent(_ value: Double?, accountID: String, symbol: String) {
        guard let index = entryIndex(accountID: accountID, symbol: symbol) else { return }

        if let value, value.isFinite {
            entries[index].targetPercent = max(0, value)
        } else {
            entries[index].targetPercent = nil
        }
    }

    /// Drops entries whose holding no longer exists. Callers must pass the
    /// full unfiltered holding set — pruning against a threshold-filtered
    /// list would delete targets for holdings that are merely hidden.
    mutating func prune(keeping holdings: [PortfolioHolding]) {
        let keys = Set(holdings.map { "\($0.accountID)|\($0.symbol)" })
        entries.removeAll { !keys.contains("\($0.accountID)|\($0.symbol)") }
    }
}
