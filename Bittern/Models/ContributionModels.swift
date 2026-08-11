//
//  ContributionModels.swift
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

extension ContributionPlan {
    static func load(from defaults: UserDefaults = .standard) -> ContributionPlan {
        guard let data = defaults.data(forKey: AppSettingKey.contributionPlan),
              let plan = try? JSONDecoder().decode(ContributionPlan.self, from: data)
        else {
            return .empty
        }
        return plan
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppSettingKey.contributionPlan)
    }
}

/// Pure contribution math. Terminology follows CONTEXT.md: the Contribution
/// Pool is the denominator of every Target Percentage, Buy Amounts are
/// dollar-space and never negative, Share Orders floor them to whole shares,
/// Greedy Top-Up re-deploys the post-flooring cash into extra whole shares,
/// and whatever no share price fits into is Residual Cash.
enum ContributionCalculator {
    struct ElectedHoldingInput {
        let id: String
        let marketValue: Double
        let price: Double
        /// Shares-denominated holdings floor to whole shares; token-denominated
        /// holdings (crypto) spend their Buy Amount exactly.
        let usesWholeShares: Bool
        /// 0–100 scale, as entered by the user.
        let targetPercent: Double
    }

    struct HoldingOutcome {
        let id: String
        let buyAmount: Double
        /// Whole shares to order; nil for token-denominated holdings.
        let shareOrder: Int?
        let actualSpend: Double
        /// 0–1 fraction of the elected holdings' combined post-purchase value.
        /// Residual Cash is excluded from the denominator (see CONTEXT.md).
        let postContributionPercent: Double
    }

    struct Outcome {
        let holdings: [HoldingOutcome]
        let investedAmount: Double
        let residualCash: Double
        let usedGapAllocation: Bool
    }

    /// Targets must total exactly 100%; the tolerance only absorbs binary
    /// floating-point error in sums of user-entered decimals.
    static let targetSumTolerance = 1e-6

    /// Below this many dollars an ideal buy is floating-point noise, not a
    /// genuinely unreachable target.
    private static let moneyEpsilon = 1e-6

    static func calculate(
        elected: [ElectedHoldingInput],
        contributionAmount: Double
    ) -> Outcome? {
        guard contributionAmount.isFinite,
              contributionAmount > 0,
              !elected.isEmpty
        else {
            return nil
        }

        for input in elected {
            guard input.price > 0,
                  input.price.isFinite,
                  input.marketValue >= 0,
                  input.marketValue.isFinite,
                  input.targetPercent >= 0,
                  input.targetPercent.isFinite
            else {
                return nil
            }
        }

        let targetSum = elected.reduce(0) { $0 + $1.targetPercent }
        guard abs(targetSum - 100) <= targetSumTolerance else { return nil }

        let contributionPool = elected.reduce(contributionAmount) { $0 + $1.marketValue }
        let idealBuys = elected.map { input in
            (input.targetPercent / 100) * contributionPool - input.marketValue
        }

        let usedGapAllocation = idealBuys.contains { $0 < -moneyEpsilon }
        let buyAmounts: [Double]
        if usedGapAllocation {
            let gaps = idealBuys.map { max(0, $0) }
            let totalGap = gaps.reduce(0, +)
            guard totalGap > 0 else { return nil }
            buyAmounts = gaps.map { contributionAmount * $0 / totalGap }
        } else {
            buyAmounts = idealBuys.map { max(0, $0) }
        }

        var spends: [Double] = []
        var shareOrders: [Int?] = []
        for (index, input) in elected.enumerated() {
            if input.usesWholeShares {
                // The epsilon keeps a mathematically whole number of shares
                // from flooring one share short after float division.
                let shares = Int((buyAmounts[index] / input.price + 1e-9).rounded(.down))
                shareOrders.append(shares)
                spends.append(Double(shares) * input.price)
            } else {
                shareOrders.append(nil)
                spends.append(buyAmounts[index])
            }
        }

        // Greedy Top-Up: re-deploy post-flooring cash into extra whole
        // shares, one at a time to the holding with the largest remaining
        // dollar deficit against its Buy Amount. A holding with a zero Buy
        // Amount is over target and is never topped up.
        var remaining = contributionAmount - spends.reduce(0, +)
        while true {
            var bestIndex: Int?
            var bestDeficit = -Double.infinity

            for (index, input) in elected.enumerated() {
                guard input.usesWholeShares,
                      buyAmounts[index] > moneyEpsilon,
                      input.price <= remaining + 1e-9
                else {
                    continue
                }

                let deficit = buyAmounts[index] - spends[index]
                if deficit > bestDeficit {
                    bestDeficit = deficit
                    bestIndex = index
                }
            }

            guard let bestIndex else { break }
            shareOrders[bestIndex] = (shareOrders[bestIndex] ?? 0) + 1
            spends[bestIndex] += elected[bestIndex].price
            remaining -= elected[bestIndex].price
        }

        let investedAmount = spends.reduce(0, +)
        let postTotal = elected.enumerated().reduce(0.0) { total, item in
            total + item.element.marketValue + spends[item.offset]
        }

        let outcomes = elected.enumerated().map { index, input in
            HoldingOutcome(
                id: input.id,
                buyAmount: buyAmounts[index],
                shareOrder: shareOrders[index],
                actualSpend: spends[index],
                postContributionPercent: postTotal > 0
                    ? (input.marketValue + spends[index]) / postTotal
                    : 0
            )
        }

        return Outcome(
            holdings: outcomes,
            investedAmount: investedAmount,
            residualCash: max(0, contributionAmount - investedAmount),
            usedGapAllocation: usedGapAllocation
        )
    }
}
