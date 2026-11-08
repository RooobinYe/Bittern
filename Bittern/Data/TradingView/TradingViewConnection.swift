//
//  TradingViewConnection.swift
//  Bittern
//
//  One WebSocket to TradingView, shared by the quote stream and every chart
//  request. It answers heartbeats, hands each message to the session it
//  belongs to, and opens a new socket when the last one failed or went
//  quiet.
//

import Foundation
import OSLog

/// What the connection needs from a WebSocket, so tests can stand in a
/// scripted server.
nonisolated protocol TradingViewSocket: AnyObject, Sendable {
    func send(_ text: String) async throws
    func receive() async throws -> String
    func close()
}

nonisolated final class URLSessionTradingViewSocket: TradingViewSocket {
    private let task: URLSessionWebSocketTask

    init(session: URLSession, url: URL) {
        var request = URLRequest(url: url)
        // TradingView refuses connections from any other origin; a
        // forwarding server passes it on.
        request.setValue("https://www.tradingview.com", forHTTPHeaderField: "Origin")
        task = session.webSocketTask(with: request)
        // A full price history arrives as one message.
        task.maximumMessageSize = 16 * 1024 * 1024
        task.resume()
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let text):
            return text
        case .data(let data):
            return String(decoding: data, as: UTF8.self)
        @unknown default:
            throw TradingViewError.malformedFrame
        }
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

/// A bar's start and close.
nonisolated struct TradingViewBar: Equatable, Sendable {
    let time: Date
    let close: Double
}

nonisolated struct TradingViewSeriesRequest: Sendable {
    let symbol: String
    /// "regular" or "extended".
    let session: String
    /// "5", "15", "60", "1D", "1W" or "1M".
    let resolution: String
    let barCount: Int
}

/// One series as TradingView resolved and loaded it.
nonisolated struct TradingViewSeries: Sendable {
    let symbolInfo: [String: JSONValue]
    let bars: [TradingViewBar]
}

