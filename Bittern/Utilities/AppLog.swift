//
//  AppLog.swift
//  Bittern
//

import Foundation
import OSLog

/// The single entry point for Bittern's unified logs.
///
/// Keep categories stable so logs remain easy to filter in Console.app. Values
/// interpolated into a `Logger` message are private by default; only mark a
/// value as public when it cannot identify a user or reveal portfolio data.
enum AppLog {
    private nonisolated static let subsystem =
        Bundle.main.bundleIdentifier ?? "com.robinye.Bittern"

    nonisolated static let portfolio = Logger(
        subsystem: subsystem,
        category: "Portfolio"
    )
    nonisolated static let snapTrade = Logger(
        subsystem: subsystem,
        category: "SnapTrade"
    )
    nonisolated static let marketData = Logger(
        subsystem: subsystem,
        category: "MarketData"
    )
    nonisolated static let persistence = Logger(
        subsystem: subsystem,
        category: "Persistence"
    )
    nonisolated static let credentials = Logger(
        subsystem: subsystem,
        category: "Credentials"
    )
    nonisolated static let images = Logger(
        subsystem: subsystem,
        category: "Images"
    )
    nonisolated static let sharing = Logger(
        subsystem: subsystem,
        category: "Sharing"
    )

    nonisolated static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        return "type=\(type(of: error)) domain=\(nsError.domain) code=\(nsError.code) taskCancelled=\(Task.isCancelled) message=\"\(error.localizedDescription)\""
    }

    nonisolated static func duration(since startedAt: Date) -> String {
        String(format: "%.3fs", Date().timeIntervalSince(startedAt))
    }

    nonisolated static func list(_ values: [String]) -> String {
        values.isEmpty ? "[]" : "[\(values.joined(separator: ","))]"
    }

    nonisolated static func optional<Value>(_ value: Value?) -> String {
        value.map(String.init(describing:)) ?? "nil"
    }
}
