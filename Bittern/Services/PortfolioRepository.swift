//
//  PortfolioRepository.swift
//  Bittern
//

import Foundation

protocol PortfolioRepository {
    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioSnapshot
    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot
}

struct LivePortfolioRepository: PortfolioRepository {
    private let dividendActivityTypes = ["DIVIDEND", "REI", "STOCK_DIVIDEND"]
    private let logoURLResolver = BrandfetchLogoURLResolver()

    func loadPortfolio(credentials: SnapTradeCredentials) async throws -> PortfolioSnapshot {
        debugLog("loadPortfolio started taskCancelled=\(Task.isCancelled)")
        let snapTrade = SnapTradeClient(credentials: credentials)
        let yahoo = YahooFinanceClient()

        let accountSources = try await loadAccountSources(from: snapTrade)
        debugLog("loadPortfolio accountSources=\(accountSources.count)")
        let accounts = accountSources.map { source in
            let dto = source.account
            return PortfolioAccount(
                id: dto.id,
                connectionID: source.connection?.id ?? dto.brokerageAuthorizationID,
                name: dto.displayName,
                institutionName: source.connection?.displayName ?? dto.displayInstitution,
                providerLogoURL: source.connection?.logoURL,
                isConnectionDisabled: source.connection?.disabled == true,
                totalBalance: dto.balance?.total?.amount,
                currencyCode: dto.balance?.total?.currency ?? "USD"
            )
        }

        var positionsByAccount: [(PortfolioAccount, SnapTradePositionDTO)] = []
        for account in accounts {
            debugLog("loadPortfolio loading positions currentCount=\(positionsByAccount.count)")
            let positions = try await snapTrade.listPositions(accountID: account.id)
            positionsByAccount.append(contentsOf: positions.map { (account, $0) })
            debugLog("loadPortfolio loaded positions batch=\(positions.count) total=\(positionsByAccount.count)")
        }

        let quoteRequests = positionsByAccount.compactMap { _, position -> YahooQuoteRequest? in
            guard let symbol = position.resolvedSymbol else { return nil }
            return YahooQuoteRequest(
                symbol: symbol,
                instrumentKind: PortfolioInstrumentKind(
                    snapTradeValue: position.instrument?.kind
                )
            )
        }
        debugLog("loadPortfolio loading quotes assets=\(quoteRequests.count)")

        let quotes = (try? await yahoo.quotes(for: quoteRequests)) ?? [:]
        debugLog("loadPortfolio loaded quotes=\(quotes.count)")
        let dividendActivitiesByAccount = await loadDividendActivitiesByAccount(
            accounts: accounts,
            snapTrade: snapTrade
        )
        debugLog("loadPortfolio loaded dividendActivityAccounts=\(dividendActivitiesByAccount.count)")

        let holdings = positionsByAccount.compactMap { account, position -> PortfolioHolding? in
            guard let rawSymbol = position.resolvedSymbol?.trimmedNonEmpty else {
                return nil
            }
            guard let units = position.units else {
                return nil
            }

            let symbol = rawSymbol.uppercased()
            let quote = quotes[symbol]
            let currentPrice = quote?.regularMarketPrice.flatMap { $0 > 0 ? $0 : nil }
            let previousClose = quote?.regularMarketPreviousClose
            let averageCost = position.resolvedAverageCost
            let currencyCode = position.resolvedCurrency ?? account.currencyCode
            let name = position.resolvedName ?? symbol
            let instrumentKind = PortfolioInstrumentKind(
                snapTradeValue: position.instrument?.kind
            )
            let logoURL = logoURLResolver.logoURL(for: symbol, kind: instrumentKind)
            debugLog(
                "logoResolution symbol=\(symbol) snapTradeKind=\(position.instrument?.kind ?? "nil") resolvedKind=\(instrumentKind?.rawValue ?? "nil") configured=\(logoURLResolver.isConfigured) url=\(logoURLResolver.redactedDescription(for: logoURL))"
            )
            let id = [account.id, position.id ?? position.instrument?.id ?? symbol]
                .joined(separator: "-")
            let dividendsReceived = dividendActivitiesByAccount[account.id].map {
                dividendAmount(
                    for: symbol,
                    currencyCode: currencyCode,
                    activities: $0
                )
            }

            return PortfolioHolding(
                id: id,
                accountID: account.id,
                symbol: symbol,
                name: name,
                instrumentKind: instrumentKind,
                logoURL: logoURL,
                accountName: account.name,
                quantity: units,
                quantityDisplay: position.unitsDisplay,
                averageCost: averageCost,
                currentPrice: currentPrice,
                previousClose: previousClose,
                currencyCode: currencyCode,
                dividendsReceived: dividendsReceived
            )
        }

        let holdingsWithPreparedLogoURL = holdings.lazy.filter { $0.logoURL != nil }.count
        debugLog(
            "loadPortfolio logoSummary configured=\(logoURLResolver.isConfigured) urlsPrepared=\(holdingsWithPreparedLogoURL)/\(holdings.count)"
        )
        debugLog("loadPortfolio completed accounts=\(accounts.count) holdings=\(holdings.count)")
        return PortfolioSnapshot.make(
            accounts: accounts,
            holdings: holdings,
            lastUpdated: Date(),
            isDemo: false
        )
    }

