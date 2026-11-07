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

    @Environment(\.self) private var environment

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
            .foregroundStyle(color.contrastingForeground(in: environment))
            .lineLimit(1)
            // Four letters on a disc sized for the symbol's logo: shrinking
            // them is the only way they stay inside the circle.
            .minimumScaleFactor(0.5)
            .padding(.horizontal, size * 0.06)
            .frame(width: size, height: size)
    }

}

extension Color {
    /// Black or white, whichever reads better on this color as it looks in
    /// `environment`.
    func contrastingForeground(in environment: EnvironmentValues) -> Color {
        let resolved = resolve(in: environment)
        let luminance = ContrastingForeground.relativeLuminance(
            linearRed: Double(resolved.linearRed),
            linearGreen: Double(resolved.linearGreen),
            linearBlue: Double(resolved.linearBlue)
        )
        switch ContrastingForeground.preferred(onLuminance: luminance) {
        case .black:
            return .black
        case .white:
            return .white
        }
    }
}

/// Black or white text, whichever contrasts more with a background.
nonisolated enum ContrastingForeground: Equatable {
    case black
    case white

    /// WCAG relative luminance from linear sRGB components.
    static func relativeLuminance(linearRed: Double, linearGreen: Double, linearBlue: Double) -> Double {
        0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue
    }

    static func contrastRatio(_ lhs: Double, _ rhs: Double) -> Double {
        (max(lhs, rhs) + 0.05) / (min(lhs, rhs) + 0.05)
    }

    static func preferred(onLuminance luminance: Double) -> ContrastingForeground {
        contrastRatio(luminance, 0) > contrastRatio(luminance, 1) ? .black : .white
    }
}
