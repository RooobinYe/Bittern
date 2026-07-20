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
    var fallbackForegroundColor: Color = .white
    @Environment(\.isRenderingScreenshot) private var isRenderingScreenshot
    @Environment(\.screenshotLogoData) private var screenshotLogoData

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

            if let logoURL,
               let logoData = screenshotLogoData[logoURL],
               let image = UIImage(data: logoData) {
                HoldingLogoBitmap(image: image, size: size)
            } else if let logoURL, !isRenderingScreenshot {
                RemoteLogoImage(
                    symbol: symbol,
                    url: logoURL,
                    size: size
                )
            }
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .clipShape(Circle())
    }

    private var fallback: some View {
        Text(label)
            .font(fallbackFont)
            .foregroundStyle(fallbackForegroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .frame(width: size, height: size)
    }
}

private struct HoldingLogoBitmap: View {
    let image: UIImage
    let size: CGFloat

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .background(Color.white)
    }
}

private struct RemoteLogoImage: View {
    let symbol: String
    let url: URL
    let size: CGFloat

    @State private var image: UIImage?
    private let brandfetch = BrandfetchClient()

    var body: some View {
        Group {
            if let image {
                HoldingLogoBitmap(image: image, size: size)
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

        do {
            image = try await brandfetch.image(for: symbol, at: url)
        } catch is CancellationError {
            return
        } catch {
            image = nil
        }
    }
}
