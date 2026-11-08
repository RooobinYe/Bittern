//
//  TradingViewError.swift
//  Bittern
//

import Foundation

nonisolated enum TradingViewError: LocalizedError, Equatable {
    case emptySymbols
    /// A packet that isn't a sequence of well-formed frames.
    case malformedFrame
    /// The socket closed or failed while it was in use.
    case connectionClosed(String)
    /// The socket stopped delivering anything, heartbeats included.
    case connectionStalled
    /// TradingView ended the session with an error of its own.
    case providerError(String)
    case timedOut(String)
    /// Every requested quote failed.
    case noMarketData
    case invalidSymbol(symbol: String, reason: String)
    case notEnoughPoints(symbol: String)
    /// Bars or trading hours that can't be used as they are.
    case invalidChartData(String)
    case currencyMismatch(symbol: String, expected: String, actual: String?)

    var errorDescription: String? {
        switch self {
        case .emptySymbols:
            "There are no symbols to quote."
        case .malformedFrame:
            "TradingView sent a message that couldn’t be read."
        case .connectionClosed(let reason):
            "The TradingView connection closed. \(reason)"
        case .connectionStalled:
            "The TradingView connection stopped responding."
        case .providerError(let reason):
            "TradingView returned an error. \(reason)"
        case .timedOut(let operation):
            "TradingView didn’t answer in time: \(operation)."
        case .noMarketData:
            "TradingView returned no market data."
        case .invalidSymbol(let symbol, let reason):
            "TradingView doesn’t know \(symbol): \(reason)."
        case .notEnoughPoints(let symbol):
            "TradingView returned too few chart points for \(symbol)."
        case .invalidChartData(let reason):
            "TradingView returned unusable chart data. \(reason)"
        case .currencyMismatch(let symbol, let expected, let actual):
            "TradingView quotes \(symbol) in \(actual ?? "an unknown currency"), not \(expected)."
        }
    }
}
