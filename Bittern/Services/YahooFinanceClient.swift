//
//  YahooFinanceClient.swift
//  Bittern
//

import Foundation

struct YahooFinanceClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func quotes(for symbols: [String]) async throws -> [String: YahooQuoteDTO] {
        let normalizedSymbols = Array(
            Set(symbols.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        )
        .filter { !$0.isEmpty }
        .sorted()

        guard !normalizedSymbols.isEmpty else {
            throw NetworkServiceError.emptySymbols
        }

        var components = URLComponents(string: "https://query1.finance.yahoo.com/v7/finance/quote")
        components?.queryItems = [
            URLQueryItem(name: "symbols", value: normalizedSymbols.joined(separator: ","))
        ]

        guard let url = components?.url else {
            throw NetworkServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NetworkServiceError.httpStatus(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(YahooQuoteEnvelopeDTO.self, from: data)
        return Dictionary(
            uniqueKeysWithValues: decoded.quoteResponse.result.map {
                ($0.symbol.uppercased(), $0)
            }
        )
    }
}

struct YahooQuoteEnvelopeDTO: Decodable {
    let quoteResponse: YahooQuoteResponseDTO
}

struct YahooQuoteResponseDTO: Decodable {
    let result: [YahooQuoteDTO]
}

struct YahooQuoteDTO: Decodable {
    let symbol: String
    let shortName: String?
    let longName: String?
    let currency: String?
    let regularMarketPrice: Double?
    let regularMarketPreviousClose: Double?
    let regularMarketChange: Double?
    let regularMarketChangePercent: Double?

    var displayName: String? {
        shortName ?? longName
    }
}
