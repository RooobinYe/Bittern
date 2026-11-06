//
//  PortfolioAllocation.swift
//  Bittern
//

import Foundation

/// How a portfolio's value divides between its holdings, as drawn by the
/// allocation donut.
enum PortfolioAllocation {
    /// A share of the donut: one holding, or every small holding together.
    struct Slice: Identifiable, Equatable {
        enum Kind: Equatable {
            case holding(PortfolioHolding)
            case other
        }

        let kind: Kind
        let value: Double
        /// The slice's fraction of the whole, between 0 and 1.
        let share: Double

        var id: String {
            switch kind {
            case .holding(let holding): holding.id
            case .other: "other"
            }
        }
    }

    /// Holdings with a positive value, largest first. Ties fall back to the
    /// symbol and then the id, so the order never depends on input order.
    static func ordered(_ holdings: [PortfolioHolding]) -> [PortfolioHolding] {
        holdings
            .filter { ($0.marketValue ?? 0) > 0 }
            .sorted { lhs, rhs in
                if lhs.marketValue != rhs.marketValue {
                    return (lhs.marketValue ?? 0) > (rhs.marketValue ?? 0)
                }

                if lhs.symbol != rhs.symbol {
                    return lhs.symbol < rhs.symbol
                }

                return lhs.id < rhs.id
            }
    }

    /// The donut's slices, largest first. Holdings below `minimumShare` of the
    /// total are combined into one trailing "other" slice.
    ///
    /// Callers pass holdings whose total is known: an unpriced holding has no
    /// share, and leaving it out would overstate everyone else's.
    static func slices(
        of holdings: [PortfolioHolding],
        minimumShare: Double = 0.05
    ) -> [Slice] {
        let ordered = ordered(holdings)
        let total = ordered.reduce(0) { $0 + ($1.marketValue ?? 0) }
        guard total > 0 else { return [] }

        var slices: [Slice] = []
        var otherValue = 0.0
        for holding in ordered {
            let value = holding.marketValue ?? 0
            if value >= total * minimumShare {
                slices.append(Slice(kind: .holding(holding), value: value, share: value / total))
            } else {
                otherValue += value
            }
        }

        if otherValue > 0 {
            slices.append(Slice(kind: .other, value: otherValue, share: otherValue / total))
        }
        return slices
    }
}

/// One provider's accounts and the holdings in them.
struct ProviderHoldings: Identifiable {
    let name: String
    let logoURL: URL?
    let isDisabled: Bool
    let accountCount: Int
    /// Largest first.
    let holdings: [PortfolioHolding]
    /// Nil unless every holding has a value in one shared currency.
    let totalMarketValue: Double?

    var id: String { name }

    /// Groups `holdings` by the provider of their account, largest provider
    /// first. Providers whose total is unknown go last.
    static func groups(
        accounts: [PortfolioAccount],
        holdings: [PortfolioHolding]
    ) -> [ProviderHoldings] {
        Dictionary(grouping: accounts, by: \.providerName)
            .map { name, providerAccounts in
                let accountIDs = Set(providerAccounts.map(\.id))
                let providerHoldings = holdings
                    .filter { accountIDs.contains($0.accountID) }
                    .sorted { ($0.marketValue ?? -.infinity) > ($1.marketValue ?? -.infinity) }

                return ProviderHoldings(
                    name: name,
                    logoURL: providerAccounts.compactMap(\.providerLogoURL).first,
                    isDisabled: providerAccounts.contains(where: \.isConnectionDisabled),
                    accountCount: providerAccounts.count,
                    holdings: providerHoldings,
                    totalMarketValue: PortfolioSnapshot.make(
                        accounts: providerAccounts,
                        holdings: providerHoldings,
                        lastUpdated: nil
                    ).totalMarketValue
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalMarketValue != rhs.totalMarketValue {
                    return (lhs.totalMarketValue ?? -.infinity) > (rhs.totalMarketValue ?? -.infinity)
                }
                return lhs.name < rhs.name
            }
    }
}
