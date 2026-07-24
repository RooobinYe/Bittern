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

    static let allocationColors: [Color] = [
        mutedAllocationColor(.systemIndigo),
        mutedAllocationColor(.systemOrange),
        mutedAllocationColor(.systemGreen),
        mutedAllocationColor(.systemTeal),
        mutedAllocationColor(.systemBlue),
        mutedAllocationColor(.systemRed),
        mutedAllocationColor(.systemPurple),
        mutedAllocationColor(.systemMint),
        mutedAllocationColor(.systemPink),
        mutedAllocationColor(.systemBrown),
        mutedAllocationColor(.systemCyan),
        mutedAllocationColor(.systemYellow)
    ]

    private static let allocationNeutral = Color(uiColor: .systemGray)
    private static let allocationMuteFraction = 0.48

    private static func mutedAllocationColor(_ color: UIColor) -> Color {
        Color(uiColor: color).mix(
            with: allocationNeutral,
            by: allocationMuteFraction,
            in: .perceptual
        )
    }

    static func allocationColor(at index: Int) -> Color {
        allocationColors[index % allocationColors.count]
    }

    static func holdingAllocationColors(
        for holdings: [PortfolioHolding]
    ) -> [String: Color] {
        var usedIndices: Set<Int> = []
        var colorsByHoldingID: [String: Color] = [:]

        for holding in holdings.sorted(by: { $0.id < $1.id }) {
            guard colorsByHoldingID[holding.id] == nil else { continue }

            var index = allocationColorIndex(forStableKey: holding.id)
            if usedIndices.count < allocationColors.count {
                while usedIndices.contains(index) {
                    index = (index + 1) % allocationColors.count
                }
                usedIndices.insert(index)
            }

            colorsByHoldingID[holding.id] = allocationColor(at: index)
        }

        return colorsByHoldingID
    }

    static func holdingAllocationColor(
        for holding: PortfolioHolding,
        in holdings: [PortfolioHolding]
    ) -> Color {
        holdingAllocationColors(for: holdings)[holding.id]
            ?? allocationColor(forStableKey: holding.id)
    }

    static let otherAllocationColor = allocationColor(forStableKey: "OTHER")

    private static func allocationColor(forStableKey key: String) -> Color {
        allocationColor(at: allocationColorIndex(forStableKey: key))
    }

    private static func allocationColorIndex(forStableKey key: String) -> Int {
        // Swift's Hashable seed changes between launches, so use a
        // deterministic hash to keep each holding attached to one color.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }

        return Int(hash % UInt64(allocationColors.count))
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