    func refreshPrices(for snapshot: PortfolioSnapshot) async throws -> PortfolioSnapshot {
        let quoteRequests = snapshot.holdings.map {
            YahooQuoteRequest(
                symbol: $0.symbol,
                instrumentKind: $0.instrumentKind
            )
        }
        let normalizedSymbols = Array(Set(quoteRequests.map { normalized($0.symbol) })).sorted()
        debugLog(
            "refreshPrices started holdings=\(snapshot.holdings.count) uniqueSymbols=\(normalizedSymbols.count) symbols=\(normalizedSymbols.joined(separator: ",")) taskCancelled=\(Task.isCancelled)"
        )

        let quotes: [String: YahooQuoteDTO]
        do {
            quotes = try await YahooFinanceClient().quotes(for: quoteRequests)
        } catch {
            debugLog("refreshPrices quote request failed \(debugDescription(for: error))")
            quotes = [:]
        }

        let quoteSymbols = quotes.keys.sorted()
        let missingSymbols = normalizedSymbols.filter { quotes[$0] == nil }
        debugLog(
            "refreshPrices quote summary succeeded=\(quoteSymbols.count)/\(normalizedSymbols.count) quoteSymbols=\(logList(quoteSymbols)) missingSymbols=\(logList(missingSymbols))"
        )

        let updatedHoldings = snapshot.holdings.map { holding -> PortfolioHolding in
            let symbol = normalized(holding.symbol)
            let quote = quotes[symbol]
            let currentPrice = quote?.regularMarketPrice.flatMap { $0 > 0 ? $0 : nil }
            let previousClose = quote?.regularMarketPreviousClose

            debugLog(
                "refreshPrices holding symbol=\(symbol) quoteFound=\(quote != nil) oldPrice=\(logValue(holding.currentPrice)) newPrice=\(logValue(currentPrice)) oldPreviousClose=\(logValue(holding.previousClose)) newPreviousClose=\(logValue(previousClose))"
            )

            return PortfolioHolding(
                id: holding.id,
                accountID: holding.accountID,
                symbol: holding.symbol,
                name: holding.name,
                instrumentKind: holding.instrumentKind,
                logoURL: holding.logoURL,
                accountName: holding.accountName,
                quantity: holding.quantity,
                quantityDisplay: holding.quantityDisplay,
                averageCost: holding.averageCost,
                currentPrice: currentPrice,
                previousClose: previousClose,
                currencyCode: holding.currencyCode,
                dividendsReceived: holding.dividendsReceived
            )
        }

        return PortfolioSnapshot.make(
            accounts: snapshot.accounts,
            holdings: updatedHoldings,
            lastUpdated: Date(),
            isDemo: snapshot.isDemo
        )
    }

