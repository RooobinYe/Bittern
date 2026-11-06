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
    let showsDivider: Bool
    let marketTime: Date

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
        VStack(spacing: 0) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 12) {
                    HoldingSymbolIcon(
                        symbol: holding.symbol,
                        logoURL: holding.logoURL,
                        color: color,
                        size: 40
                    )

                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(holding.symbol)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(BitternTheme.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer(minLength: 8)

                            Text(marketValueText)
                                .font(.title3.weight(.semibold).monospacedDigit())
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
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            if showsDivider {
                Divider()
                    .overlay(BitternTheme.softLine.opacity(0.7))
            }
        }
    }

    private var secondaryMetrics: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(quantityAndAllocationText)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(BitternTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(performanceText)
                .font(.footnote.weight(.semibold).monospacedDigit())
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
                .font(.caption.weight(.semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    presentation.primaryColor,
                    presentation.secondaryColor
                )
                .frame(width: 16, alignment: .center)
                .accessibilityHidden(true)

            Text(changeText(amount: presentation.change.amount, percent: presentation.change.percent))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(
                    BitternTheme.performanceColor(presentation.change.amount)
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(presentation.accessibilityName) \(changeText(amount: presentation.change.amount, percent: presentation.change.percent))"
        )
    }

    private var quantityAndAllocationText: String {
        let allocationText = allocation.map { PortfolioFormat.percent($0) } ?? "N/A"
        guard !isPrivacyEnabled else { return allocationText }

        let quantity = PortfolioFormat.quantity(holding.quantity, unit: holding.quantityUnit)
        return "\(quantity) \(holding.quantityUnit.rawValue) | \(allocationText)"
    }

    private var performanceText: String {
        guard let performanceAmount, let performancePercent else { return "N/A" }
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
        guard let marketValue = holding.marketValue else { return "N/A" }
        return isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode)
            : PortfolioFormat.wholeMoney(marketValue, currencyCode: holding.currencyCode)
    }
}
