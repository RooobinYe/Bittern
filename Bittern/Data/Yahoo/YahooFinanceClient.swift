//
//  YahooFinanceClient.swift
//  Bittern
//
//  Uses Yahoo Finance's v8 chart API for quotes and price history. The
//  legacy v7 /quote endpoint now requires authentication (returns 401), so
//  every request goes to the still-public /v8/finance/chart endpoint.
//

import Foundation
import OSLog

struct YahooFinanceClient {
    static let maximumConcurrentRequests = 6

    let session: URLSession
    let currentDate: @Sendable () -> Date
    private let baseURL = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart")!

    init(
        session: URLSession = .shared,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.currentDate = currentDate
    }

    /// One chart request for one ticker: builds the URL, sends it, decodes the
    /// response and turns Yahoo's in-band error or a missing result into a
    /// thrown error. Every endpoint the app uses goes through here.
    func chart(
        for symbol: String,
        query: [URLQueryItem],
        timeout: TimeInterval? = nil,
        operation: String
    ) async throws -> YahooChartResultDTO {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(symbol),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query

        guard let url = components?.url else {
            throw YahooFinanceError.invalidURL
        }

        var request = URLRequest(url: url)
        if let timeout {
            request.timeoutInterval = timeout
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await send(request, operation: operation)
        let decoded = try decodeChartResponse(from: data, operation: operation)

        // The chart wrapper may carry an error even on HTTP 200.
        if let chartError = decoded.chart.error {
            AppLog.marketData.error(
                "HTTP \(operation) provider error code=\(chartError.code ?? "nil") description=\(chartError.description ?? "nil")"
            )
            throw YahooFinanceError.providerError(chartError.description ?? "Unknown chart error.")
        }

        guard let result = decoded.chart.result?.first else {
            AppLog.marketData.error("HTTP \(operation) has no chart result")
            throw YahooFinanceError.emptyResult(symbol: symbol)
        }
        return result
    }

    /// The Yahoo ticker for a holding. Crypto needs a "-USD" pair suffix;
    /// everything else is used as-is. The kind comes from SnapTrade, never from
    /// the ticker's length: short ETF symbols such as IAUM and QQQM would
    /// otherwise read as crypto.
    func yahooSymbol(
        for rawSymbol: String,
        instrumentKind: PortfolioInstrumentKind?
    ) -> String? {
        let upper = normalizedSymbol(rawSymbol)
        guard !upper.isEmpty else { return nil }
        guard instrumentKind == .crypto, !upper.contains("-") else {
            return upper
        }
        return "\(upper)-USD"
    }

    func normalizedSymbol(_ symbol: String) -> String {
        symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func logKind(_ instrumentKind: PortfolioInstrumentKind?) -> String {
        instrumentKind?.rawValue ?? "unknown"
    }

    // MARK: - Transport

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
                throw YahooFinanceError.httpStatus(httpResponse.statusCode, bodyPreview)
            }

            AppLog.marketData.debug(
                "HTTP \(operation) succeeded \(responseSummary, privacy: .public)"
            )
            return data
        } catch let error as YahooFinanceError {
            throw error
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            AppLog.marketData.error(
                "HTTP \(operation) transport failed: \(AppLog.describe(error)) duration=\(AppLog.duration(since: startedAt), privacy: .public)"
            )
            throw error
        }
    }

    private func decodeChartResponse(
        from data: Data,
        operation: String
    ) throws -> YahooChartResponseDTO {
        do {
            return try JSONDecoder().decode(YahooChartResponseDTO.self, from: data)
        } catch {
            AppLog.marketData.error(
                "HTTP \(operation) decode failed: \(AppLog.describe(error)) body=\(responseBodyPreview(data))"
            )
            throw YahooFinanceError.decodingFailed(
                "\(operation): \(AppLog.describe(error))"
            )
        }
    }

    private func responseBodyPreview(_ data: Data) -> String {
        guard !data.isEmpty else { return "<empty>" }

        let preview = String(decoding: data.prefix(400), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? "<empty>" : "\"\(preview)\""
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
}
