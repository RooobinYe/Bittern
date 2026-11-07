//
//  BitternTheme.swift
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
    /// A chart line that is neither gain nor loss. Opaque, unlike
    /// `secondaryInk`: where two runs of a line meet, their round ends
    /// overlap, and a see-through color shows a darker dot there.
    static let neutralLine = Color(uiColor: .systemGray)
    static let accent = Color.accentColor
    /// Darker than `systemGreen` and `systemRed` in light mode so gains and
    /// losses read at 4.5:1 on white; the system colors in dark mode.
    static let positivePerformance = Color(.positivePerformance)
    static let negativePerformance = Color(.negativePerformance)
    static let warning = Color(uiColor: .systemOrange)

    /// A holding the allocation leaves out, having no value to share.
    static let unallocatedHoldingColor = Color(uiColor: .systemGray3)

    /// Each holding's color: its band's in the allocation card of
    /// `holdings`, so a holding without a logo wears its band's color.
    /// Holdings in the small-holdings band share its color. Holdings the card
    /// leaves out are missing; callers show `unallocatedHoldingColor`.
    ///
    /// Colors follow rank, so pass the holdings whose allocation the screen
    /// is about: a holding's color changes when it overtakes another.
    static func holdingAllocationColors(
        for holdings: [PortfolioHolding]
    ) -> [String: Color] {
        let slices = PortfolioAllocation.slices(of: holdings)
        var colorsByHoldingID: [String: Color] = [:]
        var otherColor: Color?

        for (slice, color) in zip(slices, allocationBandColors(count: slices.count)) {
            switch slice.kind {
            case .holding(let holding):
                colorsByHoldingID[holding.id] = color
            case .other:
                otherColor = color
            }
        }

        if let otherColor {
            for holding in PortfolioAllocation.ordered(holdings) where colorsByHoldingID[holding.id] == nil {
                colorsByHoldingID[holding.id] = otherColor
            }
        }
        return colorsByHoldingID
    }

    static func holdingAllocationColor(
        for holding: PortfolioHolding,
        in holdings: [PortfolioHolding]
    ) -> Color {
        holdingAllocationColors(for: holdings)[holding.id] ?? unallocatedHoldingColor
    }

    /// The allocation card's bands, largest first: one smooth run from deep
    /// indigo through teal and green to a light yellow, so the stack reads as
    /// one palette. A band's color follows its rank, not its holding.
    static func allocationBandColors(count: Int) -> [Color] {
        guard count > 1 else { return count == 1 ? [allocationBandColor(at: 0)] : [] }
        return (0..<count).map { allocationBandColor(at: Double($0) / Double(count - 1)) }
    }

    /// The color `fraction` of the way along the band ramp, in OKLCH.
    private static func allocationBandColor(at fraction: Double) -> Color {
        let t = min(max(fraction, 0), 1)
        let lightness = 0.42 + (0.90 - 0.42) * t
        let chroma = 0.15 + (0.17 - 0.15) * t
        let hue = (280 - (280 - 105) * t) * .pi / 180

        let a = chroma * cos(hue)
        let b = chroma * sin(hue)
        let l = pow(lightness + 0.396_337_777_4 * a + 0.215_803_757_3 * b, 3)
        let m = pow(lightness - 0.105_561_345_8 * a - 0.063_854_172_8 * b, 3)
        let s = pow(lightness - 0.089_484_177_5 * a - 1.291_485_548_0 * b, 3)
        // Linear sRGB, clipped to the gamut; Color applies the sRGB curve.
        func clip(_ value: Double) -> Double { min(max(value, 0), 1) }
        return Color(
            .sRGBLinear,
            red: clip(4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s),
            green: clip(-1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s),
            blue: clip(-0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701_0 * s)
        )
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

private struct ErrorToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(BitternTheme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                        .transition(
                            .move(edge: .top).combined(with: .opacity)
                        )
                        .task(id: message) {
                            AccessibilityNotification.Announcement(message).post()
                            try? await Task.sleep(for: .seconds(5))
                            guard !Task.isCancelled else { return }
                            self.message = nil
                        }
                }
            }
            .animation(.snappy, value: message)
    }
}

extension Font {
    /// A key figure (a total, price, change or allocation share) in SF Pro,
    /// like the rest of the app, with digits of even width so figures don't
    /// jump as they change.
    static func keyFigure(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, weight: weight).monospacedDigit()
    }
}

extension View {
    func errorToast(message: Binding<String?>) -> some View {
        modifier(ErrorToastModifier(message: message))
    }

    /// Fades content into the navigation bar instead of cutting it off with a
    /// line. Not the default whenever the navigation bar shows a title: on
    /// iOS 27 the automatic style then becomes a hard edge, and stays soft
    /// without a title. Adding a title to the holding detail made it hard;
    /// removing History's made it soft. Use this on every titled scroll screen.
    func softNavigationBarEdge() -> some View {
        scrollEdgeEffectStyle(.soft, for: .top)
    }
}
