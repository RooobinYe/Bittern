//
//  DesignSystem.swift
//  Bittern
//

import SwiftUI
import UIKit

enum BitternTheme {
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let ink = Color(uiColor: .label)
    static let secondaryInk = Color(uiColor: .secondaryLabel)
    static let softLine = Color(uiColor: .separator)
    static let gain = Color(uiColor: .systemGreen)
    static let loss = Color(uiColor: .systemPink)
    static let blue = Color(uiColor: .systemTeal)
    static let gold = Color(uiColor: .systemYellow)

    static let allocationColors = [
        Color(uiColor: .systemTeal),
        Color(uiColor: .systemIndigo),
        Color(uiColor: .systemMint),
        Color(uiColor: .systemOrange),
        Color(uiColor: .systemGreen),
        Color(uiColor: .systemBlue),
        Color(uiColor: .systemRed),
        Color(uiColor: .systemPurple)
    ]

    static func performanceColor(_ value: Double) -> Color {
        if value > 0 {
            return gain
        }

        if value < 0 {
            return loss
        }

        return secondaryInk
    }

    static func performanceColor(_ value: Double?) -> Color {
        guard let value else { return secondaryInk }
        return performanceColor(value)
    }
}

struct PanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(BitternTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BitternTheme.softLine.opacity(0.65), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func bitternPanel() -> some View {
        modifier(PanelModifier())
    }
}