actor TradingViewConnection {
    typealias SocketFactory = @Sendable () async throws -> any TradingViewSocket

    /// TradingView sends a heartbeat every 10 seconds; a socket silent for
    /// longer than this is treated as gone.
    static let stallLimit: Duration = .seconds(25)

    private let makeSocket: SocketFactory
    private let clock = ContinuousClock()
    private var socket: (any TradingViewSocket)?
    private var generation: UInt64 = 0
    private var opening: Task<UInt64, any Error>?
    private var lastReceived: ContinuousClock.Instant?
    private var subscribers: [String: AsyncThrowingStream<TradingViewMessage, any Error>.Continuation] = [:]

    init(makeSocket: @escaping SocketFactory) {
        self.makeSocket = makeSocket
    }

    // MARK: - Connection

    /// The generation of the open socket, opening one first if there is
    /// none. Sessions belong to one generation: when the socket fails, every
    /// session's stream ends, and a later call opens a new socket.
    func connect() async throws -> UInt64 {
        if socket != nil, let lastReceived, clock.now - lastReceived > Self.stallLimit {
            AppLog.marketData.warning("TradingView socket stalled; reconnecting")
            fail(TradingViewError.connectionStalled, generation: generation)
        }
        if socket != nil { return generation }
        if let opening { return try await opening.value }

        let task = Task { try await open() }
        opening = task
        defer { opening = nil }
        return try await task.value
    }

    private func open() async throws -> UInt64 {
        let startedAt = Date()
        let socket = try await makeSocket()
        generation &+= 1
        let generation = generation
        self.socket = socket
        lastReceived = clock.now
        Task { await self.receive(from: socket, generation: generation) }

        try await send("set_auth_token", [.string("unauthorized_user_token")], generation: generation)
        AppLog.marketData.debug(
            "TradingView socket opened generation=\(generation, privacy: .public) duration=\(AppLog.duration(since: startedAt), privacy: .public)"
        )
        return generation
    }

    /// Closes the open socket, ending every session on it, so the next
    /// request opens a new one, for example to another server.
    func disconnect() {
        fail(TradingViewError.connectionClosed("The connection was replaced."), generation: generation)
    }

    func send(_ method: String, _ params: [JSONValue], generation: UInt64) async throws {
        guard let socket, generation == self.generation else {
            throw TradingViewError.connectionClosed("The session belongs to a closed socket.")
        }
        do {
            try await socket.send(TradingViewFraming.encode(method: method, params: params))
        } catch {
            fail(error, generation: generation)
            throw Self.transportError(error)
        }
    }

    /// Messages for `sessionID` until the socket fails or the stream is
    /// dropped.
    func messages(for sessionID: String) -> AsyncThrowingStream<TradingViewMessage, any Error> {
        let (stream, continuation) = AsyncThrowingStream<TradingViewMessage, any Error>.makeStream()
        subscribers[sessionID] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(sessionID) }
        }
        return stream
    }

    private func removeSubscriber(_ sessionID: String) {
        subscribers[sessionID] = nil
    }

    private func receive(from socket: any TradingViewSocket, generation: UInt64) async {
        do {
            while true {
                let packet = try await socket.receive()
                guard generation == self.generation, self.socket != nil else { return }
                lastReceived = clock.now

                for frame in try TradingViewFraming.decode(packet) {
                    switch frame {
                    case .heartbeat(let payload):
                        try await socket.send(TradingViewFraming.encode(payload))
                    case .message(let payload):
                        guard let message = try TradingViewFraming.message(from: payload) else { continue }
                        route(message, generation: generation)
                    }
                }
            }
        } catch {
            fail(error, generation: generation)
        }
    }

    private func route(_ message: TradingViewMessage, generation: UInt64) {
        if message.method == "protocol_error" {
            let reason = message.params.first?.string ?? "Unknown protocol error."
            AppLog.marketData.error("TradingView protocol error: \(reason)")
            // A message for a session that no longer exists harms nothing
            // else on the socket.
            if !reason.contains("unknown_session_id") {
                fail(TradingViewError.providerError(reason), generation: generation)
            }
            return
        }
        guard let sessionID = message.sessionID, let subscriber = subscribers[sessionID] else { return }
        subscriber.yield(message)
    }

    /// Closes the socket of `generation` and ends every session on it.
    private func fail(_ error: any Error, generation: UInt64) {
        guard generation == self.generation, let socket else { return }
        AppLog.marketData.warning(
            "TradingView socket generation=\(generation, privacy: .public) closed: \(AppLog.describe(error))"
        )
        socket.close()
        self.socket = nil
        lastReceived = nil
        let ended = subscribers.values
        subscribers = [:]
        let reported = Self.transportError(error)
        for subscriber in ended {
            subscriber.finish(throwing: reported)
        }
    }

    /// URL errors keep their code, so the refresh logic can tell a missing
    /// network from a passing failure; anything else from the socket is a
    /// closed connection.
    private static func transportError(_ error: any Error) -> any Error {
        if error is URLError || error is TradingViewError || error is CancellationError {
            return error
        }
        return TradingViewError.connectionClosed(AppLog.describe(error))
    }

    // MARK: - Charts

    /// Loads one series in a chart session of its own: an anonymous session
    /// may hold only one series.
    func series(
        _ request: TradingViewSeriesRequest,
        timeout: Duration
    ) async throws -> TradingViewSeries {
        let generation = try await connect()
        let sessionID = Self.makeSessionID(prefix: "cs")
        let stream = messages(for: sessionID)
        var sessionIsOpen = true
        defer {
            subscribers[sessionID]?.finish()
            subscribers[sessionID] = nil
            // TradingView drops a session itself after an error in it, and
            // deleting an unknown one is a protocol error.
            if sessionIsOpen {
                Task { try? await self.send("chart_delete_session", [.string(sessionID)], generation: generation) }
            }
        }

        try await send("chart_create_session", [.string(sessionID), .string("")], generation: generation)
        try await send(
            "resolve_symbol",
            [
                .string(sessionID), .string("sym_1"),
                .string(try Self.symbolSpecification(symbol: request.symbol, session: request.session))
            ],
            generation: generation
        )
        try await send(
            "create_series",
            [
                .string(sessionID), .string("s_1"), .string("s_1"), .string("sym_1"),
                .string(request.resolution), .number(Double(request.barCount)), .string("")
            ],
            generation: generation
        )

        do {
            return try await withTimeout(timeout, operation: "chart \(request.symbol)@\(request.resolution)") {
                try await Self.collect(stream, symbol: request.symbol)
            }
        } catch let error as TradingViewError {
            if case .timedOut = error {} else { sessionIsOpen = false }
            throw error
        }
    }

    private static func collect(
        _ stream: AsyncThrowingStream<TradingViewMessage, any Error>,
        symbol: String
    ) async throws -> TradingViewSeries {
        var info: [String: JSONValue]?
        var bars: [Int: TradingViewBar] = [:]
        var completed = false

        for try await message in stream {
            let params = message.params
            switch message.method {
            case "symbol_resolved":
                info = params[safe: 2]?.object
            case "timescale_update":
                for item in params[safe: 1]?["s_1"]?["s"]?.array ?? [] {
                    guard let index = item["i"]?.number,
                          let values = item["v"]?.array,
                          let time = values[safe: 0]?.number,
                          let close = values[safe: 4]?.number
                    else {
                        throw TradingViewError.invalidChartData("A bar without a time or close.")
                    }
                    bars[Int(index)] = TradingViewBar(time: Date(timeIntervalSince1970: time), close: close)
                }
            case "series_completed":
                completed = true
            case "symbol_error":
                throw TradingViewError.invalidSymbol(
                    symbol: symbol,
                    reason: params[safe: 2]?.string ?? "unknown error"
                )
            case "series_error", "critical_error":
                let reason = params.dropFirst().compactMap(\.string).joined(separator: " ")
                throw TradingViewError.providerError("\(message.method): \(reason)")
            default:
                break
            }

            if completed, let info {
                return TradingViewSeries(
                    symbolInfo: info,
                    bars: bars.sorted { $0.key < $1.key }.map(\.value)
                )
            }
        }
        try Task.checkCancellation()
        throw TradingViewError.connectionClosed("The chart session ended early.")
    }

    // MARK: - Helpers

    static func makeSessionID(prefix: String) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        return prefix + "_" + String((0..<12).map { _ in letters.randomElement()! })
    }

    private static func symbolSpecification(symbol: String, session: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode([
            "symbol": symbol,
            "adjustment": "splits",
            "session": session
        ])
        return "=" + String(decoding: data, as: UTF8.self)
    }
}

/// Runs `body`, giving up with `TradingViewError.timedOut` after `timeout`.
nonisolated func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: String,
    _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TradingViewError.timedOut(operation)
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw CancellationError()
        }
        return result
    }
}

extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
