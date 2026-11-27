//
//  LogoCache.swift
//  Bittern
//
//  Persists rasterized logo PNGs under Application Support so cold launches
//  can warm them straight into memory without hitting the network or re-parsing
//  SVGs.
//

import CryptoKit
import Foundation
import OSLog
import UIKit

nonisolated struct LogoDiskCache: Sendable {
    let directoryURL: URL?

    static let live = LogoDiskCache(directoryURL: defaultDirectoryURL)
    static let disabled = LogoDiskCache(directoryURL: nil)

    private static var defaultDirectoryURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LogoCache", isDirectory: true)
    }

    func fileURL(for url: URL) -> URL? {
        guard let directoryURL else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent("\(name).png", isDirectory: false)
    }

    func load(for url: URL) -> UIImage? {
        guard let fileURL = fileURL(for: url),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data, scale: 1)
        else {
            return nil
        }
        return image.preparingForDisplay() ?? image
    }

    func save(_ image: UIImage, for url: URL) {
        guard let directoryURL,
              let fileURL = fileURL(for: url),
              let data = image.pngData()
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)

            var target = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try target.setResourceValues(values)
        } catch {
            AppLog.images.warning(
                "Logo disk cache write failed: \(AppLog.describe(error))"
            )
        }
    }
}
