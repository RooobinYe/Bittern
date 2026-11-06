//
//  HoldingListRow.swift
//  Bittern
//

import SwiftUI

struct HoldingListRow: View {
    private struct ExtendedHoursPresentation {
        let change: HoldingExtendedHoursChange
        let systemImage: String
        let primaryColor: Color
        let secondaryColor: Color
        let accessibilityName: String
    }

    let holding: PortfolioHolding
    /// The holding's share of the shown portfolio, when known.
    let allocation: Double?
    let performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let color: Color
    let marketTime: Date

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var performanceAmount: Double? {
        holding.performanceAmount(for: performanceMode)
    }

    private var performancePercent: Double? {
        holding.performancePercent(for: performanceMode)
    }

    private var extendedHoursPresentation: ExtendedHoursPresentation? {
        if let change = holding.activePreMarketChange(at: marketTime) {
            return ExtendedHoursPresentation(
                change: change,
                systemImage: "sunrise.fill",
                primaryColor: .orange,
                secondaryColor: .yellow,
                accessibilityName: "Pre-market"
            )
        }

        if let change = holding.activePostMarketChange(at: marketTime) {
            return ExtendedHoursPresentation(
                change: change,
                systemImage: "sunset.fill",
                primaryColor: .indigo,
                secondaryColor: .orange,
                accessibilityName: "Post-market"
            )
        }

        return nil
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilitySizeLayout
            } else {
                standardLayout
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// One figure per line at accessibility text sizes, each with the whole
    /// width, so none is cut off. The logo would only take room from them.
    private var accessibilitySizeLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(holding.symbol)
                .font(.headline)
                .foregroundStyle(BitternTheme.ink)

            Text(marketValueText)
                .font(.keyFigure(.headline))
                .foregroundStyle(BitternTheme.ink)

            Text(performanceText)
                .font(.keyFigure(.subheadline))
                .foregroundStyle(BitternTheme.performanceColor(performanceAmount))

            if let extendedHoursPresentation {
                extendedHoursPerformanceLabel(extendedHoursPresentation)
            }

            Text(quantityAndAllocationText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(BitternTheme.secondaryInk)
        }
    }

    private var standardLayout: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 12) {
                HoldingSymbolIcon(
                    symbol: holding.symbol,
                    logoURL: holding.logoURL,
                    color: color,
                    size: iconSize
                )
                .accessibilityHidden(true)

                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(holding.symbol)
                            .font(.headline)
                            .foregroundStyle(BitternTheme.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        Text(marketValueText)
                            .font(.keyFigure(.headline))
                            .foregroundStyle(BitternTheme.ink)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    }

                    secondaryMetrics
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let extendedHoursPresentation {
                extendedHoursPerformanceLabel(extendedHoursPresentation)
            }
        }
    }

    private var secondaryMetrics: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(quantityAndAllocationText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(BitternTheme.secondaryInk)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(performanceText)
                .font(.keyFigure(.subheadline))
                .foregroundStyle(BitternTheme.performanceColor(performanceAmount))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func extendedHoursPerformanceLabel(
        _ presentation: ExtendedHoursPresentation
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: presentation.systemImage)
                .font(.caption)
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    presentation.primaryColor,
                    presentation.secondaryColor
                )
                .accessibilityHidden(true)

            Text(changeText(amount: presentation.change.amount, percent: presentation.change.percent))
                .font(.keyFigure(.caption))
                .foregroundStyle(
                    BitternTheme.performanceColor(presentation.change.amount)
                )
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(presentation.accessibilityName) \(changeText(amount: presentation.change.amount, percent: presentation.change.percent))"
        )
    }

    private var quantityAndAllocationText: String {
        let allocationText = allocation.map { PortfolioFormat.percent($0) } ?? PortfolioFormat.missing
        guard !isPrivacyEnabled else { return allocationText }

        let quantity = PortfolioFormat.quantity(holding.quantity, unit: holding.quantityUnit)
        return "\(allocationText)\(PortfolioFormat.separator)\(quantity) \(holding.quantityUnit.rawValue)"
    }

    private var performanceText: String {
        guard let performanceAmount, let performancePercent else { return PortfolioFormat.missing }
        return changeText(amount: performanceAmount, percent: performancePercent)
    }

    private func changeText(amount: Double, percent: Double) -> String {
        if isPrivacyEnabled {
            return PortfolioFormat.hiddenChange(
                amount: amount,
                percent: percent,
                currencyCode: holding.currencyCode
            )
        }

        return "\(PortfolioFormat.money(amount, currencyCode: holding.currencyCode, signed: true)) (\(PortfolioFormat.percent(percent, signed: true)))"
    }

    private var marketValueText: String {
        guard let marketValue = holding.marketValue else { return PortfolioFormat.missing }
        return isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode)
            : PortfolioFormat.wholeMoney(marketValue, currencyCode: holding.currencyCode)
    }
}
