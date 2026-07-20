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

struct YahooQuoteBatch: Sendable {
    let quotes: [String: YahooQuoteDTO]
    let didFailExtendedHours: Bool

    static let empty = YahooQuoteBatch(
        quotes: [:],
        didFailExtendedHours: false
    )
}

private struct YahooRegularQuoteResult: Sendable {
    let quote: YahooQuoteDTO
    let extendedHoursProbe: YahooExtendedHoursProbe
}

private enum YahooExtendedHoursProbe: Sendable {
    case inactive
    case active(YahooExtendedHoursRequest)
    case invalid(String)
}

enum YahooExtendedHoursSession: Equatable, Sendable {
    case preMarket
    case postMarket

    var logName: String {
        switch self {
        case .preMarket: "pre-market"
        case .postMarket: "post-market"
        }
    }
}

private struct YahooExtendedHoursRequest: Sendable {
    let providerSymbol: String
    let extendedHoursSession: YahooExtendedHoursSession
    let session: YahooMarketSession
    let regularClose: Double
}

private struct YahooMarketSession: Equatable, Sendable {
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

enum YahooFinanceError: LocalizedError {
    case invalidURL
    case emptySymbols
    case invalidResponse
    case invalidChartMetadata(String)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The Yahoo service URL is invalid."
        case .emptySymbols:
            "There are no symbols to quote."
        case .invalidResponse:
            "Yahoo returned a non-HTTP response."
        case .invalidChartMetadata(let reason):
            "Yahoo returned invalid chart timing data. \(reason)"
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

