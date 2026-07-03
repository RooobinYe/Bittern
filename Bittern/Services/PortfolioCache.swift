//
//  PortfolioCache.swift
//  Bittern
//

import Foundation

enum PortfolioCache {
    private static let fileName = "portfolio_cache.json"

    private static var cacheURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName)
    }

    static func save(_ snapshot: PortfolioSnapshot) {
        guard let url = cacheURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot.removingYahooPricing())
            try data.write(to: url, options: .atomic)
        } catch {
            print("[PortfolioCache] save failed: \(error)")
        }
    }

    static func load() -> PortfolioSnapshot? {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            let snapshot = try JSONDecoder().decode(PortfolioSnapshot.self, from: data)
            return snapshot.removingYahooPricing()
        } catch {
            print("[PortfolioCache] load failed: \(error)")
            return nil
        }
    }

    static func loadAsync() async -> PortfolioSnapshot? {
        await Task.detached {
            load()
        }.value
    }
}

private extension PortfolioSnapshot {
    func removingYahooPricing() -> PortfolioSnapshot {
        let holdingsWithoutPrices = holdings.map { holding in
            PortfolioHolding(
                id: holding.id,
                accountID: holding.accountID,
                symbol: holding.symbol,
                name: holding.name,
                accountName: holding.accountName,
                quantity: holding.quantity,
                quantityDisplay: holding.quantityDisplay,
                averageCost: holding.averageCost,
                currentPrice: nil,
                previousClose: nil,
                currencyCode: holding.currencyCode,
                dividendsReceived: holding.dividendsReceived
            )
        }

        return PortfolioSnapshot.make(
            accounts: accounts,
            holdings: holdingsWithoutPrices,
            lastUpdated: lastUpdated,
            isDemo: isDemo
        )
    }
}
