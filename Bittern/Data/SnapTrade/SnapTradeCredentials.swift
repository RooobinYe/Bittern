//
//  SnapTradeCredentials.swift
//  Bittern
//

import Foundation

/// The API key identifies this app to SnapTrade; the user ID and secret
/// identify the SnapTrade user it registered for this device.
struct SnapTradeCredentials: Codable, Equatable {
    var clientId: String
    var consumerKey: String
    var userId: String
    var userSecret: String

    var isComplete: Bool {
        hasAPIKey && hasSnapTradeUser
    }

    var hasAPIKey: Bool {
        !clientId.trimmed.isEmpty
            && !consumerKey.trimmed.isEmpty
    }

    var hasSnapTradeUser: Bool {
        !userId.trimmed.isEmpty
            && !userSecret.trimmed.isEmpty
    }

    static let empty = SnapTradeCredentials(
        clientId: "",
        consumerKey: "",
        userId: "",
        userSecret: ""
    )

    /// An API key with no SnapTrade user yet.
    static func apiKey(clientId: String, consumerKey: String) -> SnapTradeCredentials {
        SnapTradeCredentials(
            clientId: clientId,
            consumerKey: consumerKey,
            userId: "",
            userSecret: ""
        ).sanitized
    }

    var sanitized: SnapTradeCredentials {
        SnapTradeCredentials(
            clientId: clientId.trimmed,
            consumerKey: consumerKey.trimmed,
            userId: userId.trimmed,
            userSecret: userSecret.trimmed
        )
    }

    /// Whether `other` carries the same API key, ignoring the user.
    func hasSameAPIKey(as other: SnapTradeCredentials) -> Bool {
        let lhs = sanitized
        let rhs = other.sanitized
        return lhs.clientId == rhs.clientId && lhs.consumerKey == rhs.consumerKey
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
