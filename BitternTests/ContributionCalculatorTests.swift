import Foundation
import Testing
@testable import Bittern

@Suite
struct ContributionCalculatorTests {
    private typealias Input = ContributionCalculator.ElectedHoldingInput

    private func input(
        _ id: String,
        value: Double,
        price: Double,
        target: Double,
        wholeShares: Bool = true,
        currency: String = "USD"
    ) -> Input {
        Input(
            id: id,
            marketValue: value,
            price: price,
            usesWholeShares: wholeShares,
            targetPercent: target,
            currencyCode: currency
        )
    }

    @Test func refusesToPoolHoldingsInDifferentCurrencies() {
        #expect(
            ContributionCalculator.calculate(
                elected: [
                    input("A", value: 100, price: 10, target: 50, currency: "USD"),
                    input("B", value: 100, price: 10, target: 50, currency: "CAD")
                ],
                contributionAmount: 100
            ) == nil
        )
    }

    @Test func splitsAmountByTargetsOfThePool() throws {
        let outcome = try #require(
            ContributionCalculator.calculate(
                elected: [
                    input("A", value: 600, price: 10, target: 50),
                    input("B", value: 200, price: 10, target: 50)
                ],
                contributionAmount: 200
            )
        )

        // Pool 1000 → targets 500/500 → A is over target, so Gap Allocation
        // gives the whole amount to B.
        #expect(outcome.usedGapAllocation)
        #expect(outcome.holdings[0].buyAmount == 0)
        #expect(outcome.holdings[0].shareOrder == 0)
        #expect(outcome.holdings[1].buyAmount == 200)
        #expect(outcome.holdings[1].shareOrder == 20)
        #expect(outcome.residualCash == 0)
    }

    @Test func tokenHoldingsSpendTheirBuyAmountExactly() throws {
        let outcome = try #require(
            ContributionCalculator.calculate(
                elected: [input("BTC", value: 0, price: 70_000, target: 100, wholeShares: false)],
                contributionAmount: 123.45
            )
        )

        #expect(outcome.holdings[0].shareOrder == nil)
        #expect(outcome.holdings[0].actualSpend == 123.45)
        #expect(outcome.residualCash == 0)
    }

    @Test func unaffordableShareBecomesResidualCash() throws {
        let outcome = try #require(
            ContributionCalculator.calculate(
                elected: [input("A", value: 0, price: 500, target: 100)],
                contributionAmount: 100
            )
        )

        #expect(outcome.holdings[0].shareOrder == 0)
        #expect(outcome.investedAmount == 0)
        #expect(outcome.residualCash == 100)
    }

    @Test(arguments: [
        (0.0, 100.0), (-5.0, 100.0)
    ])
    func rejectsNonPositiveAmounts(amount: Double, target: Double) {
        #expect(
            ContributionCalculator.calculate(
                elected: [input("A", value: 0, price: 10, target: target)],
                contributionAmount: amount
            ) == nil
        )
    }

    @Test func rejectsTargetsThatDoNotTotal100() {
        #expect(
            ContributionCalculator.calculate(
                elected: [
                    input("A", value: 0, price: 10, target: 50),
                    input("B", value: 0, price: 10, target: 49)
                ],
                contributionAmount: 100
            ) == nil
        )
    }

    @Test func rejectsUnusablePrices() {
        #expect(
            ContributionCalculator.calculate(
                elected: [input("A", value: 0, price: 0, target: 100)],
                contributionAmount: 100
            ) == nil
        )
    }

    /// Random portfolios small enough to enumerate: the search must never
    /// overspend, never buy a zero-Buy-Amount holding, and match the optimum.
    @Test func matchesBruteForceOnSmallPortfolios() throws {
        var generator = SeededGenerator(seed: 20_261_106)

        for _ in 0..<300 {
            let count = Int.random(in: 1...3, using: &generator)
            let cuts = (0..<(count - 1))
                .map { _ in Double(Int.random(in: 0...100, using: &generator)) }
                .sorted()
            let bounds = [0.0] + cuts + [100.0]
            let inputs = (0..<count).map { index in
                input(
                    "H\(index)",
                    value: Double(Int.random(in: 0...2_000, using: &generator)),
                    price: Double(Int.random(in: 2_000...50_000, using: &generator)) / 100,
                    target: bounds[index + 1] - bounds[index]
                )
            }
            let amount = Double(Int.random(in: 10_00...1_500_00, using: &generator)) / 100

            guard let outcome = ContributionCalculator.calculate(
                elected: inputs,
                contributionAmount: amount
            ) else {
                // Every target is zero-gap: nothing can be allocated.
                continue
            }

            #expect(!outcome.isEstimated)
            #expect(outcome.investedAmount <= amount + 1e-6)
            #expect(outcome.residualCash >= 0)
            for holding in outcome.holdings where holding.buyAmount <= 1e-6 {
                #expect(holding.shareOrder == 0, "bought a zero-Buy-Amount holding")
            }

            let prices = inputs.map(\.price)
            let buys = outcome.holdings.map(\.buyAmount)
            let best = bruteForce(prices: prices, buys: buys, budget: amount)
            let actualCost = outcome.holdings.reduce(0) { $0 + abs($1.actualSpend - $1.buyAmount) }

            #expect(abs(actualCost - best.cost) < 1e-4, "inputs=\(inputs) amount=\(amount)")
            #expect(outcome.investedAmount >= best.spend - 1e-4, "inputs=\(inputs) amount=\(amount)")
        }
    }

    private func bruteForce(
        prices: [Double],
        buys: [Double],
        budget: Double
    ) -> (cost: Double, spend: Double) {
        var best = (cost: Double.infinity, spend: 0.0)

        func visit(_ index: Int, remaining: Double, cost: Double, spend: Double) {
            guard index < prices.count else {
                if cost < best.cost - 1e-6
                    || (abs(cost - best.cost) <= 1e-6 && spend > best.spend) {
                    best = (min(cost, best.cost), spend)
                }
                return
            }

            // A zero-Buy-Amount holding is never bought.
            let limit = buys[index] <= 1e-6 ? 0 : Int((remaining / prices[index] + 1e-9).rounded(.down))
            for shares in 0...limit {
                let spent = Double(shares) * prices[index]
                visit(
                    index + 1,
                    remaining: remaining - spent,
                    cost: cost + abs(spent - buys[index]),
                    spend: spend + spent
                )
            }
        }

        visit(0, remaining: budget, cost: 0, spend: 0)
        return best
    }
}
