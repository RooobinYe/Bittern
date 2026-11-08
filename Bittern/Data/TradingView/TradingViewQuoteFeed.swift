//
//  TradingViewQuoteFeed.swift
//  Bittern
//
//  A quote session that stays open: TradingView pushes every change to the
//  symbols it holds, and a request for quotes reads the latest values
//  instead of asking the network again. Values only come from the socket
//  that is open now; when it fails, they are dropped with it.
//

import Foundation
import OSLog

/// What the feed knows about one symbol.
nonisolated enum TradingViewQuoteState: Sendable {
    /// Every field TradingView has sent for the symbol so far.
    case ready([String: JSONValue])
    case failed(String)
    /// No complete quote arrived in time.
    case pending
}

actor TradingViewQuoteFeed {
    static let fields = [
        "lp", "lp_time", "prev_close_price", "currency_code", "update_mode",
        "rtc", "rtc_time", "current_session", "timezone", "subsessions",
        "session_holidays", "first_bar_time_1d", "pro_name", "type"
    ]

    private let connection: TradingViewConnection
    private let clock = ContinuousClock()
    private var generation: UInt64?
    private var sessionID = ""
    private var starting: Task<Void, any Error>?
    private var subscribed: Set<String> = []
    private var fieldsBySymbol: [String: [String: JSONValue]] = [:]
    private var completed: Set<String> = []
    private var errors: [String: String] = [:]
    private var failure: (any Error)?

    init(connection: TradingViewConnection) {
        self.connection = connection
    }

    /// The current state of each symbol, waiting up to `timeout` for symbols
    /// the session hasn't completed yet. Throws when the socket can't be
    /// opened or fails while waiting.
    func quotes(
        for symbols: [String],
        timeout: Duration
    ) async throws -> [String: TradingViewQuoteState] {
        let generation = try await session()

        let added = symbols.filter { !subscribed.contains($0) }
        if !added.isEmpty {
            subscribed.formUnion(added)
            try await connection.send(
                "quote_add_symbols",
                [.string(sessionID)] + added.map(JSONValue.string),
                generation: generation
            )
        }

        let deadline = clock.now + timeout
        while true {
            guard self.generation == generation else {
                throw failure ?? TradingViewError.connectionClosed("The quote session ended.")
            }
            let unsettled = symbols.filter { !completed.contains($0) && errors[$0] == nil }
            if unsettled.isEmpty || clock.now >= deadline { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        var states: [String: TradingViewQuoteState] = [:]
        for symbol in symbols {
            if let error = errors[symbol] {
                states[symbol] = .failed(error)
            } else if completed.contains(symbol), let fields = fieldsBySymbol[symbol] {
                states[symbol] = .ready(fields)
            } else {
                states[symbol] = .pending
            }
        }
        return states
    }

    /// The fields last received for `symbol`, if the open session has them.
    func fields(for symbol: String) -> [String: JSONValue]? {
        completed.contains(symbol) ? fieldsBySymbol[symbol] : nil
    }

    /// The generation of a quote session on the open socket, starting one
    /// (and subscribing every symbol again) when the socket is new.
    private func session() async throws -> UInt64 {
        let generation = try await connection.connect()
        if self.generation == generation { return generation }
        if let starting {
            try await starting.value
            return try await session()
        }

        let task = Task { try await start(generation: generation) }
        starting = task
        defer { starting = nil }
        try await task.value
        return generation
    }

    private func start(generation: UInt64) async throws {
        let sessionID = TradingViewConnection.makeSessionID(prefix: "qs")
        let stream = await connection.messages(for: sessionID)
        self.sessionID = sessionID
        self.generation = generation
        failure = nil
        fieldsBySymbol = [:]
        completed = []
        errors = [:]
        let symbols = subscribed.sorted()
        subscribed = Set(symbols)

        Task {
            do {
                for try await message in stream {
                    apply(message, generation: generation)
                }
            } catch {
                ended(with: error, generation: generation)
            }
        }

        try await connection.send("quote_create_session", [.string(sessionID)], generation: generation)
        try await connection.send(
            "quote_set_fields",
            [.string(sessionID)] + Self.fields.map(JSONValue.string),
            generation: generation
        )
        if !symbols.isEmpty {
            try await connection.send(
                "quote_add_symbols",
                [.string(sessionID)] + symbols.map(JSONValue.string),
                generation: generation
            )
        }
        AppLog.marketData.debug(
            "TradingView quote session started generation=\(generation, privacy: .public) symbols=\(symbols.count, privacy: .public)"
        )
    }

    private func apply(_ message: TradingViewMessage, generation: UInt64) {
        guard generation == self.generation else { return }
        switch message.method {
        case "qsd":
            guard let data = message.params[safe: 1], let symbol = data["n"]?.string else { return }
            if data["s"]?.string == "ok" {
                fieldsBySymbol[symbol, default: [:]].merge(data["v"]?.object ?? [:]) { $1 }
            } else {
                let reason = data["errmsg"]?.string ?? data["s"]?.string ?? "unknown error"
                errors[symbol] = reason
                AppLog.marketData.warning("TradingView quote symbol=\(symbol) failed: \(reason)")
            }
        case "quote_completed":
            if let symbol = message.params[safe: 1]?.string {
                completed.insert(symbol)
            }
        case "critical_error":
            let reason = message.params.dropFirst().compactMap(\.string).joined(separator: " ")
            ended(with: TradingViewError.providerError(reason), generation: generation)
        default:
            break
        }
    }

    private func ended(with error: any Error, generation: UInt64) {
        guard generation == self.generation else { return }
        AppLog.marketData.warning("TradingView quote session ended: \(AppLog.describe(error))")
        self.generation = nil
        failure = error
        fieldsBySymbol = [:]
        completed = []
        errors = [:]
    }
}
