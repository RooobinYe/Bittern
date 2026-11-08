import Foundation
@testable import Bittern

/// A scripted TradingView chart server. Quote sessions get every field in
/// `quotes` for symbols it knows and an error for the rest; chart sessions
/// get the series keyed `"<symbol>@<resolution>"`.
nonisolated final class FakeTradingViewServer: @unchecked Sendable {
    struct Series {
        var info: [String: JSONValue]
        var bars: [(time: Date, close: Double)]
    }

    private let lock = NSLock()
    private var quotes: [String: [String: JSONValue]]
    private var series: [String: Series]
    private var sockets: [FakeTradingViewSocket] = []
    private var sent: [TradingViewMessage] = []
    private var sentHeartbeats: [String] = []
    private var refusesConnections = false
    private var connectedHosts: [String] = []
    /// Where the client under test keeps its chosen server; private to
    /// this server, so tests don't share it.
    let serverStore = TradingViewServerStore(defaults: UserDefaults(suiteName: "FakeTradingView-\(UUID().uuidString)")!)

    init(quotes: [String: [String: JSONValue]] = [:], series: [String: Series] = [:]) {
        self.quotes = quotes
        self.series = series
    }

    var makeSocket: TradingViewClient.SocketFactory {
        { [self] server in
            try lock.withLock {
                connectedHosts.append(server.host)
                if refusesConnections { throw URLError(.notConnectedToInternet) }
                let socket = FakeTradingViewSocket(server: self)
                sockets.append(socket)
                return socket
            }
        }
    }

    @MainActor func client(at date: Date) -> TradingViewClient {
        TradingViewClient(serverStore: serverStore, makeSocket: makeSocket, currentDate: { date })
    }

    var socketCount: Int { lock.withLock { sockets.count } }
    /// The host of every socket opened, in order.
    var hosts: [String] { lock.withLock { connectedHosts } }
    var messages: [TradingViewMessage] { lock.withLock { sent } }
    var heartbeats: [String] { lock.withLock { sentHeartbeats } }

    func messages(named method: String) -> [TradingViewMessage] {
        messages.filter { $0.method == method }
    }

    /// Changes a symbol's fields and pushes the change to every open quote
    /// session, as TradingView does.
    func update(_ symbol: String, _ fields: [String: JSONValue]) {
        let (targets, sessions) = lock.withLock {
            quotes[symbol, default: [:]].merge(fields) { $1 }
            return (sockets.filter { !$0.isClosed }, sent.filter { $0.method == "quote_create_session" })
        }
        for socket in targets {
            for session in sessions {
                socket.push("qsd", [session.params[0], .object(["n": .string(symbol), "s": .string("ok"), "v": .object(fields)])])
            }
        }
    }

    /// Fails the open socket, as a dropped network would.
    func dropConnections() {
        for socket in lock.withLock({ sockets }) {
            socket.fail(URLError(.networkConnectionLost))
        }
    }

    func setRefusesConnections(_ refuses: Bool) {
        lock.withLock { refusesConnections = refuses }
    }

    func pushHeartbeat(_ number: Int) {
        lock.withLock { sockets.last }?.pushPacket(TradingViewFraming.encode("~h~\(number)"))
    }

    fileprivate func received(_ packet: String, on socket: FakeTradingViewSocket) {
        guard let frames = try? TradingViewFraming.decode(packet) else { return }
        for frame in frames {
            switch frame {
            case .heartbeat(let payload):
                lock.withLock { sentHeartbeats.append(payload) }
            case .message(let payload):
                guard let message = try? TradingViewFraming.message(from: payload) else { continue }
                lock.withLock { sent.append(message) }
                respond(to: message, on: socket)
            }
        }
    }

    private func respond(to message: TradingViewMessage, on socket: FakeTradingViewSocket) {
        let params = message.params
        switch message.method {
        case "quote_add_symbols":
            let session = params[0]
            for symbol in params.dropFirst().compactMap(\.string) {
                if let fields = lock.withLock({ quotes[symbol] }) {
                    socket.push("qsd", [session, .object(["n": .string(symbol), "s": .string("ok"), "v": .object(fields)])])
                    socket.push("quote_completed", [session, .string(symbol)])
                } else {
                    socket.push("qsd", [session, .object(["n": .string(symbol), "s": .string("error"), "errmsg": .string("no_such_symbol"), "v": .object([:])])])
                }
            }
        case "resolve_symbol":
            socket.resolved[params[1].string ?? ""] = params[2].string.flatMap { spec in
                try? JSONDecoder().decode([String: String].self, from: Data(spec.dropFirst().utf8))["symbol"]
            }
        case "create_series":
            let session = params[0]
            let seriesID = params[1]
            let symbolID = params[3].string ?? ""
            let symbol = socket.resolved[symbolID] ?? nil
            guard let symbol, let found = lock.withLock({ series["\(symbol)@\(params[4].string ?? "")"] }) else {
                socket.push("symbol_error", [session, .string(symbolID), .string("invalid symbol")])
                return
            }
            socket.push("symbol_resolved", [session, .string(symbolID), .object(found.info)])
            let bars = found.bars.enumerated().map { index, bar in
                JSONValue.object([
                    "i": .number(Double(index)),
                    "v": .array([.number(bar.time.timeIntervalSince1970), .number(bar.close), .number(bar.close), .number(bar.close), .number(bar.close), .number(0)])
                ])
            }
            socket.push("timescale_update", [session, .object([seriesID.string ?? "": .object(["s": .array(bars)])])])
            socket.push("series_completed", [session, seriesID, .string("streaming")])
        default:
            break
        }
    }
}

