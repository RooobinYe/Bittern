//
//  HoldingSymbolIcon.swift
//  Bittern
//

import Foundation
import SwiftUI
import UIKit

struct HoldingSymbolIcon: View {
    let symbol: String
    let logoURL: URL?
    let color: Color
    let size: CGFloat
    var fallbackLabel: String? = nil
    var fallbackFont: Font = .caption.bold()
    var borderColor: Color? = nil
    var borderWidth: CGFloat = 0

    private var label: String {
        if let fallbackLabel {
            return fallbackLabel
        }
        let prefix = String(symbol.prefix(4))
        return prefix.isEmpty ? "?" : prefix
    }

    var body: some View {
        ZStack {
            Circle().fill(color)
            fallback

            if let logoURL {
                RemoteLogoImage(
                    symbol: symbol,
                    url: logoURL,
                    size: size
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if let borderColor, borderWidth > 0 {
                Circle().stroke(borderColor, lineWidth: borderWidth)
            }
        }
    }

    private var fallback: some View {
        Text(label)
            .font(fallbackFont)
            .foregroundStyle(BitternTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .frame(width: size, height: size)
    }
}

private struct RemoteLogoImage: View {
    let symbol: String
    let url: URL
    let size: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .background(Color.white)
                    .clipShape(Circle())
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        image = nil
        debugLogoLoad(
            "requested symbol=\(symbol) url=\(redactedLogoURLDescription(url))"
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
            logoImageUserAgent,
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LogoImageLoadingError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw LogoImageLoadingError.httpStatus(
                    httpResponse.statusCode,
                    httpResponse.mimeType
                )
            }
            guard let mimeType = httpResponse.mimeType,
                  mimeType.lowercased().hasPrefix("image/")
            else {
                throw LogoImageLoadingError.invalidContentType(
                    httpResponse.mimeType
                )
            }
            guard let decodedImage = UIImage(data: data) else {
                throw LogoImageLoadingError.invalidImageData
            }

            image = decodedImage
            let contentType = httpResponse.value(
                forHTTPHeaderField: "Content-Type"
            ) ?? mimeType
            let pixelWidth = decodedImage.cgImage?.width
                ?? Int(decodedImage.size.width * decodedImage.scale)
            let pixelHeight = decodedImage.cgImage?.height
                ?? Int(decodedImage.size.height * decodedImage.scale)
            debugLogoLoad(
                "succeeded symbol=\(symbol) status=\(httpResponse.statusCode) contentType=\(contentType) pixels=\(pixelWidth)x\(pixelHeight) bytes=\(data.count) url=\(redactedLogoURLDescription(url))"
            )
        } catch is CancellationError {
            return
        } catch {
            image = nil
            debugLogoLoad(
                "failed symbol=\(symbol) error=\(logoImageErrorDescription(error)) url=\(redactedLogoURLDescription(url))"
            )
        }
    }
}

private enum LogoImageLoadingError: Error {
    case invalidResponse
    case httpStatus(Int, String?)
    case invalidContentType(String?)
    case invalidImageData
}

private func redactedLogoURLDescription(_ url: URL) -> String {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.query = nil
    return components?.url?.absoluteString ?? "<invalid-url>"
}

private var logoImageUserAgent: String {
    let appVersion = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "1"
    let deviceFamily = UIDevice.current.userInterfaceIdiom == .pad
        ? "iPad"
        : "iPhone"
    return "Bittern/\(appVersion) (\(deviceFamily); iOS \(UIDevice.current.systemVersion))"
}

private func logoImageErrorDescription(_ error: Error) -> String {
    if let loadingError = error as? LogoImageLoadingError {
        switch loadingError {
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

private func debugLogoLoad(_ message: String) {
    #if DEBUG
    print("[HoldingLogoImage] \(message)")
    #endif
}
