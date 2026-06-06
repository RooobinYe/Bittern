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
            return try JSONDecoder().decode(PortfolioSnapshot.self, from: data)
        } catch {
            print("[PortfolioCache] load failed: \(error)")
            return nil
        }
    }
}
