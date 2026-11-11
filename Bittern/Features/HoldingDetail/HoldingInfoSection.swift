//
//  HoldingInfoSection.swift
//  Bittern
//

import SwiftUI

/// The position as a list section: value, cost, quantity, share of the
/// portfolio and how the return adds up.
struct HoldingInfoSection: View {
    let holding: PortfolioHolding
    let snapshot: PortfolioSnapshot
    let isPrivacyEnabled: Bool

    private var formattedQuantity: String {
        if let quantityDisplay = holding.quantityDisplay?.trimmingCharacters(in: .whitespacesAndNewlines),
           !quantityDisplay.isEmpty {
            return quantityDisplay
        }

        return PortfolioFormat.preciseQuantity(holding.quantity)
    }

    private var averagePriceText: String {
        guard let averageCost = holding.averageCost else { return PortfolioFormat.missing }
        return isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode)
            : PortfolioFormat.price(averageCost, currencyCode: holding.currencyCode)
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
        Section {
            LabeledContent("Market Value") {
                Text(marketValueText)
                    .font(.keyFigure(.body))
            }

            LabeledContent("Average Cost") {
                Text(averagePriceText)
                    .monospacedDigit()
            }

            LabeledContent(holding.quantityUnit.title) {
                Text(isPrivacyEnabled ? "••••" : formattedQuantity)
                    .monospacedDigit()
            }

            LabeledContent("Share of Portfolio") {
                Text(snapshot.allocation(of: holding).map { PortfolioFormat.percent($0) } ?? PortfolioFormat.missing)
                    .monospacedDigit()
            }

            if let returnEquation {
                HoldingReturnEquationRow(
                    equation: returnEquation,
                    currencyCode: holding.currencyCode,
                    isPrivacyEnabled: isPrivacyEnabled
                )
            }
        } header: {
            Text("My Holdings")
                .font(.title3.bold())
                .foregroundStyle(BitternTheme.ink)
                .textCase(nil)
        }
    }

    private var marketValueText: String {
        guard let marketValue = holding.marketValue else { return PortfolioFormat.missing }
        return isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode)
            : PortfolioFormat.money(marketValue, currencyCode: holding.currencyCode)
    }
}

private struct HoldingReturnMetric: Identifiable {
    let title: String
    let amount: Double
    let percent: Double

    var id: String { title }
}

private struct HoldingReturnEquation {
    let priceGain: HoldingReturnMetric
    let dividends: HoldingReturnMetric
    let totalReturn: HoldingReturnMetric
}

/// Price gain + dividends = total return, as three columns; at accessibility
/// text sizes, or in a column too narrow for three, as three rows.
private struct HoldingReturnEquationRow: View {
    let equation: HoldingReturnEquation
    let currencyCode: String
    let isPrivacyEnabled: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            rows
        } else {
            ViewThatFits(in: .horizontal) {
                columns
                rows
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 12) {
            cell(equation.priceGain, alignment: .leading)
            cell(equation.dividends, alignment: .leading)
            cell(equation.totalReturn, alignment: .leading)
        }
    }

    private var columns: some View {
        EquationColumnsLayout(spacing: 4) {
            cell(equation.priceGain, alignment: .center)
            ReturnOperator(symbol: "+", name: "plus")
            cell(equation.dividends, alignment: .center)
            ReturnOperator(symbol: "=", name: "equals")
            cell(equation.totalReturn, alignment: .center)
        }
        .padding(.vertical, 4)
    }

    private func cell(_ metric: HoldingReturnMetric, alignment: HorizontalAlignment) -> some View {
        HoldingReturnMetricCell(
            metric: metric,
            currencyCode: currencyCode,
            isPrivacyEnabled: isPrivacyEnabled,
            alignment: alignment
        )
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

/// The three metrics in equal columns with the operators between them at
/// their own widths. Its ideal width is three of the widest metric, not
/// their sum, so `ViewThatFits` stacks them before a title truncates.
private struct EquationColumnsLayout: Layout {
    let spacing: CGFloat

    /// Even places hold metrics, odd ones operators.
    private func widths(of subviews: Subviews) -> (metric: CGFloat, operators: CGFloat) {
        var metric: CGFloat = 0
        var operators: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let width = subview.sizeThatFits(.unspecified).width
            if index.isMultiple(of: 2) {
                metric = max(metric, width)
            } else {
                operators += width
            }
        }
        return (metric, operators)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (metric, operators) = widths(of: subviews)
        let metricCount = CGFloat((subviews.count + 1) / 2)
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let idealWidth = metric * metricCount + operators + gaps
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        guard let width = proposal.width, width.isFinite else {
            return CGSize(width: idealWidth, height: height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (_, operators) = widths(of: subviews)
        let metricCount = CGFloat((subviews.count + 1) / 2)
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let metricWidth = max(0, bounds.width - operators - gaps) / max(metricCount, 1)
        var x = bounds.minX

        for (index, subview) in subviews.enumerated() {
            let width = index.isMultiple(of: 2) ? metricWidth : subview.sizeThatFits(.unspecified).width
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }
}

private struct ReturnOperator: View {
    let symbol: String
    let name: String

    var body: some View {
        Text(symbol)
            .font(.body)
            .foregroundStyle(BitternTheme.secondaryInk)
            .accessibilityLabel(name)
    }
}

private struct HoldingReturnMetricCell: View {
    let metric: HoldingReturnMetric
    let currencyCode: String
    let isPrivacyEnabled: Bool
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            // Titled like the rows above it; the figures keep their gain or
            // loss color.
            Text(metric.title)
                .font(.body)
                .foregroundStyle(BitternTheme.ink)
                .lineLimit(1)

            Text(amountText)
                .font(.keyFigure(.body))
                .foregroundStyle(BitternTheme.performanceColor(metric.amount))
                .lineLimit(1)

            Text(PortfolioFormat.percent(metric.percent))
                .font(.keyFigure(.subheadline))
                .foregroundStyle(BitternTheme.performanceColor(metric.amount))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var amountText: String {
        isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: currencyCode)
            : PortfolioFormat.wholeMoney(metric.amount, currencyCode: currencyCode)
    }
}
