//
//  YahooFinanceClient+Quotes.swift
//  Bittern
//
//  Regular-session quotes, enriched with the active pre- or post-market
//  quote when one is in session.
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

private struct YahooRegularQuoteResult: Sendable {
    let quote: YahooQuoteDTO
    let extendedHoursProbe: YahooExtendedHoursProbe
}

private enum YahooExtendedHoursProbe: Sendable {
    case inactive
    case active(YahooExtendedHoursRequest)
    case invalid(String)
}

private struct YahooExtendedHoursRequest: Sendable {
    let providerSymbol: String
    let extendedHoursSession: YahooExtendedHoursSession
    let session: PriceChartTimeSegment
    let regularClose: Double
}

extension YahooFinanceClient {
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

        // The chart API accepts one ticker per request. A portfolio refresh
        // must not open an unbounded number of them at once.
        let requestedAt = currentDate()
        let results = await withTaskGroup(
            of: (original: String, result: YahooRegularQuoteResult?).self
        ) { group in
            var pending = normalizedRequests.makeIterator()
            func addNext() {
                guard let request = pending.next() else { return }
                group.addTask {
                    let result = await fetchQuote(for: request, at: requestedAt)
                    return (request.symbol, result)
                }
            }
            for _ in 0..<Self.maximumConcurrentRequests {
                addNext()
            }

            var dict: [String: YahooRegularQuoteResult] = [:]
            for await (original, result) in group {
                if let result {
                    dict[original] = result
                }
                addNext()
            }
            return dict
        }

        let succeeded = results.keys.sorted()
        let failed = normalizedRequests.map(\.symbol).filter { results[$0] == nil }
        AppLog.marketData.debug(
            "Quotes completed succeeded=\(succeeded.count, privacy: .public)/\(normalizedRequests.count, privacy: .public) succeededSymbols=\(AppLog.list(succeeded)) failedSymbols=\(AppLog.list(failed)) taskCancelled=\(Task.isCancelled, privacy: .public)"
        )

        guard !results.isEmpty else {
            throw YahooFinanceError.noMarketData
        }

        let regularQuotes = results.mapValues(\.quote)
        let invalidProbeSymbols: [String] = results.compactMap { symbol, result in
            guard case .invalid = result.extendedHoursProbe else { return nil }
            return symbol
        }.sorted()
        guard invalidProbeSymbols.isEmpty else {
            AppLog.marketData.error(
                "Extended-hours probe metadata invalid symbols=\(AppLog.list(invalidProbeSymbols))"
            )
            return YahooQuoteBatch(quotes: regularQuotes, didFailExtendedHours: true)
        }

        let extendedHoursRequests: [(symbol: String, request: YahooExtendedHoursRequest)] =
            results.compactMap { symbol, result in
                guard case .active(let request) = result.extendedHoursProbe else {
                    return nil
                }
                return (symbol: symbol, request: request)
            }
        guard !extendedHoursRequests.isEmpty else {
            return YahooQuoteBatch(quotes: regularQuotes, didFailExtendedHours: false)
        }

