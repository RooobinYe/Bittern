//
//  LogoClient.swift
//  Bittern
//
//  Fetches and decodes holding logos (TradingView SVGs, routed through the
//  configured MarketDataServer when configured) and brokerage logos (SnapTrade
//  raster images).
//

import Foundation
import OSLog
import SwiftDraw
import UIKit

nonisolated struct LogoClient: Sendable {
    private static let maximumRasterSize: CGFloat = 256

    private let session: URLSession
    private let serverStore: TradingViewServerStore
    private let cache: ImageCache
    private let userAgent: String

    @MainActor
    init(
        session: URLSession = .shared,
        serverStore: TradingViewServerStore = TradingViewServerStore()
    ) {
        self.init(
            session: session,
            serverStore: serverStore,
            userAgent: Self.defaultUserAgent()
        )
    }

    init(
        session: URLSession = .shared,
        serverStore: TradingViewServerStore = TradingViewServerStore(),
        userAgent: String
    ) {
        self.session = session
        self.serverStore = serverStore
        self.cache = ImageCache()
        self.userAgent = userAgent
    }

    func image(for name: String, at url: URL) async throws -> UIImage {
        if let cached = cache[url] {
            return cached
        }

        let requestURL = serverStore.server.logoRequestURL(for: url) ?? url
        let image = try await fetchImage(for: name, at: requestURL)
        cache[url] = image
        return image
    }

    func redactedDescription(for url: URL?) -> String {
        guard let url else { return "nil" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        return components?.url?.absoluteString ?? "<invalid-url>"
    }

    private func fetchImage(for name: String, at url: URL) async throws -> UIImage {
        AppLog.images.debug(
            "Logo requested name=\(name) url=\(redactedDescription(for: url))"
        )

        var request = URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 15
        )
        request.setValue(
            "image/svg+xml,image/png,image/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            userAgent,
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LogoClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw LogoClientError.httpStatus(
                    httpResponse.statusCode,
                    httpResponse.mimeType
                )
            }
            guard let mimeType = httpResponse.mimeType,
                  mimeType.lowercased().hasPrefix("image/")
            else {
                throw LogoClientError.invalidContentType(httpResponse.mimeType)
            }

            let decoded = await Task.detached(priority: .userInitiated) {
                Self.decodeImage(data: data, mimeType: mimeType, url: url)
            }.value

            guard let image = decoded else {
                throw LogoClientError.invalidImageData
            }

            let contentType = httpResponse.value(
                forHTTPHeaderField: "Content-Type"
            ) ?? mimeType
            let pixelWidth = image.cgImage?.width
                ?? Int(image.size.width * image.scale)
            let pixelHeight = image.cgImage?.height
                ?? Int(image.size.height * image.scale)
            AppLog.images.debug(
                "Logo succeeded name=\(name) status=\(httpResponse.statusCode, privacy: .public) contentType=\(contentType, privacy: .public) pixels=\(pixelWidth, privacy: .public)x\(pixelHeight, privacy: .public) bytes=\(data.count, privacy: .public) url=\(redactedDescription(for: url))"
            )
            return image
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.images.warning(
                "Logo failed name=\(name) error=\(errorDescription(error), privacy: .public) url=\(redactedDescription(for: url))"
            )
            throw error
        }
    }

    private static func decodeImage(data: Data, mimeType: String, url: URL) -> UIImage? {
        if mimeType.lowercased().contains("svg") || url.pathExtension.lowercased() == "svg" {
            guard let svg = SVG(data: data),
                  svg.size.width > 0, svg.size.height > 0,
                  svg.size.width.isFinite, svg.size.height.isFinite
            else {
                return nil
            }
            let longest = max(svg.size.width, svg.size.height)
            let targetSize = CGSize(
                width: max((svg.size.width / longest * maximumRasterSize).rounded(), 1),
                height: max((svg.size.height / longest * maximumRasterSize).rounded(), 1)
            )
            // Always pass an explicit scale so SwiftDraw never reads UIScreen.main.scale via DispatchQueue.main.sync.
            return svg.rasterize(size: targetSize, scale: 1)
        }
        return UIImage(data: data)
    }

    @MainActor
    private static func defaultUserAgent() -> String {
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1"
        let deviceFamily = UIDevice.current.userInterfaceIdiom == .pad
            ? "iPad"
            : "iPhone"
        return "Bittern/\(appVersion) (\(deviceFamily); iOS \(UIDevice.current.systemVersion))"
    }

    private func errorDescription(_ error: Error) -> String {
        if let logoError = error as? LogoClientError {
            switch logoError {
            case .invalidResponse:
                return "invalid-response"
            case .httpStatus(let statusCode, let mimeType):
                return "http-status=\(statusCode) mime=\(mimeType ?? "nil")"
            case .invalidContentType(let mimeType):
                return "invalid-content-type=\(mimeType ?? "nil")"
            case .invalidImageData:
                return "invalid-image-data"
            }
        }

        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code)"
    }
}

private nonisolated final class ImageCache: @unchecked Sendable {
    private let storage: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 128
        return cache
    }()

    subscript(url: URL) -> UIImage? {
        get { storage.object(forKey: url as NSURL) }
        set {
            if let newValue {
                storage.setObject(newValue, forKey: url as NSURL)
            } else {
                storage.removeObject(forKey: url as NSURL)
            }
        }
    }
}

nonisolated enum LogoClientError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case invalidContentType(String?)
    case invalidImageData
}
