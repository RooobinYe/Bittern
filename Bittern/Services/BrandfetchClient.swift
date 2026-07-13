//
//  BrandfetchClient.swift
//  Bittern
//

import Foundation
import OSLog
import UIKit

enum BrandfetchConfiguration {
    /// Brandfetch Client IDs are publishable client-side identifiers.
    static let clientID = "1idKAz8xUOgn2MTMDXK"
}

struct BrandfetchClient {
    private let clientID: String?
    private let session: URLSession

    var isConfigured: Bool {
        clientID != nil
    }

    init(
        clientID: String? = nil,
        session: URLSession = .shared
    ) {
        let configuredClientID = clientID ?? BrandfetchConfiguration.clientID
        let normalizedClientID = configuredClientID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientID = normalizedClientID.isEmpty ? nil : normalizedClientID
        self.session = session
    }

    func logoURL(for symbol: String, kind: PortfolioInstrumentKind?) -> URL? {
        guard let clientID,
              let endpoint = endpoint(for: kind)
        else {
            return nil
        }

        let normalizedSymbol = symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedSymbol.isEmpty else { return nil }

        let baseURL = URL(string: "https://cdn.brandfetch.io")!
            .appendingPathComponent(endpoint)
            .appendingPathComponent(normalizedSymbol)
            .appendingPathComponent("h")
            .appendingPathComponent("256")
            .appendingPathComponent("w")
            .appendingPathComponent("256")
            .appendingPathComponent("icon.png")
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "c", value: clientID)
        ]
        return components?.url
    }

    func image(for symbol: String, at url: URL) async throws -> UIImage {
        AppLog.images.debug(
            "Logo requested symbol=\(symbol) url=\(redactedDescription(for: url))"
        )

        var request = URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 15
        )
        request.setValue(
            "image/png,image/*;q=0.8",
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
                throw BrandfetchError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw BrandfetchError.httpStatus(
                    httpResponse.statusCode,
                    httpResponse.mimeType
                )
            }
            guard let mimeType = httpResponse.mimeType,
                  mimeType.lowercased().hasPrefix("image/")
            else {
                throw BrandfetchError.invalidContentType(httpResponse.mimeType)
            }
            guard let image = UIImage(data: data) else {
                throw BrandfetchError.invalidImageData
            }

            let contentType = httpResponse.value(
                forHTTPHeaderField: "Content-Type"
            ) ?? mimeType
            let pixelWidth = image.cgImage?.width
                ?? Int(image.size.width * image.scale)
            let pixelHeight = image.cgImage?.height
                ?? Int(image.size.height * image.scale)
            AppLog.images.debug(
                "Logo succeeded symbol=\(symbol) status=\(httpResponse.statusCode, privacy: .public) contentType=\(contentType, privacy: .public) pixels=\(pixelWidth, privacy: .public)x\(pixelHeight, privacy: .public) bytes=\(data.count, privacy: .public) url=\(redactedDescription(for: url))"
            )
            return image
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.images.warning(
                "Logo failed symbol=\(symbol) error=\(errorDescription(error), privacy: .public) url=\(redactedDescription(for: url))"
            )
            throw error
        }
    }

    func redactedDescription(for url: URL?) -> String {
        guard let url else { return "nil" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        return components?.url?.absoluteString ?? "<invalid-url>"
    }

    private func endpoint(for kind: PortfolioInstrumentKind?) -> String? {
        switch kind {
        case .stock, .etf, .mutualFund, .adr, .closedEndFund:
            return "ticker"
        case .crypto:
            return "crypto"
        case .future, .option, .cfd, .other, nil:
            return nil
        }
    }

    private var userAgent: String {
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1"
        let deviceFamily = UIDevice.current.userInterfaceIdiom == .pad
            ? "iPad"
            : "iPhone"
        return "Bittern/\(appVersion) (\(deviceFamily); iOS \(UIDevice.current.systemVersion))"
    }

    private func errorDescription(_ error: Error) -> String {
        if let brandfetchError = error as? BrandfetchError {
            switch brandfetchError {
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

private enum BrandfetchError: Error {
    case invalidResponse
    case httpStatus(Int, String?)
    case invalidContentType(String?)
    case invalidImageData
}
