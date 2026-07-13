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
    private let brandfetch = BrandfetchClient()

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

        do {
            image = try await brandfetch.image(for: symbol, at: url)
        } catch is CancellationError {
            return
        } catch {
            image = nil
        }
    }
}
