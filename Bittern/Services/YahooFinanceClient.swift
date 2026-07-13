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
import OSLog

struct YahooQuoteRequest: Sendable {
    let symbol: String
    let instrumentKind: PortfolioInstrumentKind?
}

enum YahooFinanceError: LocalizedError {
    case invalidURL
    case emptySymbols
    case invalidResponse
    case httpStatus(Int, String)

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
        }
    }
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
            throw YahooFinanceError.emptySymbols
        }

        AppLog.marketData.debug(
            "Quotes requested inputCount=\(requests.count, privacy: .public) uniqueCount=\(normalizedRequests.count, privacy: .public) assets=\(logAssets(normalizedRequests)) taskCancelled=\(Task.isCancelled, privacy: .public)"
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
        AppLog.marketData.debug(
            "Quotes completed succeeded=\(succeeded.count, privacy: .public)/\(normalizedRequests.count, privacy: .public) succeededSymbols=\(AppLog.list(succeeded)) failedSymbols=\(AppLog.list(failed)) taskCancelled=\(Task.isCancelled, privacy: .public)"
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
            throw YahooFinanceError.emptySymbols
        }

        AppLog.marketData.debug(
            "Price history requested symbol=\(symbol) instrumentKind=\(logKind(instrumentKind), privacy: .public) range=\(range.title, privacy: .public) candidates=\(AppLog.list(candidates))"
        )

        for candidate in candidates {
            do {
                let history = try await fetchHistoryOne(candidate: candidate, range: range)
                if !history.isEmpty {
                    AppLog.marketData.debug(
                        "Price history candidate=\(candidate) returned points=\(history.count, privacy: .public)"
                    )
                    return history
                }
                AppLog.marketData.warning(
                    "Price history candidate=\(candidate) returned no points"
                )
            } catch {
                AppLog.marketData.warning(
                    "Price history candidate=\(candidate) failed: \(AppLog.describe(error))"
                )
            }
        }

        AppLog.marketData.error(
            "Price history failed for every candidate symbol=\(symbol)"
        )
        throw YahooFinanceError.httpStatus(-1, "Empty chart result for \(symbol)")
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

        AppLog.marketData.debug(
            "Quote symbol=\(upper) instrumentKind=\(logKind(request.instrumentKind), privacy: .public) candidates=\(AppLog.list(candidates)) started"
        )

        for candidate in candidates {
            do {
                let quote = try await fetchOne(candidate: candidate)
                AppLog.marketData.debug(
                    "Quote symbol=\(upper) candidate=\(candidate) succeeded price=\(AppLog.optional(quote.regularMarketPrice)) previousClose=\(AppLog.optional(quote.regularMarketPreviousClose)) currency=\(quote.currency ?? "nil")"
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
                AppLog.marketData.warning(
                    "Quote symbol=\(upper) candidate=\(candidate) failed: \(AppLog.describe(error))"
                )
            }
        }

        AppLog.marketData.warning(
            "Quote symbol=\(upper) failed allCandidates=\(AppLog.list(candidates))"
        )
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
            throw YahooFinanceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await send(
            request,
            operation: "quote candidate=\(symbol)"
        )

        let decoded: YahooChartResponseDTO
        do {
            decoded = try JSONDecoder().decode(YahooChartResponseDTO.self, from: data)
        } catch {
            AppLog.marketData.error(
                "HTTP quote candidate=\(symbol) decode failed: \(AppLog.describe(error)) body=\(responseBodyPreview(data))"
            )
            throw error
        }

        // The chart wrapper may carry an error even on HTTP 200
        if let chartError = decoded.chart.error {
            AppLog.marketData.error(
                "HTTP quote candidate=\(symbol) provider error code=\(chartError.code ?? "nil") description=\(chartError.description ?? "nil")"
            )
            throw YahooFinanceError.httpStatus(-1, chartError.description ?? "Yahoo chart error")
        }

        guard let result = decoded.chart.result?.first,
              let meta = result.meta,
              let currentPrice = meta.regularMarketPrice
        else {
            AppLog.marketData.error(
                "HTTP quote candidate=\(symbol) is missing regularMarketPrice or chart result"
            )
            throw YahooFinanceError.httpStatus(-1, "Empty chart result for \(symbol)")
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

    private func responseBodyPreview(_ data: Data) -> String {
        guard !data.isEmpty else { return "<empty>" }

        let preview = String(decoding: data.prefix(400), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? "<empty>" : "\"\(preview)\""
    }

    private func send(_ request: URLRequest, operation: String) async throws -> Data {
        let startedAt = Date()
        AppLog.marketData.debug(
            "HTTP \(operation) started url=\(request.url?.absoluteString ?? "nil")"
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLog.marketData.error(
                    "HTTP \(operation) returned a non-HTTP response bytes=\(data.count, privacy: .public) duration=\(AppLog.duration(since: startedAt), privacy: .public)"
                )
                throw YahooFinanceError.invalidResponse
            }

            let responseSummary = responseSummary(
                httpResponse,
                byteCount: data.count,
                startedAt: startedAt
            )
            guard (200..<300).contains(httpResponse.statusCode) else {
                let bodyPreview = responseBodyPreview(data)
                AppLog.marketData.error(
                    "HTTP \(operation) failed \(responseSummary, privacy: .public) body=\(bodyPreview)"
                )
                throw YahooFinanceError.httpStatus(
                    httpResponse.statusCode,
                    bodyPreview
                )
            }

            AppLog.marketData.debug(
                "HTTP \(operation) succeeded \(responseSummary, privacy: .public)"
            )
            return data
        } catch let error as YahooFinanceError {
            throw error
        } catch {
            AppLog.marketData.error(
                "HTTP \(operation) transport failed: \(AppLog.describe(error)) duration=\(AppLog.duration(since: startedAt), privacy: .public)"
            )
            throw error
        }
    }

    private func responseSummary(
        _ response: HTTPURLResponse,
        byteCount: Int,
        startedAt: Date
    ) -> String {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")
            ?? "nil"
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
            ?? "nil"
        return "status=\(response.statusCode) bytes=\(byteCount) contentType=\(contentType) retryAfter=\(retryAfter) duration=\(AppLog.duration(since: startedAt))"
    }

    private func logAssets(_ requests: [YahooQuoteRequest]) -> String {
        let values = requests.map {
            "\($0.symbol):\(logKind($0.instrumentKind))"
        }
        return AppLog.list(values)
    }

    private func logKind(_ instrumentKind: PortfolioInstrumentKind?) -> String {
        instrumentKind?.rawValue ?? "unknown"
    }

    private func normalizedSymbol(_ symbol: String) -> String {
        symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
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
            throw YahooFinanceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await send(
            request,
            operation: "price-history candidate=\(symbol) range=\(range.title)"
        )

        let decoded = try JSONDecoder().decode(YahooChartResponseDTO.self, from: data)

        if let chartError = decoded.chart.error {
            throw YahooFinanceError.httpStatus(-1, chartError.description ?? "Yahoo chart error")
        }

        guard let result = decoded.chart.result?.first,
              let timestamps = result.timestamp,
              let closes = result.indicators?.quote?.first?.close
        else {
            throw YahooFinanceError.httpStatus(-1, "Empty chart result for \(symbol)")
        }

        let points = zip(timestamps, closes).compactMap { timestamp, close -> HoldingPricePoint? in
            guard let close, close > 0 else { return nil }
            return HoldingPricePoint(
                date: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                price: close
            )
        }

        guard points.count >= 2 else {
            throw YahooFinanceError.httpStatus(-1, "Not enough chart points for \(symbol)")
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
