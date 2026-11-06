//
//  ContributionSession.swift
//  Bittern
//

import Foundation

/// Everything one contribution session derives from the holdings, the
/// Contribution Plan and the Contribution Amount. Built once per change, so
/// the Optimal Share Search runs once rather than once per question asked of
/// its result.
struct ContributionSession {
    enum IncompleteReason: Equatable {
        case noElectedHoldings
        case mixedCurrencies
        case missingAmount
        case missingTargets
        case targetsNotWhole
    }

    /// The cash to prepare at one provider: the sum of its actual purchases.
    struct AccountRequirement: Identifiable, Equatable {
        let name: String
        let amount: Double

        var id: String { name }
    }

    /// Candidates for election, largest first.
    let holdings: [PortfolioHolding]
    /// Elected Holdings that can take part. An unpriced holding is never
    /// electable, and a stale election of one is void (see CONTEXT.md).
    let electedHoldings: [PortfolioHolding]
    /// The sum of the elected holdings' Target Percentages, in percent.
    let allocatedPercent: Double
    let outcome: ContributionCalculator.Outcome?
    let outcomesByHoldingID: [String: ContributionCalculator.HoldingOutcome]
    /// Providers with nothing to buy are left out. Largest first.
    let accountRequirements: [AccountRequirement]
    let incompleteReason: IncompleteReason?

    private let plan: ContributionPlan

    init(
        holdings candidates: [PortfolioHolding],
        plan: ContributionPlan,
        contributionAmount: Double?,
        providerName: (PortfolioHolding) -> String
    ) {
        self.plan = plan
        holdings = candidates.sorted { ($0.marketValue ?? 0) > ($1.marketValue ?? 0) }

        let elected = holdings.filter {
            Self.isElectable($0) && plan.isElected(accountID: $0.accountID, symbol: $0.symbol)
        }
        electedHoldings = elected

        func target(_ holding: PortfolioHolding) -> Double? {
            plan.targetPercent(accountID: holding.accountID, symbol: holding.symbol)
        }
        allocatedPercent = elected.reduce(0) { $0 + (target($1) ?? 0) }

        let outcome = Self.outcome(
            elected: elected,
            contributionAmount: contributionAmount,
            target: target
        )
        self.outcome = outcome

        let outcomes = Dictionary(
            uniqueKeysWithValues: (outcome?.holdings ?? []).map { ($0.id, $0) }
        )
        outcomesByHoldingID = outcomes

        var amounts: [String: Double] = [:]
        for holding in elected {
            guard let spend = outcomes[holding.id]?.actualSpend, spend > 0 else { continue }
            amounts[providerName(holding), default: 0] += spend
        }
        accountRequirements = amounts
            .map { AccountRequirement(name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }

        incompleteReason = outcome != nil ? nil : Self.incompleteReason(
            elected: elected,
            contributionAmount: contributionAmount,
            target: target
        )
    }

    static func isElectable(_ holding: PortfolioHolding) -> Bool {
        holding.currentPrice != nil
    }

    func isElected(_ holding: PortfolioHolding) -> Bool {
        Self.isElectable(holding)
            && plan.isElected(accountID: holding.accountID, symbol: holding.symbol)
    }

    private static func outcome(
        elected: [PortfolioHolding],
        contributionAmount: Double?,
        target: (PortfolioHolding) -> Double?
    ) -> ContributionCalculator.Outcome? {
        guard let contributionAmount, !elected.isEmpty else { return nil }

        var inputs: [ContributionCalculator.ElectedHoldingInput] = []
        for holding in elected {
            guard let price = holding.currentPrice,
                  let marketValue = holding.marketValue,
                  let targetPercent = target(holding)
            else {
                return nil
            }

            inputs.append(
                ContributionCalculator.ElectedHoldingInput(
                    id: holding.id,
                    marketValue: marketValue,
                    price: price,
                    usesWholeShares: holding.quantityUnit == .shares,
                    targetPercent: targetPercent,
                    currencyCode: holding.currencyCode
                )
            )
        }

        return ContributionCalculator.calculate(
            elected: inputs,
            contributionAmount: contributionAmount
        )
    }

    private static func incompleteReason(
        elected: [PortfolioHolding],
        contributionAmount: Double?,
        target: (PortfolioHolding) -> Double?
    ) -> IncompleteReason {
        if elected.isEmpty {
            return .noElectedHoldings
        }
        if Set(elected.map(\.currencyCode)).count > 1 {
            return .mixedCurrencies
        }
        if (contributionAmount ?? 0) <= 0 {
            return .missingAmount
        }
        if elected.contains(where: { target($0) == nil }) {
            return .missingTargets
        }
        return .targetsNotWhole
    }
}
