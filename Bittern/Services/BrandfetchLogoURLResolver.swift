//
//  BrandfetchLogoURLResolver.swift
//  Bittern
//

import Foundation

enum BrandfetchConfiguration {
    /// Brandfetch Client IDs are publishable client-side identifiers.
    static let clientID = "1idKAz8xUOgn2MTMDXK"
}

struct BrandfetchLogoURLResolver {
    private let clientID: String?

    var isConfigured: Bool {
        clientID != nil
    }

    init(clientID: String? = nil) {
        let configuredClientID = clientID ?? BrandfetchConfiguration.clientID
        let normalizedClientID = configuredClientID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientID = normalizedClientID.isEmpty ? nil : normalizedClientID
    }

    func logoURL(for symbol: String, kind: PortfolioInstrumentKind?) -> URL? {
        guard let clientID,
              let endpoint = endpoint(for: kind)
        else {
            return nil
        }

        let normalizedSymbol = symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedSymbol.isEmpty else { return nil }

        let baseURL = URL(string: "https://cdn.brandfetch.io")!
            .appendingPathComponent(endpoint)
            .appendingPathComponent(normalizedSymbol)
            .appendingPathComponent("h")
            .appendingPathComponent("256")
            .appendingPathComponent("w")
            .appendingPathComponent("256")
            .appendingPathComponent("icon.png")
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "c", value: clientID)
        ]
        return components?.url
    }

    func redactedDescription(for url: URL?) -> String {
        guard let url else { return "nil" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        return components?.url?.absoluteString ?? "<invalid-url>"
    }

    private func endpoint(for kind: PortfolioInstrumentKind?) -> String? {
        switch kind {
        case .stock, .etf, .mutualFund, .adr, .closedEndFund:
            return "ticker"
        case .crypto:
            return "crypto"
        case .future, .option, .cfd, .other, nil:
            return nil
        }
    }
}
