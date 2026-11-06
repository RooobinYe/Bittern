//
//  YahooFinanceError.swift
//  Bittern
//

import Foundation

enum YahooFinanceError: LocalizedError {
    case invalidURL
    case emptySymbols
    case invalidResponse
    case httpStatus(Int, String)
    case decodingFailed(String)
    /// Yahoo answered with its own error inside an HTTP 200 response.
    case providerError(String)
    /// The response had no chart result, or the result had no price.
    case emptyResult(symbol: String)
    /// Every requested quote failed.
    case noMarketData
    case notEnoughPoints(symbol: String)
    case invalidChartMetadata(String)
    case currencyMismatch(symbol: String, expected: String, actual: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The Yahoo service URL is invalid."
        case .emptySymbols:
            "There are no symbols to quote."
        case .invalidResponse:
            "Yahoo returned a non-HTTP response."
        case .httpStatus(let status, let body):
            "Yahoo request failed with HTTP \(status). \(body)"
        case .decodingFailed(let reason):
            "Yahoo returned an undecodable response. \(reason)"
        case .providerError(let description):
            "Yahoo returned an error. \(description)"
        case .emptyResult(let symbol):
            "Yahoo returned no chart data for \(symbol)."
        case .noMarketData:
            "Yahoo returned no market data."
        case .notEnoughPoints(let symbol):
            "Yahoo returned too few chart points for \(symbol)."
        case .invalidChartMetadata(let reason):
            "Yahoo returned invalid chart timing data. \(reason)"
        case .currencyMismatch(let symbol, let expected, let actual):
            "Yahoo quotes \(symbol) in \(actual ?? "an unknown currency"), not \(expected)."
        }
    }
}