nonisolated final class FakeTradingViewSocket: TradingViewSocket, @unchecked Sendable {
    private let lock = NSLock()
    private unowned let server: FakeTradingViewServer
    private var pending: [String] = []
    private var waiter: CheckedContinuation<String, any Error>?
    private var closedError: (any Error)?
    /// Symbol IDs of chart sessions to the symbols they resolved.
    var resolved: [String: String?] {
        get { lock.withLock { resolvedSymbols } }
        set { lock.withLock { resolvedSymbols = newValue } }
    }
    private var resolvedSymbols: [String: String?] = [:]

    init(server: FakeTradingViewServer) {
        self.server = server
    }

    var isClosed: Bool { lock.withLock { closedError != nil } }

    func send(_ text: String) async throws {
        if let error = lock.withLock({ closedError }) { throw error }
        server.received(text, on: self)
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !pending.isEmpty {
                let packet = pending.removeFirst()
                lock.unlock()
                continuation.resume(returning: packet)
            } else if let closedError {
                lock.unlock()
                continuation.resume(throwing: closedError)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    func close() {
        fail(URLError(.cancelled))
    }

    func fail(_ error: any Error) {
        let waiter = lock.withLock {
            let waiter = self.waiter
            self.waiter = nil
            if closedError == nil { closedError = error }
            return waiter
        }
        waiter?.resume(throwing: error)
    }

    func push(_ method: String, _ params: [JSONValue]) {
        guard let packet = try? TradingViewFraming.encode(method: method, params: params) else { return }
        pushPacket(packet)
    }

    func pushPacket(_ packet: String) {
        let waiter: CheckedContinuation<String, any Error>? = lock.withLock {
            guard closedError == nil else { return nil }
            if let waiter = self.waiter {
                self.waiter = nil
                return waiter
            }
            pending.append(packet)
            return nil
        }
        waiter?.resume(returning: packet)
    }
}

// MARK: - Market shapes

nonisolated enum FakeMarket {
    /// US stock hours as TradingView publishes them: 4:00 to 20:00 with the
    /// regular session from 9:30 to 16:00, and an early close the day after
    /// Thanksgiving.
    static let usStockSubsessions = JSONValue.array([
        .object([
            "id": .string("regular"),
            "session": .string("0930-1600"),
            "session-correction": .string("0930-1300:20261127,20261224;dayoff:20250109")
        ]),
        .object([
            "id": .string("extended"),
            "session": .string("0400-2000"),
            "session-correction": .string("0400-1700:20261127,20261224;dayoff:20250109")
        ]),
        .object(["id": .string("premarket"), "session": .string("0400-0930")]),
        .object(["id": .string("postmarket"), "session": .string("1600-2000")])
    ])
    static let usHolidays = "20261126,20261225"

    static let cryptoSubsessions = JSONValue.array([
        .object(["id": .string("regular"), "session": .string("24x7")])
    ])

    static func stockQuote(
        price: Double = 110,
        previousClose: Double = 105,
        currency: String = "USD",
        priceTime: Date = marketTime(day: 6, hour: 19, minute: 59),
        extendedPrice: Double? = nil,
        extendedTime: Date? = nil
    ) -> [String: JSONValue] {
        [
            "lp": .number(price),
            "lp_time": .number(priceTime.timeIntervalSince1970),
            "prev_close_price": .number(previousClose),
            "currency_code": .string(currency),
            "update_mode": .string("streaming"),
            "timezone": .string("America/New_York"),
            "subsessions": usStockSubsessions,
            "session_holidays": .string(usHolidays),
            "rtc": extendedPrice.map(JSONValue.number) ?? .null,
            "rtc_time": extendedTime.map { .number($0.timeIntervalSince1970) } ?? .null,
            "first_bar_time_1d": .number(454_896_000)
        ]
    }

    static func cryptoQuote(price: Double, previousClose: Double) -> [String: JSONValue] {
        [
            "lp": .number(price),
            "lp_time": .number(marketTime(day: 8, hour: 11).timeIntervalSince1970),
            "prev_close_price": .number(previousClose),
            "currency_code": .string("USD"),
            "timezone": .string("Etc/UTC"),
            "subsessions": cryptoSubsessions
        ]
    }

    static func stockInfo(currency: String = "USD") -> [String: JSONValue] {
        [
            "currency_code": .string(currency),
            "timezone": .string("America/New_York"),
            "subsessions": usStockSubsessions,
            "session_holidays": .string(usHolidays)
        ]
    }

    static let cryptoInfo: [String: JSONValue] = [
        "currency_code": .string("USD"),
        "timezone": .string("Etc/UTC"),
        "subsessions": cryptoSubsessions
    ]

    /// Bars every `step` seconds from `start` up to, not including, `end`,
    /// each closing at `price(index)`.
    static func bars(
        from start: Date,
        to end: Date,
        every step: TimeInterval,
        price: (Int) -> Double = { 100 + Double($0) / 100 }
    ) -> [(time: Date, close: Double)] {
        var bars: [(time: Date, close: Double)] = []
        var time = start
        while time < end {
            bars.append((time, price(bars.count)))
            time = time.addingTimeInterval(step)
        }
        return bars
    }
}
