//
//  HoldingInfoSection.swift
//  Bittern
//

import SwiftUI

struct HoldingInfoSection: View {
    let holding: PortfolioHolding
    let snapshot: PortfolioSnapshot
    let isPrivacyEnabled: Bool

    private var allocation: Double? {
        snapshot.allocation(of: holding)
    }

    private var unitLabel: String {
        holding.quantityUnit.title
    }

    private var formattedQuantity: String {
        if let quantityDisplay = holding.quantityDisplay?.trimmingCharacters(in: .whitespacesAndNewlines),
           !quantityDisplay.isEmpty {
            return quantityDisplay
        }

        return preciseQuantity(holding.quantity)
    }

    private var averagePriceText: String {
        if isPrivacyEnabled {
            return PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode)
        }

        guard let averageCost = holding.averageCost else { return "N/A" }
        return PortfolioFormat.price(averageCost, currencyCode: holding.currencyCode)
    }

    private var returnEquation: HoldingReturnEquation? {
        guard let allTimeGainAmount = holding.allTimeGainAmount,
              let allTimeGainPercent = holding.allTimeGainPercent,
              let dividendsReceived = holding.dividendsReceived,
              let dividendReturnPercent = holding.dividendReturnPercent,
              let totalReturnAmount = holding.totalReturnAmount,
              let totalReturnPercent = holding.totalReturnPercent,
              holding.quantity > 0
        else {
            return nil
        }

        return HoldingReturnEquation(
            priceGain: HoldingReturnMetric(
                title: "Price Gain",
                amount: allTimeGainAmount,
                percent: allTimeGainPercent
            ),
            dividends: HoldingReturnMetric(
                title: "Dividends",
                amount: dividendsReceived,
                percent: dividendReturnPercent
            ),
            totalReturn: HoldingReturnMetric(
                title: "Total Return",
                amount: totalReturnAmount,
                percent: totalReturnPercent
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("My Holdings")
                    .font(.title.bold())
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8)

                Text(allocationText)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(uiColor: .secondarySystemFill))
                    .clipShape(Capsule())
            }

            VStack(spacing: 0) {
                HoldingInfoRow(
                    title: "Market Value",
                    value: totalText
                )

                Divider().overlay(BitternTheme.softLine)

                HoldingInfoRow(
                    title: "Average Cost",
                    value: averagePriceText
                )

                Divider().overlay(BitternTheme.softLine)

                HoldingInfoRow(title: unitLabel, value: isPrivacyEnabled ? "••••" : formattedQuantity)

                if let returnEquation {
                    Divider().overlay(BitternTheme.softLine)

                    HoldingReturnEquationGrid(
                        equation: returnEquation,
                        currencyCode: holding.currencyCode,
                        isPrivacyEnabled: isPrivacyEnabled
                    )
                }
            }
            .bitternPanel()
        }
    }

    private var allocationText: String {
        guard let allocation else { return "N/A of portfolio" }
        return "\(PortfolioFormat.percent(allocation)) of portfolio"
    }

    private var totalText: String {
        if isPrivacyEnabled {
            return holding.marketValue == nil ? "N/A" : PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode)
        }

        guard let marketValue = holding.marketValue else { return "N/A" }
        return PortfolioFormat.money(marketValue, currencyCode: holding.currencyCode)
    }
}

private struct HoldingInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(BitternTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Spacer(minLength: 14)

            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(BitternTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.56)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 64)
        .padding(.horizontal, 18)
    }
}

private struct HoldingReturnMetric: Identifiable {
    let title: String
    let amount: Double?
    let percent: Double?

    var id: String { title }
}

private struct HoldingReturnEquation {
    let priceGain: HoldingReturnMetric
    let dividends: HoldingReturnMetric
    let totalReturn: HoldingReturnMetric
}

private struct HoldingReturnEquationGrid: View {
    let equation: HoldingReturnEquation
    let currencyCode: String
    let isPrivacyEnabled: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                HoldingReturnMetricCell(
                    metric: equation.priceGain,
                    currencyCode: currencyCode,
                    isPrivacyEnabled: isPrivacyEnabled
                )
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(width: 1)
                    .overlay(BitternTheme.softLine)

                HoldingReturnMetricCell(
                    metric: equation.dividends,
                    currencyCode: currencyCode,
                    isPrivacyEnabled: isPrivacyEnabled
                )
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(width: 1)
                    .overlay(BitternTheme.softLine)

                HoldingReturnMetricCell(
                    metric: equation.totalReturn,
                    currencyCode: currencyCode,
                    isPrivacyEnabled: isPrivacyEnabled
                )
                .frame(maxWidth: .infinity)
            }

            GeometryReader { proxy in
                HoldingReturnOperator(symbol: "+")
                    .position(x: proxy.size.width / 3, y: proxy.size.height * 0.62)

                HoldingReturnOperator(symbol: "=")
                    .position(x: proxy.size.width * 2 / 3, y: proxy.size.height * 0.62)
            }
            .allowsHitTesting(false)
        }
        .frame(minHeight: 112)
    }
}

private struct HoldingReturnOperator: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.title2)
            .foregroundStyle(BitternTheme.secondaryInk)
            .frame(width: 32, height: 32)
            .background(BitternTheme.surface)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(BitternTheme.softLine.opacity(0.8), lineWidth: 1)
            }
    }
}

private struct HoldingReturnMetricCell: View {
    let metric: HoldingReturnMetric
    let currencyCode: String
    let isPrivacyEnabled: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(metric.title)
                .font(.headline.bold())
                .foregroundStyle(BitternTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            VStack(spacing: 2) {
                Text(amountText)
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(metricColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(percentText)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(metricColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
    }

    private var amountText: String {
        guard let amount = metric.amount else { return "--" }
        return isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: currencyCode)
            : PortfolioFormat.wholeMoney(amount, currencyCode: currencyCode)
    }

    private var percentText: String {
        guard let percent = metric.percent else { return "(--)" }
        return "(\(PortfolioFormat.percent(percent)))"
    }

    private var metricColor: Color {
        guard let amount = metric.amount else {
            return BitternTheme.secondaryInk
        }

        return BitternTheme.performanceColor(amount)
    }
}

private let preciseQuantityFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.maximumFractionDigits = 12
    formatter.minimumFractionDigits = 0
    return formatter
}()

private func preciseQuantity(_ value: Double) -> String {
    return preciseQuantityFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

