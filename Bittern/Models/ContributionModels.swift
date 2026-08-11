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
/// dollar-space and never negative, Optimal Share Search picks the Share
/// Orders with the least Misallocation — the dollar distance between actual
/// spends and Buy Amounts — and whatever it leaves unspent is Residual Cash.
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

        var spends = [Double](repeating: 0, count: elected.count)
        var shareOrders = [Int?](repeating: nil, count: elected.count)
        var searchIndices: [Int] = []
        var shareBudget = contributionAmount

        for (index, input) in elected.enumerated() {
            if input.usesWholeShares {
                shareOrders[index] = 0
                // A zero-Buy-Amount holding is over target and is never bought.
                if buyAmounts[index] > moneyEpsilon {
                    searchIndices.append(index)
                }
            } else {
                spends[index] = buyAmounts[index]
                shareBudget -= buyAmounts[index]
            }
        }
        shareBudget = max(0, shareBudget)

        if !searchIndices.isEmpty {
            var search = ShareSearch(
                prices: searchIndices.map { elected[$0].price },
                buyAmounts: searchIndices.map { buyAmounts[$0] },
                budget: shareBudget
            )
            let counts = search.run()
            for (slot, index) in searchIndices.enumerated() {
                shareOrders[index] = counts[slot]
                spends[index] = Double(counts[slot]) * elected[index].price
            }
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

/// Optimal Share Search: exact branch-and-bound over whole-share counts.
/// Minimizes Misallocation — Σ|spend − Buy Amount| in dollars, where a
/// shortfall dollar, an overshoot dollar, and an unspent dollar all cost the
/// same — breaking ties toward less Residual Cash. Seeded with the previous
/// greedy plan, so even a node-cap exit never returns a worse plan than
/// greedy did.
private struct ShareSearch {
    private static let moneyEpsilon = 1e-6
    /// Backstop for adversarial price patterns (e.g. a sub-dollar share
    /// price against a four-digit one). Realistic portfolios explore a few
    /// hundred nodes; hitting the cap returns the incumbent plan.
    private static let nodeCap = 200_000

    private let prices: [Double]
    private let buyAmounts: [Double]
    private let budget: Double
    /// Slots ordered by price descending so the most budget-constraining
    /// decisions branch first.
    private let order: [Int]
    /// suffixBuy[depth] = Σ Buy Amounts of order[depth...]; grounds the
    /// "money not spendable is Misallocation" lower bound.
    private let suffixBuy: [Double]

    private var bestCounts: [Int]
    private var bestCost: Double
    private var bestSpend: Double
    private var nodesVisited = 0

    init(prices: [Double], buyAmounts: [Double], budget: Double) {
        self.prices = prices
        self.buyAmounts = buyAmounts
        self.budget = budget

        let sorted = prices.indices.sorted { lhs, rhs in
            prices[lhs] == prices[rhs] ? lhs < rhs : prices[lhs] > prices[rhs]
        }
        order = sorted

        var suffix = [Double](repeating: 0, count: sorted.count + 1)
        for depth in stride(from: sorted.count - 1, through: 0, by: -1) {
            suffix[depth] = suffix[depth + 1] + buyAmounts[sorted[depth]]
        }
        suffixBuy = suffix

        let seed = Self.greedyPlan(prices: prices, buyAmounts: buyAmounts, budget: budget)
        bestCounts = seed
        bestCost = zip(seed, prices.indices).reduce(0) { total, item in
            total + abs(Double(item.0) * prices[item.1] - buyAmounts[item.1])
        }
        bestSpend = zip(seed, prices).reduce(0) { $0 + Double($1.0) * $1.1 }
    }

    mutating func run() -> [Int] {
        var counts = bestCounts
        search(depth: 0, counts: &counts, cost: 0, remaining: budget)
        return bestCounts
    }

    /// The pre-search incumbent: floor every Buy Amount, then re-deploy the
    /// leftovers one share at a time to the largest remaining deficit.
    private static func greedyPlan(prices: [Double], buyAmounts: [Double], budget: Double) -> [Int] {
        // The epsilon keeps a mathematically whole number of shares from
        // flooring one share short after float division.
        var counts = prices.indices.map { Int((buyAmounts[$0] / prices[$0] + 1e-9).rounded(.down)) }
        var remaining = budget - prices.indices.reduce(0) { $0 + Double(counts[$1]) * prices[$1] }

        while true {
            var bestIndex: Int?
            var bestDeficit = -Double.infinity
            for index in prices.indices where prices[index] <= remaining + 1e-9 {
                let deficit = buyAmounts[index] - Double(counts[index]) * prices[index]
                if deficit > bestDeficit {
                    bestDeficit = deficit
                    bestIndex = index
                }
            }
            guard let bestIndex else { break }
            counts[bestIndex] += 1
            remaining -= prices[bestIndex]
        }
        return counts
    }

    private mutating func search(depth: Int, counts: inout [Int], cost: Double, remaining: Double) {
        if nodesVisited >= Self.nodeCap { return }
        nodesVisited += 1

        if depth == order.count {
            let spend = budget - remaining
            let improved = cost < bestCost - Self.moneyEpsilon
            let tiedButFuller = abs(cost - bestCost) <= Self.moneyEpsilon
                && spend > bestSpend + Self.moneyEpsilon
            if improved || tiedButFuller {
                bestCost = min(bestCost, cost)
                bestSpend = spend
                bestCounts = counts
            }
            return
        }

        if cost + lowerBound(depth: depth, remaining: remaining) > bestCost + Self.moneyEpsilon {
            return
        }

        let slot = order[depth]
        let price = prices[slot]
        let buyAmount = buyAmounts[slot]

        let floorCount = Int((buyAmount / price + 1e-9).rounded(.down))
        let hasRemainder = buyAmount - Double(floorCount) * price > Self.moneyEpsilon
        // Anything past the first overshoot share only adds Misallocation.
        let ceilCount = hasRemainder ? floorCount + 1 : floorCount
        let maxAffordable = Int((remaining / price + 1e-9).rounded(.down))
        let upper = min(ceilCount, maxAffordable)

        let ideal = max(0, min(upper, Int((buyAmount / price).rounded())))
        var below = ideal
        var above = ideal + 1

        // Two-pointer walk outward from the ideal count visits candidates in
        // ascending own-cost order, so the first own-cost past the incumbent
        // ends the whole slot.
        while below >= 0 || above <= upper {
            let count: Int
            if below >= 0,
               above > upper || abs(Double(below) * price - buyAmount) <= abs(Double(above) * price - buyAmount) {
                count = below
                below -= 1
            } else {
                count = above
                above += 1
            }

            let ownCost = abs(Double(count) * price - buyAmount)
            if cost + ownCost > bestCost + Self.moneyEpsilon { break }

            let nextRemaining = remaining - Double(count) * price
            let unspendable = max(0, suffixBuy[depth + 1] - nextRemaining)
            if cost + ownCost + unspendable > bestCost + Self.moneyEpsilon { continue }

            counts[slot] = count
            search(depth: depth + 1, counts: &counts, cost: cost + ownCost, remaining: nextRemaining)
        }
    }

    /// Valid optimistic completion cost for order[depth...]: the larger of
    /// "Buy Amounts the remaining budget cannot cover" and the sum of each
    /// holding's best own cost if it had the whole remaining budget.
    private func lowerBound(depth: Int, remaining: Double) -> Double {
        var independentSum = 0.0
        for position in depth..<order.count {
            let slot = order[position]
            let price = prices[slot]
            let buyAmount = buyAmounts[slot]
            let maxAffordable = Int((remaining / price + 1e-9).rounded(.down))
            let floorCount = Int((buyAmount / price + 1e-9).rounded(.down))
            if maxAffordable <= floorCount {
                independentSum += max(0, buyAmount - Double(maxAffordable) * price)
            } else {
                independentSum += min(
                    max(0, buyAmount - Double(floorCount) * price),
                    Double(floorCount + 1) * price - buyAmount
                )
            }
        }
        return max(independentSum, suffixBuy[depth] - remaining)
    }
}
