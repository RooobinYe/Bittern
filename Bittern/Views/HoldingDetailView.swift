//
//  HoldingDetailView.swift
//  Bittern
//

import Combine
import SwiftUI
import OSLog

struct HoldingDetailView: View {
    let holding: PortfolioHolding
    let snapshot: PortfolioSnapshot
    let allocationHoldings: [PortfolioHolding]

    @StateObject private var detailModel: HoldingDetailViewModel
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false

    init(
        holding: PortfolioHolding,
        snapshot: PortfolioSnapshot,
        allocationHoldings: [PortfolioHolding]
    ) {
        self.holding = holding
        self.snapshot = snapshot
        self.allocationHoldings = allocationHoldings
        _detailModel = StateObject(wrappedValue: HoldingDetailViewModel(holding: holding))
    }

    var body: some View {
        ZStack {
            BitternTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    HoldingAssetHeader(
                        holding: holding,
                        series: detailModel.visibleSeries,
                        range: detailModel.selectedRange,
                        selectedPoint: detailModel.selectedPoint,
                        oneDayBaselinePrice: detailModel.visibleBaselinePrice,
                        isPrivacyEnabled: isPrivacyEnabled,
                        avatarColor: BitternTheme.holdingAllocationColor(
                            for: holding,
                            in: allocationHoldings
                        )
                    )

                    HoldingChartSection(
                        series: detailModel.visibleSeries,
                        timeDomain: detailModel.visibleTimeDomain,
                        previousClose: holding.previousClose,
                        oneDayBaselinePrice: detailModel.visibleBaselinePrice,
                        currencyCode: holding.currencyCode,
                        isPrivacyEnabled: isPrivacyEnabled,
                        range: $detailModel.selectedRange,
                        selectedPoint: $detailModel.selectedPoint,
                        isLoading: detailModel.isLoading
                    )
                    .frame(maxWidth: holdingDetailMaximumChartWidth)

                    HoldingInfoSection(
                        holding: holding,
                        snapshot: snapshot,
                        isPrivacyEnabled: isPrivacyEnabled
                    )
                }
                .frame(maxWidth: holdingDetailMaximumContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentMargins(.horizontal, 24, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable {
                await Task {
                    await detailModel.refreshSelectedRange()
                }.value
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .errorToast(message: $detailModel.errorMessage)
        .task {
            await detailModel.loadSelectedRangeIfNeeded()
        }
        .onChange(of: detailModel.selectedRange) { _, _ in
            Task {
                await detailModel.loadSelectedRangeIfNeeded()
            }
        }
    }
}

private let holdingDetailMaximumContentWidth: CGFloat = 900
private let holdingDetailMaximumChartWidth: CGFloat = 760

@MainActor
private final class HoldingDetailViewModel: ObservableObject {
    @Published var selectedRange: HoldingChartRange = .oneDay
    @Published var selectedPoint: HoldingPricePoint?
    @Published private(set) var priceSeriesByRange: [HoldingChartRange: HoldingPriceSeries] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let holding: PortfolioHolding
    private let yahooClient: YahooFinanceClient

    init(holding: PortfolioHolding, yahooClient: YahooFinanceClient? = nil) {
        self.holding = holding
        self.yahooClient = yahooClient ?? YahooFinanceClient()
    }

    var visibleSeries: [HoldingPricePoint] {
        priceSeriesByRange[selectedRange]?.points ?? []
    }

    var visibleTimeDomain: PriceChartTimeDomain? {
        priceSeriesByRange[selectedRange]?.timeDomain
    }

    var visibleBaselinePrice: Double? {
        priceSeriesByRange[selectedRange]?.baselinePrice
    }

    func loadSelectedRangeIfNeeded() async {
        let range = selectedRange
        guard priceSeriesByRange[range] == nil else {
            isLoading = false
            return
        }

        await loadSelectedRange(range, showsLoading: true)
    }

    func refreshSelectedRange() async {
        let range = selectedRange
        await loadSelectedRange(range, showsLoading: priceSeriesByRange[range] == nil)
    }

    private func loadSelectedRange(
        _ range: HoldingChartRange,
        showsLoading: Bool
    ) async {
        if showsLoading {
            isLoading = true
        }
        errorMessage = nil
        defer {
            if showsLoading && selectedRange == range {
                isLoading = false
            }
        }

        do {
            let history = try await yahooClient.priceHistory(
                for: holding.symbol,
                instrumentKind: holding.instrumentKind,
                range: range
            )
            guard !Task.isCancelled else { return }
            selectedPoint = nil
            priceSeriesByRange[range] = history
        } catch {
            guard !Task.isCancelled else { return }
            AppLog.marketData.warning(
                "Chart load failed range=\(range.title, privacy: .public) symbol=\(self.holding.symbol): \(AppLog.describe(error))"
            )
            if priceSeriesByRange[range] == nil {
                priceSeriesByRange[range] = .empty
            }
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "Price history for \(holding.symbol) couldn’t be loaded. Please try again."
            )
        }
    }

}

private struct HoldingAssetHeader: View {
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

private struct HoldingChartSection: View {
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

private struct HoldingInfoSection: View {
    let holding: PortfolioHolding
    let snapshot: PortfolioSnapshot
    let isPrivacyEnabled: Bool

    private var allocation: Double? {
        guard let holdingMarketValue = holding.marketValue,
              let totalMarketValue = snapshot.totalMarketValue,
              totalMarketValue > 0
        else {
            return nil
        }

        return holdingMarketValue / totalMarketValue
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

#if DEBUG
struct HoldingDetailView_Previews: PreviewProvider {
    static var previews: some View {
        HoldingDetailView(
            holding: DemoPortfolio.snapshot.holdings[3],
            snapshot: DemoPortfolio.snapshot,
            allocationHoldings: DemoPortfolio.snapshot.holdings
        )
    }
}
#endif
