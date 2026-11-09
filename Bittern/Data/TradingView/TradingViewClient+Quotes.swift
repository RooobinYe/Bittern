//
//  TradingViewClient+Quotes.swift
//  Bittern
//
//  Regular-session quotes, with the active pre-market, post-market or
//  overnight quote when one is in session, read from the streaming quote
//  session.
//

import Foundation
import OSLog

extension TradingViewClient {
    /// Returns quotes keyed by the original normalized symbol (for example
    /// "BTC"), regardless of the TradingView symbol used for the request.
    /// Symbols TradingView rejects or doesn't complete in time are left
    /// out; when every one is, the request fails.
    func quotes(for requests: [MarketQuoteRequest]) async throws -> MarketQuoteBatch {
        var providerSymbols: [String: String] = [:]
        var kinds: [String: PortfolioInstrumentKind?] = [:]
        for request in requests {
            let symbol = normalizedSymbol(request.symbol)
            guard !symbol.isEmpty else { continue }
            if let existing = kinds[symbol], existing != nil, request.instrumentKind == nil {
                continue
            }
            guard let providerSymbol = tradingViewSymbol(for: symbol, instrumentKind: request.instrumentKind) else {
                continue
            }
            providerSymbols[symbol] = providerSymbol
            kinds[symbol] = request.instrumentKind
        }

        guard !providerSymbols.isEmpty else {
            throw TradingViewError.emptySymbols
        }

        let startedAt = Date()
        let states = try await quoteFeed.quotes(
            for: Array(Set(providerSymbols.values)).sorted(),
            timeout: Self.quoteTimeout
        )
        let now = currentDate()

        var quotes: [String: MarketQuote] = [:]
        var failed: [String] = []
        var didFailExtendedHours = false
        for (symbol, providerSymbol) in providerSymbols.sorted(by: { $0.key < $1.key }) {
            switch states[providerSymbol] {
            case .ready(let fields):
                let built = quote(symbol: symbol, providerSymbol: providerSymbol, fields: fields, at: now)
                quotes[symbol] = built.quote
                didFailExtendedHours = didFailExtendedHours || built.didFailExtendedHours
            case .failed(let reason):
                failed.append(symbol)
                AppLog.marketData.warning("Quote symbol=\(symbol) tradingViewSymbol=\(providerSymbol) failed: \(reason)")
            case .pending, nil:
                failed.append(symbol)
                AppLog.marketData.warning("Quote symbol=\(symbol) tradingViewSymbol=\(providerSymbol) timed out")
            }
        }

        AppLog.marketData.debug(
            "Quotes read succeeded=\(quotes.count, privacy: .public)/\(providerSymbols.count, privacy: .public) failedSymbols=\(AppLog.list(failed)) duration=\(AppLog.duration(since: startedAt), privacy: .public)"
        )
        guard !quotes.isEmpty else {
            throw TradingViewError.noMarketData
        }
        return MarketQuoteBatch(quotes: quotes, didFailExtendedHours: didFailExtendedHours)
    }

