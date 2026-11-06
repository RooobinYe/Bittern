//
//  PortfolioSnapshot.swift
//  Bittern
//

import Foundation

struct PortfolioSnapshot: nonisolated Codable, Sendable {
    let accounts: [PortfolioAccount]
    let holdings: [PortfolioHolding]
    let totalMarketValue: Double?
    let dayGainAmount: Double?
    let dayGainPercent: Double?
    let allTimeGainAmount: Double?
    let allTimeGainPercent: Double?
    /// The currency of the totals. Meaningless while `hasMixedCurrencies`, when
    /// every total is nil, and a placeholder when there are no holdings.
    let currencyCode: String
    let hasMixedCurrencies: Bool
    /// When every holding last had a price; nil if that has never been true.
    let lastUpdated: Date?

    /// Totals are nil unless every holding contributes to them in one shared
    /// currency: Bittern never converts, so there is no honest sum otherwise
    /// (docs/adr/0002-single-currency-portfolio.md).
    static func make(
        accounts: [PortfolioAccount],
        holdings: [PortfolioHolding],
        lastUpdated: Date? = Date()
    ) -> PortfolioSnapshot {
        let currencyCodes = Set(holdings.map(\.currencyCode))
        let hasMixedCurrencies = currencyCodes.count > 1

        func total(_ value: (PortfolioHolding) -> Double?) -> Double? {
            guard !holdings.isEmpty, !hasMixedCurrencies else { return nil }
            var sum = 0.0
            for holding in holdings {
                guard let amount = value(holding) else { return nil }
                sum += amount
            }
            return sum
        }

        func ratio(_ amount: Double?, of base: Double?) -> Double? {
            guard let amount, let base, base != 0 else { return nil }
            return amount / abs(base)
        }

        let totalMarketValue = total(\.marketValue)
        let dayGainAmount = totalMarketValue == nil ? nil : total(\.dayGainAmount)
        let previousMarketValue = totalMarketValue.flatMap { value in
            dayGainAmount.map { value - $0 }
        }
        let totalCostBasis = total(\.costBasis)
        let allTimeGainAmount = totalCostBasis == nil ? nil : total(\.totalReturnAmount)

        return PortfolioSnapshot(
            accounts: accounts,
            holdings: holdings,
            totalMarketValue: totalMarketValue,
            dayGainAmount: dayGainAmount,
            dayGainPercent: ratio(dayGainAmount, of: previousMarketValue),
            allTimeGainAmount: allTimeGainAmount,
            allTimeGainPercent: ratio(allTimeGainAmount, of: totalCostBasis),
            currencyCode: holdings.first?.currencyCode ?? "USD",
            hasMixedCurrencies: hasMixedCurrencies,
            lastUpdated: lastUpdated
        )
    }

    /// Symbols of holdings that have no usable price.
    var unpricedSymbols: [String] {
        Array(Set(holdings.filter { $0.currentPrice == nil }.map(\.symbol))).sorted()
    }

    /// The same inputs with totals recomputed by today's rules. Used on data
    /// persisted by an earlier version.
    func recomputed() -> PortfolioSnapshot {
        .make(accounts: accounts, holdings: holdings, lastUpdated: lastUpdated)
    }

    /// A partial refresh has no `lastUpdated` of its own, so it keeps showing
    /// when the prices were last complete.
    func inheritingLastUpdated(from previous: PortfolioSnapshot?) -> PortfolioSnapshot {
        guard lastUpdated == nil, let previous else { return self }
        return .make(
            accounts: accounts,
            holdings: holdings,
            lastUpdated: previous.lastUpdated
        )
    }

    /// Only the accounts at one provider, with totals recomputed. A provider
    /// with no accounts here leaves the snapshot whole rather than empty.
    func filtered(toProvider providerName: String?) -> PortfolioSnapshot {
        guard let providerName else { return self }

        let providerAccounts = accounts.filter { $0.providerName == providerName }
        guard !providerAccounts.isEmpty else { return self }

        let accountIDs = Set(providerAccounts.map(\.id))
        return .make(
            accounts: providerAccounts,
            holdings: holdings.filter { accountIDs.contains($0.accountID) },
            lastUpdated: lastUpdated
        )
    }

    /// Without the holdings worth less than `minimumMarketValue`, with totals
    /// recomputed. An unpriced holding has no known value, so it stays.
    func filtered(minimumMarketValue: Double) -> PortfolioSnapshot {
        let kept = holdings.filter { $0.meetsMinimumMarketValue(minimumMarketValue) }
        guard kept.count != holdings.count else { return self }
        return .make(accounts: accounts, holdings: kept, lastUpdated: lastUpdated)
    }

    func performanceAmount(for mode: PerformanceMode) -> Double? {
        switch mode {
        case .today:
            dayGainAmount
        case .allTime:
            allTimeGainAmount
        }
    }

    func performancePercent(for mode: PerformanceMode) -> Double? {
        switch mode {
        case .today:
            dayGainPercent
        case .allTime:
            allTimeGainPercent
        }
    }

    /// A holding's share of this snapshot's total, when both are known.
    func allocation(of holding: PortfolioHolding) -> Double? {
        guard let marketValue = holding.marketValue,
              let totalMarketValue,
              totalMarketValue > 0
        else {
            return nil
        }
        return marketValue / totalMarketValue
    }
}

extension PortfolioHolding {
    func meetsMinimumMarketValue(_ minimum: Double) -> Bool {
        marketValue.map { $0 >= minimum } ?? true
    }
}
