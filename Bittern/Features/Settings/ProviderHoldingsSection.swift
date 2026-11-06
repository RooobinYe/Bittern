//
//  ProviderHoldingsSection.swift
//  Bittern
//

import SwiftUI

struct ProviderHoldingsSection: View {
    let group: ProviderHoldings
    let holdingColorLookup: [String: Color]
    let isPrivacyEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ProviderLogo(name: group.name, url: group.logoURL)

                Text(group.name)
                    .font(.title2.bold())
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if group.isDisabled {
                    Text("Disabled")
                        .font(.caption2.bold())
                        .foregroundStyle(BitternTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BitternTheme.warning.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.bottom, 15)

            if group.holdings.isEmpty {
                Text("\(group.accountCount) account\(group.accountCount == 1 ? "" : "s") connected")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .padding(.bottom, 15)
            } else {
                ForEach(group.holdings) { holding in
                    ProviderHoldingRow(
                        holding: holding,
                        color: holdingColorLookup[holding.id] ?? BitternTheme.allocationColor(at: 0),
                        isPrivacyEnabled: isPrivacyEnabled
                    )
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

    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 28

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
                .font(.title2.weight(.semibold))
                .foregroundStyle(BitternTheme.secondaryInk)
        }
        .accessibilityHidden(true)
    }
}

private struct ProviderHoldingRow: View {
    let holding: PortfolioHolding
    let color: Color
    let isPrivacyEnabled: Bool

    private var unitLabel: String {
        holding.quantityUnit.rawValue
    }

    private var formattedQuantity: String {
        PortfolioFormat.quantity(holding.quantity, unit: holding.quantityUnit)
    }

    var body: some View {
        HStack(spacing: 12) {
            HoldingSymbolIcon(
                symbol: holding.symbol,
                logoURL: holding.logoURL,
                color: color,
                size: 40
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(holding.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)

                Text(holding.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(marketValueText)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(isPrivacyEnabled ? "••••" : formattedQuantity) \(unitLabel)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(BitternTheme.softLine.opacity(0.7))
        }
    }

    private var marketValueText: String {
        guard let marketValue = holding.marketValue else { return "N/A" }
        return isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode)
            : PortfolioFormat.wholeMoney(marketValue, currencyCode: holding.currencyCode)
    }
}

struct EmptyProvidersView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "building.columns")
                .font(.title2.bold())
                .foregroundStyle(BitternTheme.secondaryInk)

            Text("No providers yet")
                .font(.headline.bold())
                .foregroundStyle(BitternTheme.ink)

            Text("Connect a brokerage through SnapTrade to see providers here.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BitternTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(16)
        .bitternPanel()
    }
}