    /// Returns quotes keyed by the original normalized symbol (for example
    /// "BTC"), regardless of the Yahoo symbol used for the request. Regular
    /// quotes remain usable when the atomic extended-hours enrichment batch fails.
    func quotes(for requests: [YahooQuoteRequest]) async throws -> YahooQuoteBatch {
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
        let requestedAt = Date()
        let results = await withTaskGroup(
            of: (original: String, result: YahooRegularQuoteResult?).self
        ) { group in
            for request in normalizedRequests {
                group.addTask {
                    let result = await fetchQuote(
                        for: request,
                        at: requestedAt
                    )
                    return (request.symbol, result)
                }
            }

            var dict: [String: YahooRegularQuoteResult] = [:]
            for await (original, result) in group {
                if let result {
                    dict[original] = result
                }
            }
            return dict
        }

        let succeeded = results.keys.sorted()
        let failed = normalizedRequests.map(\.symbol).filter { results[$0] == nil }
        AppLog.marketData.debug(
            "Quotes completed succeeded=\(succeeded.count, privacy: .public)/\(normalizedRequests.count, privacy: .public) succeededSymbols=\(AppLog.list(succeeded)) failedSymbols=\(AppLog.list(failed)) taskCancelled=\(Task.isCancelled, privacy: .public)"
        )

        guard !results.isEmpty else {
            throw YahooFinanceError.httpStatus(-1, "No market data was returned.")
        }

        let regularQuotes = results.mapValues(\.quote)
        let invalidProbeSymbols: [String] = results.compactMap { entry in
            let (symbol, result) = entry
            guard case .invalid = result.extendedHoursProbe else { return nil }
            return symbol
        }.sorted()
        guard invalidProbeSymbols.isEmpty else {
            AppLog.marketData.error(
                "Extended-hours probe metadata invalid symbols=\(AppLog.list(invalidProbeSymbols))"
            )
            return YahooQuoteBatch(
                quotes: regularQuotes,
                didFailExtendedHours: true
            )
        }

        let extendedHoursRequests: [(
            symbol: String,
            request: YahooExtendedHoursRequest
        )] = results.compactMap { entry in
            let (symbol, result) = entry
            guard case .active(let request) = result.extendedHoursProbe else {
                return nil
            }
            return (symbol: symbol, request: request)
        }
        guard !extendedHoursRequests.isEmpty else {
            return YahooQuoteBatch(
                quotes: regularQuotes,
                didFailExtendedHours: false
            )
        }

        do {
            let extendedHoursQuotes = try await fetchExtendedHoursQuotes(
                extendedHoursRequests
            )
            let enrichedQuotes = regularQuotes.mapValues { quote in
                let extendedHoursQuote = extendedHoursQuotes[quote.symbol]
                return YahooQuoteDTO(
                    symbol: quote.symbol,
                    shortName: quote.shortName,
                    longName: quote.longName,
                    currency: quote.currency,
                    regularMarketPrice: quote.regularMarketPrice,
                    regularMarketPreviousClose: quote.regularMarketPreviousClose,
                    preMarket: extendedHoursQuote?.extendedHoursSession == .preMarket
                        ? extendedHoursQuote
                        : nil,
                    postMarket: extendedHoursQuote?.extendedHoursSession == .postMarket
                        ? extendedHoursQuote
                        : nil
                )
            }
            return YahooQuoteBatch(
                quotes: enrichedQuotes,
                didFailExtendedHours: false
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.marketData.error(
                "Extended-hours quote batch failed: \(AppLog.describe(error))"
            )
            return YahooQuoteBatch(
                quotes: regularQuotes,
                didFailExtendedHours: true
            )
        }
    }

    func priceHistory(
        for symbol: String,
        instrumentKind: PortfolioInstrumentKind?,
        range: HoldingChartRange
    ) async throws -> HoldingPriceSeries {
        let candidates = candidateSymbols(for: symbol, instrumentKind: instrumentKind)
        guard !candidates.isEmpty else {
            throw YahooFinanceError.emptySymbols
        }

        AppLog.marketData.debug(
            "Price history requested symbol=\(symbol) instrumentKind=\(logKind(instrumentKind), privacy: .public) range=\(range.title, privacy: .public) candidates=\(AppLog.list(candidates))"
        )

        var lastError: Error?
        for candidate in candidates {
            do {
                let history = try await fetchHistoryOne(candidate: candidate, range: range)
                if !history.points.isEmpty {
                    AppLog.marketData.debug(
                        "Price history candidate=\(candidate) returned points=\(history.points.count, privacy: .public)"
                    )
                    return history
                }
                AppLog.marketData.warning(
                    "Price history candidate=\(candidate) returned no points"
                )
            } catch {
                lastError = error
                AppLog.marketData.warning(
                    "Price history candidate=\(candidate) failed: \(AppLog.describe(error))"
                )
            }
        }

        AppLog.marketData.error(
            "Price history failed for every candidate symbol=\(symbol)"
        )
        throw lastError ?? YahooFinanceError.httpStatus(-1, "Empty chart result for \(symbol)")
    }

    // MARK: - Private

    /// Try the symbol as-is (works for stocks), then with "-USD" appended
    /// (required for crypto).  The returned DTO carries the ORIGINAL symbol
    /// so callers can look up by the ticker they already have.
    private func fetchQuote(
        for request: YahooQuoteRequest,
        at requestedAt: Date
    ) async -> YahooRegularQuoteResult? {
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
                let result = try await fetchOne(
                    candidate: candidate,
                    at: requestedAt
                )
                let quote = result.quote
                AppLog.marketData.debug(
                    "Quote symbol=\(upper) candidate=\(candidate) succeeded price=\(AppLog.optional(quote.regularMarketPrice)) previousClose=\(AppLog.optional(quote.regularMarketPreviousClose)) currency=\(quote.currency ?? "nil")"
                )
                // Always report back with the original ticker
                return YahooRegularQuoteResult(
                    quote: YahooQuoteDTO(
                        symbol: upper,
                        shortName: quote.shortName,
                        longName: quote.longName,
                        currency: quote.currency,
                        regularMarketPrice: quote.regularMarketPrice,
                        regularMarketPreviousClose: quote.regularMarketPreviousClose,
                        preMarket: nil,
                        postMarket: nil
                    ),
                    extendedHoursProbe: result.extendedHoursProbe
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

    private func fetchOne(
        candidate symbol: String,
        at requestedAt: Date
    ) async throws -> YahooRegularQuoteResult {
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

        let quote = YahooQuoteDTO(
            symbol: symbol,
            shortName: meta.shortName,
            longName: meta.longName,
            currency: meta.currency,
            regularMarketPrice: currentPrice,
            regularMarketPreviousClose: previousClose,
            preMarket: nil,
            postMarket: nil
        )
        return YahooRegularQuoteResult(
            quote: quote,
            extendedHoursProbe: extendedHoursProbe(
                meta: meta,
                providerSymbol: symbol,
                regularClose: currentPrice,
                requestedAt: requestedAt
            )
        )
    }

    private func extendedHoursProbe(
        meta: YahooChartMetaDTO,
        providerSymbol: String,
        regularClose: Double,
        requestedAt: Date
    ) -> YahooExtendedHoursProbe {
        guard meta.hasPrePostMarketData == true else {
            return .inactive
        }
        guard regularClose.isFinite, regularClose > 0 else {
            return .invalid("Invalid regular close for \(providerSymbol).")
        }
        guard let periods = meta.currentTradingPeriod,
              let preMarket = marketSession(from: periods.pre),
              let regular = marketSession(from: periods.regular),
              let postMarket = marketSession(from: periods.post),
              preMarket.end <= regular.start,
              regular.end <= postMarket.start
        else {
            return .invalid(
                "Missing or malformed current trading periods for \(providerSymbol)."
            )
        }
        if preMarket.contains(requestedAt) {
            return .active(
                YahooExtendedHoursRequest(
                    providerSymbol: providerSymbol,
                    extendedHoursSession: .preMarket,
                    session: preMarket,
                    regularClose: regularClose
                )
            )
        }

        if postMarket.contains(requestedAt) {
            return .active(
                YahooExtendedHoursRequest(
                    providerSymbol: providerSymbol,
                    extendedHoursSession: .postMarket,
                    session: postMarket,
                    regularClose: regularClose
                )
            )
        }

        return .inactive
    }

    private func marketSession(
        from period: YahooCurrentTradingPeriodDTO?
    ) -> YahooMarketSession? {
        guard let start = period?.start,
              let end = period?.end,
              start < end
        else {
            return nil
        }

        return YahooMarketSession(
            start: Date(timeIntervalSince1970: TimeInterval(start)),
            end: Date(timeIntervalSince1970: TimeInterval(end))
        )
    }

    private func currentTradingPeriod(
        for extendedHoursSession: YahooExtendedHoursSession,
        in periods: YahooCurrentTradingPeriodsDTO?
    ) -> YahooCurrentTradingPeriodDTO? {
        switch extendedHoursSession {
        case .preMarket:
            periods?.pre
        case .postMarket:
            periods?.post
        }
    }

    private func fetchExtendedHoursQuotes(
        _ requests: [(symbol: String, request: YahooExtendedHoursRequest)]
    ) async throws -> [String: YahooExtendedHoursQuoteDTO] {
        try await withThrowingTaskGroup(
            of: (symbol: String, quote: YahooExtendedHoursQuoteDTO).self,
            returning: [String: YahooExtendedHoursQuoteDTO].self
        ) { group in
            for item in requests {
                group.addTask {
                    let quote = try await fetchExtendedHoursQuote(item.request)
                    return (item.symbol, quote)
                }
            }

            var quotes: [String: YahooExtendedHoursQuoteDTO] = [:]
            do {
                for try await (symbol, quote) in group {
                    quotes[symbol] = quote
                }
                return quotes
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func fetchExtendedHoursQuote(
        _ extendedHoursRequest: YahooExtendedHoursRequest
    ) async throws -> YahooExtendedHoursQuoteDTO {
        let symbol = extendedHoursRequest.providerSymbol
        let sessionName = extendedHoursRequest.extendedHoursSession.logName
        var components = URLComponents(string: "\(baseURL)/\(symbol)")
        components?.queryItems = [
            URLQueryItem(name: "interval", value: "1m"),
            URLQueryItem(name: "range", value: "1d"),
            URLQueryItem(name: "includePrePost", value: "true")
        ]

        guard let url = components?.url else {
            throw YahooFinanceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(
            request,
            operation: "\(sessionName) candidate=\(symbol)"
        )

        let decoded: YahooChartResponseDTO
        do {
            decoded = try JSONDecoder().decode(
                YahooChartResponseDTO.self,
                from: data
            )
        } catch {
            AppLog.marketData.error(
                "HTTP \(sessionName) candidate=\(symbol) decode failed: \(AppLog.describe(error)) body=\(responseBodyPreview(data))"
            )
            throw error
        }

        if let chartError = decoded.chart.error {
            throw YahooFinanceError.httpStatus(
                -1,
                chartError.description ?? "Yahoo chart error"
            )
        }
        guard let result = decoded.chart.result?.first,
              let meta = result.meta,
              meta.hasPrePostMarketData == true,
              let detailedExtendedHours = marketSession(
                from: currentTradingPeriod(
                    for: extendedHoursRequest.extendedHoursSession,
                    in: meta.currentTradingPeriod
                )
              ),
              detailedExtendedHours == extendedHoursRequest.session
        else {
            throw YahooFinanceError.invalidChartMetadata(
                "The current \(sessionName) session changed or is missing for \(symbol)."
            )
        }

        let timestamps = result.timestamp ?? []
        let closes = result.indicators?.quote?.first?.close ?? []
        guard timestamps.count == closes.count else {
            throw YahooFinanceError.invalidChartMetadata(
                "Timestamp and \(sessionName) close counts differ for \(symbol)."
            )
        }

        var previousTimestamp: Int?
        var latestObservation: (date: Date, price: Double)?
        for (timestamp, close) in zip(timestamps, closes) {
            if let previousTimestamp, timestamp <= previousTimestamp {
                throw YahooFinanceError.invalidChartMetadata(
                    "Unordered \(sessionName) timestamps for \(symbol)."
                )
            }
            previousTimestamp = timestamp

            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            guard extendedHoursRequest.session.contains(date), let close else {
                continue
            }
            guard close.isFinite, close > 0 else {
                throw YahooFinanceError.invalidChartMetadata(
                    "Invalid \(sessionName) price for \(symbol)."
                )
            }
            latestObservation = (date, close)
        }

        let price = latestObservation?.price ?? extendedHoursRequest.regularClose
        return YahooExtendedHoursQuoteDTO(
            extendedHoursSession: extendedHoursRequest.extendedHoursSession,
            price: price,
            regularClose: extendedHoursRequest.regularClose,
            observedAt: latestObservation?.date,
            sessionStart: extendedHoursRequest.session.start,
            sessionEnd: extendedHoursRequest.session.end
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
            if Task.isCancelled {
                throw CancellationError()
            }
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

    private func fetchHistoryOne(candidate symbol: String, range: HoldingChartRange) async throws -> HoldingPriceSeries {
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

        guard timestamps.count == closes.count else {
            throw YahooFinanceError.invalidChartMetadata(
                "Timestamp and close counts differ for \(symbol)."
            )
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

        let timeDomain = try range == .oneDay
            ? oneDayTimeDomain(meta: result.meta, points: points, symbol: symbol)
            : nil

        return HoldingPriceSeries(points: points, timeDomain: timeDomain)
    }

    private func oneDayTimeDomain(
        meta: YahooChartMetaDTO?,
        points: [HoldingPricePoint],
        symbol: String
    ) throws -> PriceChartTimeDomain {
        guard let meta else {
            throw YahooFinanceError.invalidChartMetadata("Missing metadata for \(symbol).")
        }
        guard meta.range == HoldingChartRange.oneDay.yahooRange else {
            throw YahooFinanceError.invalidChartMetadata("Unexpected range for \(symbol).")
        }
        guard meta.dataGranularity == HoldingChartRange.oneDay.yahooInterval,
              let granularity = duration(forYahooInterval: meta.dataGranularity)
        else {
            throw YahooFinanceError.invalidChartMetadata("Unexpected granularity for \(symbol).")
        }
        guard let timeZoneName = meta.exchangeTimezoneName,
              let timeZone = TimeZone(identifier: timeZoneName)
        else {
            throw YahooFinanceError.invalidChartMetadata("Missing exchange timezone for \(symbol).")
        }
        guard let tradingPeriods = meta.tradingPeriods else {
            throw YahooFinanceError.invalidChartMetadata("Missing trading periods for \(symbol).")
        }
        guard case .regular(let periodGroups) = tradingPeriods else {
            throw YahooFinanceError.invalidChartMetadata(
                "Unexpected extended trading periods for \(symbol)."
            )
        }

        let rawPeriods = periodGroups.flatMap { $0 }
        guard !rawPeriods.isEmpty else {
            throw YahooFinanceError.invalidChartMetadata("Empty trading periods for \(symbol).")
        }

        let periods = try rawPeriods.map { rawPeriod -> PriceChartTimeDomain in
            guard let start = rawPeriod.start,
                  let end = rawPeriod.end,
                  start < end
            else {
                throw YahooFinanceError.invalidChartMetadata("Malformed trading period for \(symbol).")
            }

            return PriceChartTimeDomain(
                start: Date(timeIntervalSince1970: TimeInterval(start)),
                end: Date(timeIntervalSince1970: TimeInterval(end))
            )
        }

        guard zip(points, points.dropFirst()).allSatisfy({ previous, next in
            previous.date < next.date
        }) else {
            throw YahooFinanceError.invalidChartMetadata("Unordered timestamps for \(symbol).")
        }

        let matchingPeriods = periods.filter { period in
            points.allSatisfy { point in
                point.date >= period.start && point.date <= period.end
            }
        }
        guard matchingPeriods.count == 1, let period = matchingPeriods.first else {
            throw YahooFinanceError.invalidChartMetadata(
                "Expected one trading period matching the points for \(symbol)."
            )
        }

        if coversFullCalendarDay(period, in: timeZone, granularity: granularity),
           let firstPoint = points.first,
           let lastPoint = points.last {
            return PriceChartTimeDomain(start: firstPoint.date, end: lastPoint.date)
        }

        return period
    }

    private func coversFullCalendarDay(
        _ period: PriceChartTimeDomain,
        in timeZone: TimeZone,
        granularity: TimeInterval
    ) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let startOfDay = calendar.startOfDay(for: period.start)
        guard period.start == startOfDay,
              let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
        else {
            return false
        }

        let remaining = nextDay.timeIntervalSince(period.end)
        return remaining >= 0 && remaining <= granularity
    }

    private func duration(forYahooInterval interval: String?) -> TimeInterval? {
        guard let interval,
              let unit = interval.last,
              let amount = Double(interval.dropLast()),
              amount > 0
        else {
            return nil
        }

        switch unit {
        case "m":
            return amount * 60
        case "h":
            return amount * 60 * 60
        case "d":
            return amount * 24 * 60 * 60
        default:
            return nil
        }
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
    let exchangeTimezoneName: String?
    let dataGranularity: String?
    let range: String?
    let tradingPeriods: YahooTradingPeriodsDTO?
    let hasPrePostMarketData: Bool?
    let currentTradingPeriod: YahooCurrentTradingPeriodsDTO?
}

private struct YahooTradingPeriodDTO: Decodable {
    let start: Int?
    let end: Int?
}

private enum YahooTradingPeriodsDTO: Decodable {
    case regular([[YahooTradingPeriodDTO]])
    case extended(YahooExtendedTradingPeriodsDTO)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let regular = try? container.decode(
            [[YahooTradingPeriodDTO]].self
        ) {
            self = .regular(regular)
            return
        }

        self = .extended(
            try container.decode(YahooExtendedTradingPeriodsDTO.self)
        )
    }
}

private struct YahooExtendedTradingPeriodsDTO: Decodable {
    let pre: [[YahooTradingPeriodDTO]]?
    let regular: [[YahooTradingPeriodDTO]]?
    let post: [[YahooTradingPeriodDTO]]?
}

private struct YahooCurrentTradingPeriodsDTO: Decodable {
    let pre: YahooCurrentTradingPeriodDTO?
    let regular: YahooCurrentTradingPeriodDTO?
    let post: YahooCurrentTradingPeriodDTO?
}

private struct YahooCurrentTradingPeriodDTO: Decodable {
    let start: Int?
    let end: Int?
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

// MARK: - Quote results

struct YahooQuoteDTO: Sendable {
    let symbol: String
    let shortName: String?
    let longName: String?
    let currency: String?
    let regularMarketPrice: Double?
    let regularMarketPreviousClose: Double?
    let preMarket: YahooExtendedHoursQuoteDTO?
    let postMarket: YahooExtendedHoursQuoteDTO?

    var fullName: String? {
        longName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var displayName: String? {
        fullName
    }
}

struct YahooExtendedHoursQuoteDTO: Sendable {
    let extendedHoursSession: YahooExtendedHoursSession
    let price: Double
    let regularClose: Double
    let observedAt: Date?
    let sessionStart: Date
    let sessionEnd: Date
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
