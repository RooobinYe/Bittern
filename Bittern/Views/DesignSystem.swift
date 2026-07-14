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
    static let accent = Color.accentColor
    static let positivePerformance = Color(uiColor: .systemGreen)
    static let negativePerformance = Color(uiColor: .systemRed)
    static let warning = Color(uiColor: .systemOrange)

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

    static func allocationColor(at index: Int) -> Color {
        allocationColors[index % allocationColors.count]
    }

    static func holdingAllocationColors(
        for holdings: [PortfolioHolding]
    ) -> [String: Color] {
        Dictionary(
            uniqueKeysWithValues: sortedAllocationHoldings(holdings)
                .enumerated()
                .map { index, holding in
                    (holding.id, allocationColor(at: index))
                }
        )
    }

    static func holdingAllocationColor(
        for holding: PortfolioHolding,
        in holdings: [PortfolioHolding]
    ) -> Color {
        holdingAllocationColors(for: holdings)[holding.id]
            ?? allocationColor(at: 0)
    }

    static func sortedAllocationHoldings(
        _ holdings: [PortfolioHolding]
    ) -> [PortfolioHolding] {
        holdings
            .filter { ($0.marketValue ?? 0) > 0 }
            .sorted { lhs, rhs in
                if lhs.marketValue != rhs.marketValue {
                    return (lhs.marketValue ?? 0) > (rhs.marketValue ?? 0)
                }

                if lhs.symbol != rhs.symbol {
                    return lhs.symbol < rhs.symbol
                }

                return lhs.id < rhs.id
            }
    }

    static func performanceColor(_ value: Double) -> Color {
        if value > 0 {
            return positivePerformance
        }

        if value < 0 {
            return negativePerformance
        }

        return secondaryInk
    }

    static func performanceColor(_ value: Double?) -> Color {
        guard let value else { return secondaryInk }
        return performanceColor(value)
    }
}

struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(BitternTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BitternTheme.softLine.opacity(0.65), lineWidth: 1)
            }
    }
}

private struct ErrorToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BitternTheme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                        .transition(
                            .move(edge: .top).combined(with: .opacity)
                        )
                        .task(id: message) {
                            try? await Task.sleep(for: .seconds(5))
                            guard !Task.isCancelled else { return }
                            self.message = nil
                        }
                }
            }
            .animation(.snappy, value: message)
    }
}

extension View {
    func bitternPanel() -> some View {
        modifier(PanelModifier())
    }

    func errorToast(message: Binding<String?>) -> some View {
        modifier(ErrorToastModifier(message: message))
    }
}
