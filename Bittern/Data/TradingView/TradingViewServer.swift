//
//  TradingViewServer.swift
//  Bittern
//
//  Where the TradingView connection goes: TradingView itself, or a server
//  of the user's that forwards TradingView's chart WebSocket, such as a
//  Cloudflare Worker on their own domain.
//

import Foundation

nonisolated struct TradingViewServer: Equatable, Sendable {
    static let tradingView = TradingViewServer(validatedHost: "data.tradingview.com")

    /// The host, with a port when it isn't the default.
    let host: String

    private init(validatedHost host: String) {
        self.host = host
    }

    /// The server named by `text`: a host such as `data.example.com`, with
    /// or without a port, or a whole address pasted from elsewhere
    /// (`wss://data.example.com/socket.io/websocket?…`), of which only the
    /// host is kept. Nil when `text` names no usable host.
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let address = trimmed.contains("://") ? trimmed : "wss://" + trimmed
        guard let components = URLComponents(string: address),
              ["wss", "https", "ws", "http"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              host.contains("."),
              components.user == nil,
              components.password == nil
        else {
            return nil
        }
        self.host = components.port.map { "\(host):\($0)" } ?? host
        guard socketURL != nil else { return nil }
    }

    var isTradingView: Bool {
        self == .tradingView
    }

    /// The chart WebSocket on this server. A forwarding server serves it at
    /// TradingView's own path.
    var socketURL: URL? {
        URL(string: "wss://\(host)/socket.io/websocket?from=chart%2F&type=chart")
    }
}

/// The server the user chose, kept in UserDefaults. Nothing kept means
/// TradingView itself.
nonisolated final class TradingViewServerStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var server: TradingViewServer {
        defaults.string(forKey: AppSettingKey.marketDataServer).flatMap(TradingViewServer.init) ?? .tradingView
    }

    func save(_ server: TradingViewServer) {
        if server.isTradingView {
            defaults.removeObject(forKey: AppSettingKey.marketDataServer)
        } else {
            defaults.set(server.host, forKey: AppSettingKey.marketDataServer)
        }
    }
}

/// What a test of a server found: it answered with a live quote.
nonisolated struct TradingViewServerCheck: Equatable, Sendable {
    let server: TradingViewServer
    let duration: Duration
    let symbol: String
    let price: Double
    let currencyCode: String?
    /// TradingView streams the quote as it trades, rather than delayed.
    let isRealTime: Bool
}