    private func loadAccountSources(from snapTrade: SnapTradeClient) async throws -> [AccountSource] {
        debugLog("loadAccountSources started taskCancelled=\(Task.isCancelled)")
        do {
            let connections = try await snapTrade.listConnections()
            debugLog("loadAccountSources connections=\(connections.count)")
            guard !connections.isEmpty else {
                let accounts = try await snapTrade.listAccounts().map {
                    AccountSource(account: $0, connection: nil)
                }
                debugLog("loadAccountSources fallback accounts=\(accounts.count)")
                return accounts
            }

            return try await withThrowingTaskGroup(
                of: [AccountSource].self,
                returning: [AccountSource].self
            ) { group in
                for connection in connections {
                    group.addTask {
                        if let accounts = try? await snapTrade.listAccounts(connectionID: connection.id) {
                            return accounts.map { AccountSource(account: $0, connection: connection) }
                        }
                        return []
                    }
                }

                var sources: [AccountSource] = []
                for try await batch in group {
                    sources.append(contentsOf: batch)
                    debugLog("loadAccountSources collected batch=\(batch.count) total=\(sources.count)")
                }
                return sources
            }
        } catch {
            debugLog("loadAccountSources failed primary path \(debugDescription(for: error)); trying accounts fallback")
            let accounts = try await snapTrade.listAccounts().map {
                AccountSource(account: $0, connection: nil)
            }
            debugLog("loadAccountSources fallback after failure accounts=\(accounts.count)")
            return accounts
        }
    }

    private func loadDividendActivitiesByAccount(
        accounts: [PortfolioAccount],
        snapTrade: SnapTradeClient
    ) async -> [String: [SnapTradeActivityDTO]] {
        debugLog("loadDividendActivities started accounts=\(accounts.count) taskCancelled=\(Task.isCancelled)")
        return await withTaskGroup(
            of: (String, [SnapTradeActivityDTO])?.self,
            returning: [String: [SnapTradeActivityDTO]].self
        ) { group in
            for account in accounts {
                group.addTask { [dividendActivityTypes] in
                    if let activities = try? await snapTrade.listActivities(
                        accountID: account.id,
                        types: []
                    ) {
                        let filtered = activities.filter { activity in
                            guard let type = activity.type?.uppercased() else { return false }
                            return dividendActivityTypes.contains(type)
                        }
                        return (account.id, filtered)
                    }
                    return nil
                }
            }

            var result: [String: [SnapTradeActivityDTO]] = [:]
            for await pair in group {
                if let (accountID, activities) = pair {
                    result[accountID] = activities
                    debugLog("loadDividendActivities collected accountActivities=\(activities.count) accountCount=\(result.count)")
                }
            }
            return result
        }
    }

    private func dividendAmount(
        for symbol: String,
        currencyCode: String,
        activities: [SnapTradeActivityDTO]
    ) -> Double {
        let normalizedSymbol = normalized(symbol)
        let normalizedCurrencyCode = currencyCode.uppercased()

        return activities.reduce(0) { total, activity in
            guard let activitySymbol = activity.resolvedSymbol.map(normalized),
                  activitySymbol == normalizedSymbol,
                  let amount = activity.amount
            else {
                return total
            }

            if let activityCurrency = activity.currency?.uppercased(),
               activityCurrency != normalizedCurrencyCode {
                return total
            }

            return total + max(amount, 0)
        }
    }

    private func normalized(_ symbol: String) -> String {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func logList(_ values: [String]) -> String {
        values.isEmpty ? "[]" : "[\(values.joined(separator: ","))]"
    }

    private func logValue(_ value: Double?) -> String {
        value.map { String($0) } ?? "nil"
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[LivePortfolioRepository] \(message)")
        #endif
    }

    private func debugDescription(for error: Error) -> String {
        let nsError = error as NSError
        return "type=\(type(of: error)) domain=\(nsError.domain) code=\(nsError.code) taskCancelled=\(Task.isCancelled) message=\"\(error.localizedDescription)\""
    }
}

private struct AccountSource {
    let account: SnapTradeAccountDTO
    let connection: SnapTradeConnectionDTO?
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
