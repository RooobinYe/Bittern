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
    /// The close 1D or YTD is measured from, when the series carries one.
    let seriesBaselinePrice: Double?
    let isPrivacyEnabled: Bool
    let avatarColor: Color

    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 64
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            previousClose: holding.previousClose,
            seriesBaseline: seriesBaselinePrice,
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
        // At accessibility text sizes the logo moves above the price so the
        // price keeps the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))

        layout {
            if dynamicTypeSize.isAccessibilitySize {
                avatar
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(holding.name)
                    .font(.title3)
                    .foregroundStyle(BitternTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(priceText)
                    .font(.keyFigure(.largeTitle, weight: .bold))
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)
                    // The price is the one figure that must stay whole on a
                    // single line, so it shrinks before it would wrap.
                    .minimumScaleFactor(0.6)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        changeAmountLabel
                        changePercentLabel
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        changeAmountLabel
                        changePercentLabel
                    }
                }

                Text(selectionLabel)
                    .font(.subheadline)
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .accessibilityElement(children: .combine)

            if !dynamicTypeSize.isAccessibilitySize {
                avatar
            }
        }
    }

    private var avatar: some View {
        HoldingSymbolIcon(
            symbol: holding.symbol,
            logoURL: holding.logoURL,
            color: avatarColor,
            size: avatarSize,
            fallbackFont: .title2.bold()
        )
        .accessibilityHidden(true)
    }

    private var changeAmountLabel: some View {
        Text(changeAmountText)
            .font(.keyFigure(.body))
            .foregroundStyle(BitternTheme.performanceColor(priceDelta))
            .lineLimit(1)
    }

    private var changePercentLabel: some View {
        Text(priceDeltaPercentText)
            .font(.keyFigure(.body))
            .foregroundStyle(BitternTheme.performanceColor(priceDelta))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(BitternTheme.performanceColor(priceDelta).opacity(0.15), in: .capsule)
    }

    private var changeAmountText: String {
        guard let priceDelta else { return PortfolioFormat.missing }
        if isPrivacyEnabled {
            return PortfolioFormat.hiddenSignedMoney(priceDelta, currencyCode: holding.currencyCode)
        }
        return PortfolioFormat.money(priceDelta, currencyCode: holding.currencyCode, signed: true)
    }

    private var priceDeltaPercentText: String {
        guard let priceDeltaPercent else { return PortfolioFormat.missing }
        return PortfolioFormat.percent(priceDeltaPercent, signed: true)
    }

    private var priceText: String {
        guard let displayPoint else { return PortfolioFormat.missing }
        if isPrivacyEnabled {
            return PortfolioFormat.hiddenMoney(currencyCode: holding.currencyCode)
        }
        return PortfolioFormat.price(displayPoint.price, currencyCode: holding.currencyCode)
    }

    private var selectionLabel: String {
        if range == .oneDay {
            guard let point = displayPoint else { return PortfolioFormat.missing }
            return selectedPoint == nil
                ? PortfolioFormat.day(point.date)
                : range.selectionLabel(for: point.date)
        }

        if selectedPoint != nil, let displayPoint {
            return range.selectionLabel(for: displayPoint.date)
        }

        return range.summaryLabel
    }
}

struct HoldingChartSection: View {
    let series: [HoldingPricePoint]
    let timeDomain: PriceChartTimeDomain?
    let previousClose: Double?
    /// The close 1D or YTD is measured from, when the series carries one.
    let seriesBaselinePrice: Double?
    let currencyCode: String
    let isPrivacyEnabled: Bool
    /// The ranges to offer, leaving out those the holding hasn't traded
    /// long enough for.
    let ranges: [HoldingChartRange]
    @Binding var range: HoldingChartRange
    @Binding var selectedPoint: HoldingPricePoint?
    let isLoading: Bool

    private var basePrice: Double? {
        range.detailChangeBasePrice(
            previousClose: previousClose,
            seriesBaseline: seriesBaselinePrice,
            seriesFirstPrice: series.first?.price
        )
    }

    private var xScale: PerformanceChartXScale<HoldingPricePoint> {
        guard range == .oneDay else { return .indexed }
        guard let timeDomain else { return .unavailable }
        return .time(domain: timeDomain, timestamp: { $0.date })
    }

    var body: some View {
        let range = range
        let currencyCode = currencyCode

        PerformanceLineChartSection(
            points: series,
            value: { $0.price },
            xScale: xScale,
            date: { $0.date },
            axisUnit: range.axisUnit(for: series.map(\.date)),
            selectionLabel: { range.selectionLabel(for: $0.date) },
            valueLabel: isPrivacyEnabled
                ? nil
                : { PortfolioFormat.price($0, currencyCode: currencyCode) },
            wholeValueLabel: isPrivacyEnabled
                ? nil
                : { PortfolioFormat.wholeMoney($0, currencyCode: currencyCode) },
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
            ranges: ranges,
            rangeTitle: { $0.title },
            selectedRange: $range,
            selectedPoint: $selectedPoint,
            isLoading: isLoading,
            background: Color(uiColor: .systemGroupedBackground)
        )
    }

    private var primaryLineValue: Double? {
        if range == .oneDay {
            return series.last(where: { $0.session == .regular })?.price
        }

        return series.last?.price
    }
}

extension HoldingChartRange {
    /// The calendar unit the horizontal axis is labelled in. MAX and YTD
    /// span however much history there is, so their unit fits the dates:
    /// YTD reads in days through January and in months after.
    func axisUnit(for dates: [Date]) -> PerformanceChartAxisUnit {
        switch self {
        case .oneDay:
            .hours
        case .fiveDays, .oneMonth:
            .days
        case .threeMonths, .oneYear:
            .months
        case .fiveYears:
            .years
        case .yearToDate, .max:
            .fitting(dates)
        }
    }

    /// A selected point's date, with the time of day where prices change
    /// within a day.
    func selectionLabel(for date: Date) -> String {
        switch self {
        case .oneDay, .fiveDays, .oneMonth:
            PortfolioFormat.dayAndTime(date)
        case .threeMonths, .yearToDate, .oneYear, .fiveYears, .max:
            PortfolioFormat.dayWithYear(date)
        }
    }
}
