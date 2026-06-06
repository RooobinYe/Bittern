//
//  YahooFinanceClient.swift
//  Bittern
//
//  Uses Yahoo Finance v8 chart API to fetch current price and previous
//  close for daily gain/loss calculations.  The legacy v7 /quote endpoint
//  now requires authentication (returns 401) so we use the still-public
//  /v8/finance/chart endpoint instead.
//

import Foundation

struct YahooFinanceClient {
    private let session: URLSession
    private let baseURL = "https://query1.finance.yahoo.com/v8/finance/chart"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns a dictionary keyed by the **original** symbol passed in
    /// (e.g. "BTC"), regardless of what format Yahoo required internally.
    func quotes(for symbols: [String]) async throws -> [String: YahooQuoteDTO] {
        let normalized = Array(
            Set(symbols.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        )
        .filter { !$0.isEmpty }
        .sorted()

        guard !normalized.isEmpty else {
            throw NetworkServiceError.emptySymbols
        }

        // Fetch every symbol independently — the chart API accepts one
        // ticker per request.  Use TaskGroup for concurrency.
        let results = await withTaskGroup(
            of: (original: String, quote: YahooQuoteDTO?).self
        ) { group in
            for symbol in normalized {
                group.addTask {
                    let quote = await fetchQuote(for: symbol)
                    return (symbol, quote)
                }
            }

            var dict: [String: YahooQuoteDTO] = [:]
            for await (original, quote) in group {
                if let quote {
                    dict[original] = quote
                }
            }
            return dict
        }

        return results
    }

    // MARK: - Private

    /// Try the symbol as-is (works for stocks), then with "-USD" appended
    /// (required for crypto).  The returned DTO carries the ORIGINAL symbol
    /// so callers can look up by the ticker they already have.
    private func fetchQuote(for rawSymbol: String) async -> YahooQuoteDTO? {
        let upper = rawSymbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Yahoo needs "BTC-USD" for crypto but plain "AAPL" for stocks.
        // Plain "BTC" resolves to a different (wrong) security, so we
        // cannot simply fall back.  Try -USD first for short all-letter
        // symbols (likely crypto), otherwise use the ticker as-is.
        let isLikelyCrypto = upper.count <= 5
            && upper.allSatisfy(\.isLetter)
            && !upper.contains("-")

        let candidates = isLikelyCrypto
            ? ["\(upper)-USD", upper]
            : [upper]

        for candidate in candidates {
            if let quote = try? await fetchOne(candidate: candidate) {
                // Always report back with the original ticker
                return YahooQuoteDTO(
                    symbol: upper,
                    shortName: quote.shortName,
                    longName: quote.longName,
                    currency: quote.currency,
                    regularMarketPrice: quote.regularMarketPrice,
                    regularMarketPreviousClose: quote.regularMarketPreviousClose,
                    regularMarketChange: quote.regularMarketChange,
                    regularMarketChangePercent: quote.regularMarketChangePercent
                )
            }
        }

        return nil
    }

    private func fetchOne(candidate symbol: String) async throws -> YahooQuoteDTO {
        var components = URLComponents(string: "\(baseURL)/\(symbol)")
        components?.queryItems = [
            URLQueryItem(name: "interval", value: "1d"),
            URLQueryItem(name: "range", value: "2d"),
            URLQueryItem(name: "includePrePost", value: "false"),
        ]

        guard let url = components?.url else {
            throw NetworkServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode) {
            throw NetworkServiceError.httpStatus(httpResponse.statusCode, "")
        }

        let decoded = try JSONDecoder().decode(YahooChartResponseDTO.self, from: data)

        // The chart wrapper may carry an error even on HTTP 200
        if let chartError = decoded.chart.error {
            throw NetworkServiceError.httpStatus(-1, chartError.description ?? "Yahoo chart error")
        }

        guard let result = decoded.chart.result?.first,
              let meta = result.meta,
              let currentPrice = meta.regularMarketPrice
        else {
            throw NetworkServiceError.httpStatus(-1, "Empty chart result for \(symbol)")
        }

        // previousClose is not reliably present in meta; compute it from
        // the daily close array (second-to-last value = previous session).
        let closes = result.indicators?.quote?.first?.close?.compactMap({ $0 }) ?? []
        let previousClose: Double
        if closes.count >= 2 {
            previousClose = closes[closes.count - 2]
        } else {
            previousClose = currentPrice
        }

        let change = currentPrice - previousClose
        let changePercent = previousClose != 0 ? change / previousClose : 0

        return YahooQuoteDTO(
            symbol: symbol,
            shortName: meta.shortName,
            longName: meta.longName,
            currency: meta.currency,
            regularMarketPrice: currentPrice,
            regularMarketPreviousClose: previousClose,
            regularMarketChange: change,
            regularMarketChangePercent: changePercent
        )
    }
}

// MARK: - v8 Chart API DTOs

private struct YahooChartResponseDTO: Decodable {
    let chart: YahooChartDTO
}

private struct YahooChartDTO: Decodable {
    let result: [YahooChartResultDTO]?
    let error: YahooChartErrorDTO?
}

private struct YahooChartErrorDTO: Decodable {
    let code: String?
    let description: String?
}

private struct YahooChartResultDTO: Decodable {
    let meta: YahooChartMetaDTO?
    let indicators: YahooChartIndicatorsDTO?
}

private struct YahooChartMetaDTO: Decodable {
    let currency: String?
    let symbol: String?
    let regularMarketPrice: Double?
    let shortName: String?
    let longName: String?
}

private struct YahooChartIndicatorsDTO: Decodable {
    let quote: [YahooChartQuoteDTO]?
}

private struct YahooChartQuoteDTO: Decodable {
    let close: [Double?]?
    let low: [Double?]?
    let open: [Double?]?
    let high: [Double?]?
}

// MARK: - Public result (unchanged signature)

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