        do {
            let extendedHoursQuotes = try await fetchExtendedHoursQuotes(extendedHoursRequests)
            let enrichedQuotes = regularQuotes.mapValues { quote in
                let extendedHoursQuote = extendedHoursQuotes[quote.symbol]
                return YahooQuoteDTO(
                    symbol: quote.symbol,
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
            return YahooQuoteBatch(quotes: enrichedQuotes, didFailExtendedHours: false)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.marketData.error(
                "Extended-hours quote batch failed: \(AppLog.describe(error))"
            )
            return YahooQuoteBatch(quotes: regularQuotes, didFailExtendedHours: true)
        }
    }

    // MARK: - Regular session

    /// Fetches the regular-session quote. The returned DTO carries the
    /// holding's own symbol, not the Yahoo one, so callers can look it up by
    /// the ticker they already have.
    private func fetchQuote(
        for request: YahooQuoteRequest,
        at requestedAt: Date
    ) async -> YahooRegularQuoteResult? {
        let upper = normalizedSymbol(request.symbol)
        guard let yahooSymbol = yahooSymbol(
            for: request.symbol,
            instrumentKind: request.instrumentKind
        ) else {
            return nil
        }

        AppLog.marketData.debug(
            "Quote symbol=\(upper) yahooSymbol=\(yahooSymbol) instrumentKind=\(logKind(request.instrumentKind), privacy: .public) started"
        )

        do {
            let result = try await chart(
                for: yahooSymbol,
                query: [
                    URLQueryItem(name: "interval", value: "1d"),
                    URLQueryItem(name: "range", value: "1d"),
                    URLQueryItem(name: "includePrePost", value: "false")
                ],
                operation: "quote candidate=\(yahooSymbol)"
            )
            guard let meta = result.meta, let currentPrice = meta.regularMarketPrice else {
                throw YahooFinanceError.emptyResult(symbol: yahooSymbol)
            }

            AppLog.marketData.debug(
                "Quote symbol=\(upper) succeeded price=\(currentPrice) previousClose=\(AppLog.optional(meta.chartPreviousClose)) currency=\(meta.currency ?? "nil")"
            )
            return YahooRegularQuoteResult(
                quote: YahooQuoteDTO(
                    symbol: upper,
                    currency: meta.currency,
                    regularMarketPrice: currentPrice,
                    regularMarketPreviousClose: meta.chartPreviousClose,
                    preMarket: nil,
                    postMarket: nil
                ),
                extendedHoursProbe: extendedHoursProbe(
                    meta: meta,
                    providerSymbol: yahooSymbol,
                    regularClose: currentPrice,
                    requestedAt: requestedAt
                )
            )
        } catch {
            AppLog.marketData.warning(
                "Quote symbol=\(upper) yahooSymbol=\(yahooSymbol) failed: \(AppLog.describe(error))"
            )
            return nil
        }
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
            return .invalid("Missing or malformed current trading periods for \(providerSymbol).")
        }

        for (session, period) in [(YahooExtendedHoursSession.preMarket, preMarket), (.postMarket, postMarket)]
        where period.contains(requestedAt) {
            return .active(
                YahooExtendedHoursRequest(
                    providerSymbol: providerSymbol,
                    extendedHoursSession: session,
                    session: period,
                    regularClose: regularClose
                )
            )
        }
        return .inactive
    }

    private func marketSession(from period: YahooCurrentTradingPeriodDTO?) -> PriceChartTimeSegment? {
        guard let start = period?.start,
              let end = period?.end,
              start < end
        else {
            return nil
        }

        return PriceChartTimeSegment(
            start: Date(timeIntervalSince1970: TimeInterval(start)),
            end: Date(timeIntervalSince1970: TimeInterval(end))
        )
    }

    // MARK: - Extended hours

    private func fetchExtendedHoursQuotes(
        _ requests: [(symbol: String, request: YahooExtendedHoursRequest)]
    ) async throws -> [String: YahooExtendedHoursQuoteDTO] {
        try await withThrowingTaskGroup(
            of: (symbol: String, quote: YahooExtendedHoursQuoteDTO).self,
            returning: [String: YahooExtendedHoursQuoteDTO].self
        ) { group in
            var pending = requests.makeIterator()
            func addNext() {
                guard let item = pending.next() else { return }
                group.addTask {
                    let quote = try await fetchExtendedHoursQuote(item.request)
                    return (item.symbol, quote)
                }
            }
            for _ in 0..<Self.maximumConcurrentRequests {
                addNext()
            }

            var quotes: [String: YahooExtendedHoursQuoteDTO] = [:]
            do {
                for try await (symbol, quote) in group {
                    quotes[symbol] = quote
                    addNext()
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
        let result = try await chart(
            for: symbol,
            query: [
                URLQueryItem(name: "interval", value: "1m"),
                URLQueryItem(name: "range", value: "1d"),
                URLQueryItem(name: "includePrePost", value: "true")
            ],
            operation: "\(sessionName) candidate=\(symbol)"
        )

        let currentPeriods = result.meta?.currentTradingPeriod
        let currentPeriod = extendedHoursRequest.extendedHoursSession == .preMarket
            ? currentPeriods?.pre
            : currentPeriods?.post
        guard result.meta?.hasPrePostMarketData == true,
              let detailedSession = marketSession(from: currentPeriod),
              detailedSession == extendedHoursRequest.session
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

        return YahooExtendedHoursQuoteDTO(
            extendedHoursSession: extendedHoursRequest.extendedHoursSession,
            price: latestObservation?.price ?? extendedHoursRequest.regularClose,
            regularClose: extendedHoursRequest.regularClose,
            observedAt: latestObservation?.date,
            sessionStart: extendedHoursRequest.session.start,
            sessionEnd: extendedHoursRequest.session.end
        )
    }

    private func logAssets(_ requests: [YahooQuoteRequest]) -> String {
        AppLog.list(requests.map { "\($0.symbol):\(logKind($0.instrumentKind))" })
    }
}
