//
//  UserFacingError.swift
//  Bittern
//

import Foundation

enum UserFacingError {
    static func message(for error: Error, fallback: String) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection. Check your network and try again."
            case .timedOut:
                return "The request timed out. Check your connection and try again."
            default:
                return "The network request failed. Check your connection and try again."
            }
        }

        guard !(error is SnapTradeError), !(error is YahooFinanceError) else {
            return fallback
        }
        let description = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty, description.count <= 180 else {
            return fallback
        }
        return description
    }
}
