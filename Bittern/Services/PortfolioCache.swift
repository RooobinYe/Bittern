//
//  PortfolioCache.swift
//  Bittern
//

import Foundation
import OSLog

enum PortfolioCache {
    private nonisolated static let fileName = "portfolio_cache.json"

    /// The persisted snapshot is the only portfolio data available when the
    /// network or SnapTrade is unreachable, so it lives in Application Support
    /// rather than Caches: iOS reclaims `Library/Caches` while an app sits
    /// unused, which leaves a cold launch with nothing to show but zeroes.
    private nonisolated static var directoryURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
    }

    private nonisolated static var storeURL: URL? {
        directoryURL?.appendingPathComponent(fileName)
    }

    private nonisolated static var legacyCacheURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName)
    }

    nonisolated static func save(_ snapshot: PortfolioSnapshot) {
        guard let storeURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try writeStore(data, to: storeURL)
        } catch {
            AppLog.persistence.error(
                "Cache save failed: \(AppLog.describe(error))"
            )
        }
    }

    nonisolated static func load() -> PortfolioSnapshot? {
        guard let data = readData() else {
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

    /// Removes the snapshot and any pre-migration copy. A missing file is
    /// already the desired state; every other failure reaches the caller so
    /// holdings are never silently left on disk.
    nonisolated static func clear() throws {
        for url in [storeURL, legacyCacheURL].compactMap({ $0 }) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                continue
            }
        }
    }

    /// Reads the current store, falling back once to the pre-migration Caches
    /// copy so upgrading does not start from an empty portfolio.
    private nonisolated static func readData() -> Data? {
        if let storeURL, let data = try? Data(contentsOf: storeURL) {
            return data
        }

        guard let legacyCacheURL,
              let data = try? Data(contentsOf: legacyCacheURL) else {
            return nil
        }

        migrateFromLegacyCache(data, at: legacyCacheURL)
        return data
    }

    private nonisolated static func migrateFromLegacyCache(
        _ data: Data,
        at legacyURL: URL
    ) {
        guard let storeURL else { return }
        do {
            try writeStore(data, to: storeURL)
            try? FileManager.default.removeItem(at: legacyURL)
            AppLog.persistence.debug(
                "Migrated snapshot out of the caches directory"
            )
        } catch {
            AppLog.persistence.error(
                "Cache migration failed: \(AppLog.describe(error))"
            )
        }
    }

    /// Keeps holdings out of iCloud and device backups. An atomic write replaces
    /// the file and loses the exclusion, so it is reapplied after every write.
    private nonisolated static func writeStore(_ data: Data, to url: URL) throws {
        try prepareDirectory()
        try data.write(to: url, options: .atomic)

        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Application Support is not created for us the way Caches is.
    private nonisolated static func prepareDirectory() throws {
        guard let directoryURL else { return }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }
}
