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
            let data = try JSONEncoder().encode(snapshot)
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
            return PortfolioSnapshot.make(
                accounts: snapshot.accounts,
                holdings: snapshot.holdings,
                lastUpdated: snapshot.lastUpdated,
                isDemo: snapshot.isDemo
            )
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
