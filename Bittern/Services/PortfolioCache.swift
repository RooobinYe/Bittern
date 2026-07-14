//
//  PortfolioCache.swift
//  Bittern
//

import Foundation
import OSLog

enum PortfolioCache {
    private nonisolated static let fileName = "portfolio_cache.json"

    private nonisolated static var cacheURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName)
    }

    nonisolated static func save(_ snapshot: PortfolioSnapshot) {
        guard let url = cacheURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            AppLog.persistence.error(
                "Cache save failed: \(AppLog.describe(error))"
            )
        }
    }

    nonisolated static func load() -> PortfolioSnapshot? {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            let snapshot = try JSONDecoder().decode(PortfolioSnapshot.self, from: data)
            return snapshot
        } catch {
            AppLog.persistence.error(
                "Cache load failed: \(AppLog.describe(error))"
            )
            return nil
        }
    }

    nonisolated static func loadAsync() async -> PortfolioSnapshot? {
        await Task.detached {
            load()
        }.value
    }
}
