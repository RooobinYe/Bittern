//
//  PortfolioAccount.swift
//  Bittern
//

import Foundation

struct PortfolioAccount: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let institutionName: String
    let providerLogoURL: URL?
    let isConnectionDisabled: Bool
    /// The balance's currency, which SnapTrade may omit. Holdings carry their
    /// own currency, so this never decides how a holding is valued.
    let currencyCode: String?

    var providerName: String {
        let institution = institutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !institution.isEmpty {
            return institution
        }

        let accountName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return accountName.isEmpty ? "Account" : accountName
    }
}

extension Array where Element == PortfolioAccount {
    /// Each provider once, in the order its first account appears.
    var providerNames: [String] {
        var seen: Set<String> = []
        return compactMap { seen.insert($0.providerName).inserted ? $0.providerName : nil }
    }
}