    /// One quote from the fields the stream holds. Without readable trading
    /// hours an exchange-traded quote keeps its regular price but has no
    /// trading day and no extended-hours quote, and says so.
    private func quote(
        symbol: String,
        providerSymbol: String,
        fields: [String: JSONValue],
        at now: Date
    ) -> (quote: MarketQuote, didFailExtendedHours: Bool) {
        let price = fields["lp"]?.number.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let previousClose = fields["prev_close_price"]?.number.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let priceTime = fields["lp_time"]?.number.map { Date(timeIntervalSince1970: $0) }
        if let mode = fields["update_mode"]?.string, mode != "streaming" {
            AppLog.marketData.warning("Quote symbol=\(symbol) updateMode=\(mode, privacy: .public)")
        }

        let calendar: TradingViewSessionCalendar
        do {
            calendar = try TradingViewSessionCalendar(
                timeZone: fields["timezone"]?.string,
                subsessions: fields["subsessions"],
                holidays: fields["session_holidays"]?.string
            )
        } catch {
            AppLog.marketData.error(
                "Quote symbol=\(symbol) tradingViewSymbol=\(providerSymbol) has unreadable trading hours: \(AppLog.describe(error))"
            )
            return (
                MarketQuote(
                    symbol: symbol,
                    currency: fields["currency_code"]?.string,
                    regularMarketPrice: price,
                    regularMarketPreviousClose: previousClose,
                    preMarket: nil,
                    postMarket: nil,
                    regularMarketTime: priceTime
                ),
                true
            )
        }

        let marketSession = calendar.tradesAroundTheClock ? nil : calendar.latestTradingDay(startedBy: now)
        let extendedHours = extendedHoursQuote(
            fields: fields,
            regularClose: price,
            marketSession: marketSession,
            at: now
        )
        AppLog.marketData.debug(
            "Quote symbol=\(symbol) price=\(AppLog.optional(price)) previousClose=\(AppLog.optional(previousClose)) currency=\(fields["currency_code"]?.string ?? "nil") session=\(fields["current_session"]?.string ?? "nil", privacy: .public) extendedHours=\(extendedHours.quote?.extendedHoursSession.logName ?? "none", privacy: .public)"
        )
        return (
            MarketQuote(
                symbol: symbol,
                currency: fields["currency_code"]?.string,
                regularMarketPrice: price,
                regularMarketPreviousClose: previousClose,
                preMarket: extendedHours.quote?.extendedHoursSession == .preMarket ? extendedHours.quote : nil,
                postMarket: extendedHours.quote?.extendedHoursSession == .postMarket ? extendedHours.quote : nil,
                regularMarketTime: priceTime.map(calendar.regularTradeTime(for:)),
                marketSession: marketSession,
                overnight: extendedHours.quote?.extendedHoursSession == .overnight ? extendedHours.quote : nil
            ),
            extendedHours.didFail
        )
    }

    /// The quote of the pre-market, post-market or overnight session in
    /// progress at `now`. TradingView sends pre- and post-market trades as
    /// `rtc` and overnight trades as `ntc`; either counts only when it
    /// traded inside that session. Before the session's first trade the
    /// price is the regular close.
    private func extendedHoursQuote(
        fields: [String: JSONValue],
        regularClose: Double?,
        marketSession: HoldingMarketSession?,
        at now: Date
    ) -> (quote: ExtendedHoursQuote?, didFail: Bool) {
        guard let marketSession else { return (nil, false) }

        let active: (ExtendedHoursSession, PriceChartTimeSegment)
        let preMarket = PriceChartTimeSegment(start: marketSession.start, end: marketSession.regularStart)
        let postMarket = PriceChartTimeSegment(start: marketSession.regularEnd, end: marketSession.end)
        let overnight = marketSession.overnight.map { PriceChartTimeSegment(start: $0.start, end: $0.end) }
        if preMarket.start < preMarket.end, preMarket.contains(now) {
            active = (.preMarket, preMarket)
        } else if postMarket.start < postMarket.end, postMarket.contains(now) {
            active = (.postMarket, postMarket)
        } else if let overnight, overnight.contains(now) {
            active = (.overnight, overnight)
        } else {
            return (nil, false)
        }
        guard let regularClose else {
            return (nil, true)
        }

        let priceField = active.0 == .overnight ? "ntc" : "rtc"
        let tradeTime = fields["\(priceField)_time"]?.number.map { Date(timeIntervalSince1970: $0) }
        let tradePrice = fields[priceField]?.number.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let trade = tradeTime.flatMap { time in
            tradePrice.flatMap { active.1.contains(time) ? (time, $0) : nil }
        }
        return (
            ExtendedHoursQuote(
                extendedHoursSession: active.0,
                price: trade?.1 ?? regularClose,
                regularClose: regularClose,
                observedAt: trade?.0,
                sessionStart: active.1.start,
                sessionEnd: active.1.end
            ),
            false
        )
    }
}
