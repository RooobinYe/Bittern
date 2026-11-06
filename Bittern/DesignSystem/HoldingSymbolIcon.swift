//
//  HoldingSymbolIcon.swift
//  Bittern
//

import SwiftUI

/// A holding's logo on a colored disc, or the start of its symbol when there
/// is no logo.
struct HoldingSymbolIcon: View {
    let symbol: String
    let logoURL: URL?
    let color: Color
    let size: CGFloat
    var fallbackLabel: String? = nil
    var fallbackFont: Font = .caption.bold()
    var fallbackForegroundColor: Color = .white

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

            LogoImage(name: symbol, url: logoURL) { image in
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .background(Color.white)
            } placeholder: {
                Color.clear
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
            .minimumScaleFactor(0.5)
            .frame(width: size, height: size)
    }
}
