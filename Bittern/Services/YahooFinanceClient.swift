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

struct YahooQuoteRequest: Sendable {
    let symbol: String
    let instrumentKind: PortfolioInstrumentKind?
}

struct YahooFinanceClient {
    private let session: URLSession
    private let baseURL = "https://query1.finance.yahoo.com/v8/finance/chart"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns a dictionary keyed by the original normalized symbol (for
    /// example "BTC"), regardless of the Yahoo symbol used for the request.
    func quotes(for requests: [YahooQuoteRequest]) async throws -> [String: YahooQuoteDTO] {
        var requestsBySymbol: [String: YahooQuoteRequest] = [:]
        for request in requests {
            let symbol = normalizedSymbol(request.symbol)
            guard !symbol.isEmpty else { continue }

            if let existing = requestsBySymbol[symbol],
               existing.instrumentKind != nil,
               request.instrumentKind == nil {
                continue
            }

            requestsBySymbol[symbol] = YahooQuoteRequest(
                symbol: symbol,
                instrumentKind: request.instrumentKind
            )
        }

        let normalizedRequests = requestsBySymbol.values.sorted { $0.symbol < $1.symbol }

        guard !normalizedRequests.isEmpty else {
            throw NetworkServiceError.emptySymbols
        }

        debugLog(
            "quotes requested inputCount=\(requests.count) uniqueCount=\(normalizedRequests.count) assets=\(logAssets(normalizedRequests)) taskCancelled=\(Task.isCancelled)"
        )

        // Fetch every symbol independently — the chart API accepts one
        // ticker per request.  Use TaskGroup for concurrency.
        let results = await withTaskGroup(
            of: (original: String, quote: YahooQuoteDTO?).self
        ) { group in
            for request in normalizedRequests {
                group.addTask {
                    let quote = await fetchQuote(for: request)
                    return (request.symbol, quote)
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

        let succeeded = results.keys.sorted()
        let failed = normalizedRequests.map(\.symbol).filter { results[$0] == nil }
        debugLog(
            "quotes completed succeeded=\(succeeded.count)/\(normalizedRequests.count) succeededSymbols=\(logList(succeeded)) failedSymbols=\(logList(failed)) taskCancelled=\(Task.isCancelled)"
        )

        return results
    }

    func priceHistory(
        for symbol: String,
        instrumentKind: PortfolioInstrumentKind?,
        range: HoldingChartRange
    ) async throws -> [HoldingPricePoint] {
        let candidates = candidateSymbols(for: symbol, instrumentKind: instrumentKind)
        guard !candidates.isEmpty else {
            throw NetworkServiceError.emptySymbols
        }

        print("[YahooClient] priceHistory symbol=\(symbol) instrumentKind=\(logKind(instrumentKind)) range=\(range.title) candidates=\(candidates)")

        for candidate in candidates {
            do {
                let history = try await fetchHistoryOne(candidate: candidate, range: range)
                if !history.isEmpty {
                    print("[YahooClient] candidate \(candidate) returned \(history.count) points")
                    return history
                }
                print("[YahooClient] candidate \(candidate) returned empty history")
            } catch {
                print("[YahooClient] candidate \(candidate) failed: \(error)")
            }
        }

        print("[YahooClient] all candidates failed for \(symbol)")
        throw NetworkServiceError.httpStatus(-1, "Empty chart result for \(symbol)")
    }

    // MARK: - Private

    /// Try the symbol as-is (works for stocks), then with "-USD" appended
    /// (required for crypto).  The returned DTO carries the ORIGINAL symbol
    /// so callers can look up by the ticker they already have.
    private func fetchQuote(for request: YahooQuoteRequest) async -> YahooQuoteDTO? {
        let upper = normalizedSymbol(request.symbol)
        let candidates = candidateSymbols(
            for: request.symbol,
            instrumentKind: request.instrumentKind
        )

        debugLog(
            "quote symbol=\(upper) instrumentKind=\(logKind(request.instrumentKind)) candidates=\(logList(candidates)) started"
        )

        for candidate in candidates {
            do {
                let quote = try await fetchOne(candidate: candidate)
                debugLog(
                    "quote symbol=\(upper) candidate=\(candidate) succeeded price=\(logValue(quote.regularMarketPrice)) previousClose=\(logValue(quote.regularMarketPreviousClose)) currency=\(quote.currency ?? "nil")"
                )
                // Always report back with the original ticker
                return YahooQuoteDTO(
                    symbol: upper,
                    shortName: quote.shortName,
                    longName: quote.longName,
                    currency: quote.currency,
                    regularMarketPrice: quote.regularMarketPrice,
                    regularMarketPreviousClose: quote.regularMarketPreviousClose
                )
            } catch {
                debugLog(
                    "quote symbol=\(upper) candidate=\(candidate) failed \(debugDescription(for: error))"
                )
            }
        }

        debugLog("quote symbol=\(upper) failed allCandidates=\(logList(candidates))")
        return nil
    }

    private func candidateSymbols(
        for rawSymbol: String,
        instrumentKind: PortfolioInstrumentKind?
    ) -> [String] {
        let upper = normalizedSymbol(rawSymbol)
        guard !upper.isEmpty else { return [] }

        // Do not infer asset type from ticker length: short ETF symbols such
        // as IAUM and QQQM would be misclassified as crypto. SnapTrade's
        // instrument kind is persisted on PortfolioHolding and is the source
        // of truth here.
        guard instrumentKind == .crypto, !upper.contains("-") else {
            return [upper]
        }

        return ["\(upper)-USD"]
    }

    private func fetchOne(candidate symbol: String) async throws -> YahooQuoteDTO {
        var components = URLComponents(string: "\(baseURL)/\(symbol)")
        components?.queryItems = [
            URLQueryItem(name: "interval", value: "1d"),
            URLQueryItem(name: "range", value: "1d"),
            URLQueryItem(name: "includePrePost", value: "false"),
        ]

        guard let url = components?.url else {
            throw NetworkServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let startedAt = Date()
        debugLog("HTTP quote candidate=\(symbol) started url=\(url.absoluteString)")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            debugLog(
                "HTTP quote candidate=\(symbol) transportFailed \(debugDescription(for: error)) duration=\(durationText(since: startedAt))"
            )
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog(
                "HTTP quote candidate=\(symbol) nonHTTPResponse bytes=\(data.count) duration=\(durationText(since: startedAt))"
            )
            throw NetworkServiceError.httpStatus(-1, "Yahoo returned a non-HTTP response.")
        }

        let responseSummary = "status=\(httpResponse.statusCode) bytes=\(data.count) contentType=\(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil") retryAfter=\(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "nil") duration=\(durationText(since: startedAt))"
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let bodyPreview = responseBodyPreview(data)
            debugLog(
                "HTTP quote candidate=\(symbol) failed \(responseSummary) body=\(bodyPreview)"
            )
            throw NetworkServiceError.httpStatus(httpResponse.statusCode, bodyPreview)
        }

        debugLog("HTTP quote candidate=\(symbol) succeeded \(responseSummary)")

        let decoded: YahooChartResponseDTO
        do {
            decoded = try JSONDecoder().decode(YahooChartResponseDTO.self, from: data)
        } catch {
            debugLog(
                "HTTP quote candidate=\(symbol) decodeFailed \(debugDescription(for: error)) body=\(responseBodyPreview(data))"
            )
            throw error
        }

        // The chart wrapper may carry an error even on HTTP 200
        if let chartError = decoded.chart.error {
            debugLog(
                "HTTP quote candidate=\(symbol) yahooError code=\(chartError.code ?? "nil") description=\(chartError.description ?? "nil")"
            )
            throw NetworkServiceError.httpStatus(-1, chartError.description ?? "Yahoo chart error")
        }

        guard let result = decoded.chart.result?.first,
              let meta = result.meta,
              let currentPrice = meta.regularMarketPrice
        else {
            debugLog("HTTP quote candidate=\(symbol) missing regularMarketPrice or chart result")
            throw NetworkServiceError.httpStatus(-1, "Empty chart result for \(symbol)")
        }

        let previousClose = meta.chartPreviousClose

        return YahooQuoteDTO(
            symbol: symbol,
            shortName: meta.shortName,
            longName: meta.longName,
            currency: meta.currency,
            regularMarketPrice: currentPrice,
            regularMarketPreviousClose: previousClose
        )
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[YahooFinanceClient] \(message)")
        #endif
    }

    private func debugDescription(for error: Error) -> String {
        let nsError = error as NSError
        return "type=\(type(of: error)) domain=\(nsError.domain) code=\(nsError.code) taskCancelled=\(Task.isCancelled) message=\"\(error.localizedDescription)\""
    }

    private func durationText(since startedAt: Date) -> String {
        String(format: "%.3fs", Date().timeIntervalSince(startedAt))
    }

    private func responseBodyPreview(_ data: Data) -> String {
        guard !data.isEmpty else { return "<empty>" }

        let preview = String(decoding: data.prefix(400), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? "<empty>" : "\"\(preview)\""
    }

    private func logList(_ values: [String]) -> String {
        values.isEmpty ? "[]" : "[\(values.joined(separator: ","))]"
    }

    private func logAssets(_ requests: [YahooQuoteRequest]) -> String {
        let values = requests.map {
            "\($0.symbol):\(logKind($0.instrumentKind))"
        }
        return logList(values)
    }

    private func logKind(_ instrumentKind: PortfolioInstrumentKind?) -> String {
        instrumentKind?.rawValue ?? "unknown"
    }

    private func normalizedSymbol(_ symbol: String) -> String {
        symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func logValue(_ value: Double?) -> String {
        value.map { String($0) } ?? "nil"
    }

    private func fetchHistoryOne(candidate symbol: String, range: HoldingChartRange) async throws -> [HoldingPricePoint] {
        var components = URLComponents(string: "\(baseURL)/\(symbol)")
        components?.queryItems = [
            URLQueryItem(name: "interval", value: range.yahooInterval),
            URLQueryItem(name: "range", value: range.yahooRange),
            URLQueryItem(name: "includePrePost", value: "false"),
            URLQueryItem(name: "events", value: "history")
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

        if let chartError = decoded.chart.error {
            throw NetworkServiceError.httpStatus(-1, chartError.description ?? "Yahoo chart error")
        }

        guard let result = decoded.chart.result?.first,
              let timestamps = result.timestamp,
              let closes = result.indicators?.quote?.first?.close
        else {
            throw NetworkServiceError.httpStatus(-1, "Empty chart result for \(symbol)")
        }

        let points = zip(timestamps, closes).compactMap { timestamp, close -> HoldingPricePoint? in
            guard let close, close > 0 else { return nil }
            return HoldingPricePoint(
                date: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                price: close
            )
        }

        guard points.count >= 2 else {
            throw NetworkServiceError.httpStatus(-1, "Not enough chart points for \(symbol)")
        }

        return points
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
    let timestamp: [Int]?
    let indicators: YahooChartIndicatorsDTO?
}

private struct YahooChartMetaDTO: Decodable {
    let currency: String?
    let symbol: String?
    let regularMarketPrice: Double?
    let chartPreviousClose: Double?
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

    var fullName: String? {
        longName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var displayName: String? {
        fullName
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
