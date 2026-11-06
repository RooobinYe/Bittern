//
//  ProviderHoldingsSection.swift
//  Bittern
//

import SwiftUI

/// One brokerage in the settings form: its name and logo as the section
/// header, then the holdings it holds.
struct ProviderHoldingsSection: View {
    let group: ProviderHoldings
    let holdingColorLookup: [String: Color]
    let isPrivacyEnabled: Bool

    var body: some View {
        Section {
            if group.holdings.isEmpty {
                Text(group.accountCount == 1 ? "1 account connected" : "\(group.accountCount) accounts connected")
                    .foregroundStyle(BitternTheme.secondaryInk)
            } else {
                ForEach(group.holdings) { holding in
                    ProviderHoldingRow(
                        holding: holding,
                        color: holdingColorLookup[holding.id] ?? BitternTheme.allocationColor(at: 0),
                        isPrivacyEnabled: isPrivacyEnabled
                    )
                }
            }
        } header: {
            HStack(spacing: 8) {
                ProviderLogo(name: group.name, url: group.logoURL)

                Text(group.name)

                if group.isDisabled {
                    Text("Disabled")
                        .foregroundStyle(BitternTheme.warning)
                }
            }
        }
    }
}

/// The brokerage's logo from SnapTrade, or a generic link symbol while it
/// loads or when SnapTrade has none.
private struct ProviderLogo: View {
    let name: String
    let url: URL?

    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 20

    var body: some View {
        LogoImage(name: name, url: url) { image in
            image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } placeholder: {
            Image(systemName: "link")
                .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

private struct ProviderHoldingRow: View {
    let holding: PortfolioHolding
    let color: Color
    let isPrivacyEnabled: Bool

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 12) {
            HoldingSymbolIcon(
                symbol: holding.symbol,
                logoURL: holding.logoURL,
                color: color,
                size: iconSize
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(holding.symbol)
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)

                Text(holding.name)
                    .font(.subheadline)
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(marketValueText)
                    .font(.keyFigure(.body))
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)

                Text(quantityText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var quantityText: String {
        let quantity = isPrivacyEnabled
            ? "••••"
            : PortfolioFormat.quantity(holding.quantity, unit: holding.quantityUnit)
        return "\(quantity) \(holding.quantityUnit.rawValue)"
    }

    private var marketValueText: String {
        guard let marketValue = holding.marketValue else { return PortfolioFormat.missing }
        return isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode)
            : PortfolioFormat.wholeMoney(marketValue, currencyCode: holding.currencyCode)
    }
}
