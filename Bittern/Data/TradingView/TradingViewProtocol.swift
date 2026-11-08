//
//  TradingViewProtocol.swift
//  Bittern
//
//  The wire format of TradingView's chart WebSocket. Every packet holds one
//  or more frames, each `~m~<length>~m~<payload>`, where the length counts
//  UTF-16 code units. A payload is either a heartbeat (`~h~<n>`), which the
//  client must echo, or a JSON object `{"m": method, "p": params}`.
//

import Foundation

/// Any JSON value, so messages whose shape varies by method can be read
/// field by field.
nonisolated enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        object?[key]
    }
}

/// One `{"m": method, "p": params}` message.
nonisolated struct TradingViewMessage: Equatable, Sendable {
    let method: String
    let params: [JSONValue]

    /// The quote or chart session a message belongs to: its first parameter.
    var sessionID: String? {
        params.first?.string
    }
}

nonisolated enum TradingViewFrame: Equatable, Sendable {
    case heartbeat(String)
    case message(String)
}

nonisolated enum TradingViewFraming {
    private static let marker = Array("~m~".utf16)

    static func encode(_ payload: String) -> String {
        "~m~\(payload.utf16.count)~m~\(payload)"
    }

    static func encode(method: String, params: [JSONValue]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(JSONValue.object(["m": .string(method), "p": .array(params)]))
        return encode(String(decoding: data, as: UTF8.self))
    }

    /// The frames in one packet. A packet that doesn't parse whole is
    /// rejected rather than read in part.
    static func decode(_ packet: String) throws -> [TradingViewFrame] {
        let units = Array(packet.utf16)
        var frames: [TradingViewFrame] = []
        var index = 0

        func expectMarker() throws {
            guard index + marker.count <= units.count,
                  units[index..<index + marker.count].elementsEqual(marker)
            else {
                throw TradingViewError.malformedFrame
            }
            index += marker.count
        }

        while index < units.count {
            try expectMarker()
            var length = 0
            var digits = 0
            while index < units.count, (48...57).contains(units[index]), digits < 9 {
                length = length * 10 + Int(units[index] - 48)
                index += 1
                digits += 1
            }
            guard digits > 0 else { throw TradingViewError.malformedFrame }
            try expectMarker()
            guard index + length <= units.count else { throw TradingViewError.malformedFrame }

            let payload = String(decoding: units[index..<index + length], as: UTF16.self)
            index += length
            frames.append(payload.hasPrefix("~h~") ? .heartbeat(payload) : .message(payload))
        }
        return frames
    }

    /// The message a frame's payload holds, or nil for payloads that aren't
    /// method calls, such as the server's greeting.
    static func message(from payload: String) throws -> TradingViewMessage? {
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8))
        } catch {
            throw TradingViewError.malformedFrame
        }
        guard let method = value["m"]?.string else { return nil }
        return TradingViewMessage(method: method, params: value["p"]?.array ?? [])
    }
}
