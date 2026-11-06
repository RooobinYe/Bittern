//
//  SnapTradeMapping.swift
//  Bittern
//
//  Turns SnapTrade's vocabulary into the domain's.
//

import Foundation

extension SnapTradeInstrumentDTO {
    /// The instrument's kind, or nil when SnapTrade doesn't say. A kind
    /// Bittern doesn't know is `.other`, never a guess from the ticker.
    var portfolioKind: PortfolioInstrumentKind? {
        guard let value = kind?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !value.isEmpty
        else {
            return nil
        }

        switch value {
        case "stock": return .stock
        case "etf": return .etf
        case "crypto": return .crypto
        case "mutualfund": return .mutualFund
        case "adr": return .adr
        case "cef": return .closedEndFund
        case "future": return .future
        case "option": return .option
        case "cfd": return .cfd
        default: return .other
        }
    }
}

extension SnapTradeAccountBalanceHistoryDTO {
    var accountBalanceHistory: AccountBalanceHistory {
        AccountBalanceHistory(
            currencyCode: currency,
            readings: history.map {
                AccountBalanceHistory.Reading(date: $0.date, totalValue: $0.totalValue)
            }
        )
    }
}
