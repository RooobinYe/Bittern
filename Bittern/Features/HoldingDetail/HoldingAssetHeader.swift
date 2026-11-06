//
//  HoldingAssetHeader.swift
//  Bittern
//

import SwiftUI

struct HoldingAssetHeader: View {
    let holding: PortfolioHolding
    let series: [HoldingPricePoint]
    let range: HoldingChartRange
    let selectedPoint: HoldingPricePoint?
    let oneDayBaselinePrice: Double?
    let isPrivacyEnabled: Bool
    let avatarColor: Color

    @ScaledMetric(relativeTo: .largeTitle) private var priceRowMinimumHeight: CGFloat = 41

    private var displayPoint: HoldingPricePoint? {
        selectedPoint ?? defaultDisplayPoint
    }

    private var defaultDisplayPoint: HoldingPricePoint? {
        if range == .oneDay {
            return series.last(where: { $0.session == .regular })
                ?? holding.currentPrice.map {
                    HoldingPricePoint(date: Date(), price: $0)
                }
        }

        return series.last
            ?? holding.currentPrice.map {
                HoldingPricePoint(date: Date(), price: $0)
            }
    }

    private var basePrice: Double? {
        range.detailChangeBasePrice(
            previousClose: oneDayBaselinePrice ?? holding.previousClose,
            seriesFirstPrice: series.first?.price
        )
    }

    private var priceDelta: Double? {
        guard let displayPoint, let basePrice else { return nil }
        return displayPoint.price - basePrice
    }

    private var priceDeltaPercent: Double? {
        guard let basePrice, basePrice != 0, let priceDelta else { return nil }
        return priceDelta / abs(basePrice)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(holding.name)
                    .font(.title.bold())
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.48)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(priceText)
                        .font(.largeTitle.bold().monospacedDigit())
                        .foregroundStyle(BitternTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Text(holding.currencyCode)
                        .font(.title3.bold())
                        .foregroundStyle(BitternTheme.ink)
                        .lineLimit(1)
                }
                .frame(minHeight: priceRowMinimumHeight, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 9) {
                        changeAmountLabel
                            .layoutPriority(1)
                        changePercentLabel
                            .layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .leading)

                    Text(selectionLabel)
                        .font(.headline.bold())
                        .foregroundStyle(BitternTheme.secondaryInk)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            HoldingDetailAvatar(
                symbol: holding.symbol,
                logoURL: holding.logoURL,
                color: avatarColor,
                size: 84
            )
                .accessibilityLabel(holding.symbol)
        }
    }

    private var changeAmountLabel: some View {
        Text(changeAmountText)
            .font(.headline.bold().monospacedDigit())
            .foregroundStyle(BitternTheme.performanceColor(priceDelta))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
    }

    private var changePercentLabel: some View {
        Text(priceDeltaPercentText)
            .font(.headline.bold().monospacedDigit())
            .foregroundStyle(BitternTheme.performanceColor(priceDelta))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(BitternTheme.performanceColor(priceDelta).opacity(0.18))
            .clipShape(Capsule())
    }

    private var changeAmountText: String {
        if isPrivacyEnabled {
            guard let priceDelta else {
                return "N/A"
            }

            if priceDelta > 0 {
                return "+\(PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode))"
            }

            if priceDelta < 0 {
                return "-\(PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode))"
            }

            return PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode)
        }

        guard let priceDelta else { return "N/A" }
        return PortfolioFormat.money(priceDelta, currencyCode: holding.currencyCode, signed: true)
    }

    private var priceDeltaPercentText: String {
        guard let priceDeltaPercent else { return "N/A" }
        return PortfolioFormat.percent(priceDeltaPercent, signed: true)
    }

    private var priceText: String {
        if isPrivacyEnabled {
            return displayPoint == nil ? "N/A" : PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode)
        }

        guard let displayPoint else { return "N/A" }
        return PortfolioFormat.price(displayPoint.price, currencyCode: holding.currencyCode)
    }

    private var selectionLabel: String {
        if range == .oneDay {
            guard let point = displayPoint else { return "N/A" }
            return selectedPoint == nil
                ? oneDayLatestDateFormatter.string(from: point.date)
                : formattedSelectionDate(point.date, range: range)
        }

        if selectedPoint != nil, let displayPoint {
            return formattedSelectionDate(displayPoint.date, range: range)
        }

        return range.summaryLabel
    }
}

private struct HoldingDetailAvatar: View {
    let symbol: String
    let logoURL: URL?
    let color: Color
    let size: CGFloat

    var body: some View {
        HoldingSymbolIcon(
            symbol: symbol,
            logoURL: logoURL,
            color: color,
            size: size,
            fallbackFont: .title2.bold()
        )
    }
}

struct HoldingChartSection: View {
    let series: [HoldingPricePoint]
    let timeDomain: PriceChartTimeDomain?
    let previousClose: Double?
    let oneDayBaselinePrice: Double?
    let currencyCode: String
    let isPrivacyEnabled: Bool
    @Binding var range: HoldingChartRange
    @Binding var selectedPoint: HoldingPricePoint?
    let isLoading: Bool

    private var basePrice: Double? {
        range.detailChangeBasePrice(
            previousClose: oneDayBaselinePrice ?? previousClose,
            seriesFirstPrice: series.first?.price
        )
    }

    private var xScale: PerformanceChartXScale<HoldingPricePoint> {
        guard range == .oneDay else { return .indexed }
        guard let timeDomain else { return .unavailable }
        return .time(domain: timeDomain, timestamp: { $0.date })
    }

    var body: some View {
        PerformanceLineChartSection(
            points: series,
            value: { $0.price },
            xScale: xScale,
            baseValue: basePrice,
            baselineLabel: basePrice.map {
                isPrivacyEnabled
                    ? PortfolioFormat.hiddenMoney(currencyCode: currencyCode)
                    : PortfolioFormat.price($0, currencyCode: currencyCode)
            },
            primaryLineValue: primaryLineValue,
            lineStyle: { point in
                point.session.isExtendedHours ? .neutral : .primary
            },
            ranges: HoldingChartRange.allCases,
            rangeTitle: { $0.title },
            selectedRange: $range,
            selectedPoint: $selectedPoint,
            isLoading: isLoading
        )
    }

    private var primaryLineValue: Double? {
        if range == .oneDay {
            return series.last(where: { $0.session == .regular })?.price
        }

        return series.last?.price
    }
}

private let selectionDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    return formatter
}()

private let oneDayLatestDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "d MMM"
    return formatter
}()

private func formattedSelectionDate(_ date: Date, range: HoldingChartRange) -> String {
    switch range {
    case .oneDay:
        selectionDateFormatter.dateFormat = "d MMM, HH:mm"
    case .fiveDays:
        selectionDateFormatter.dateFormat = "d MMM, HH:mm"
    case .threeMonths, .oneYear, .fiveYears, .max:
        selectionDateFormatter.dateFormat = "d MMM, yyyy"
    }

    return selectionDateFormatter.string(from: date)
}

