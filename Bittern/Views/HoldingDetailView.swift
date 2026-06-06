//
//  HoldingDetailView.swift
//  Bittern
//

import Combine
import SwiftUI

struct HoldingDetailView: View {
    let holding: PortfolioHolding
    let snapshot: PortfolioSnapshot
    let providerName: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var detailModel: HoldingDetailViewModel
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false

    init(
        holding: PortfolioHolding,
        snapshot: PortfolioSnapshot,
        providerName: String
    ) {
        self.holding = holding
        self.snapshot = snapshot
        self.providerName = providerName
        _detailModel = StateObject(wrappedValue: HoldingDetailViewModel(holding: holding))
    }

    var body: some View {
        ZStack {
            BitternTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HoldingDetailTopBar(goBack: { dismiss() })
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 14)
                .background(BitternTheme.background)

                ScrollView {
                    VStack(spacing: 24) {
                        HoldingAssetHeader(
                            holding: holding,
                            series: detailModel.visibleSeries,
                            range: detailModel.selectedRange,
                            selectedPoint: detailModel.selectedPoint,
                            isPrivacyEnabled: isPrivacyEnabled
                        )

                        HoldingChartSection(
                            series: detailModel.visibleSeries,
                            currencyCode: holding.currencyCode,
                            range: $detailModel.selectedRange,
                            selectedPoint: $detailModel.selectedPoint,
                            isLoading: detailModel.isLoading
                        )

                        HoldingInfoSection(
                            holding: holding,
                            snapshot: snapshot,
                            providerName: providerName,
                            isPrivacyEnabled: isPrivacyEnabled
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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

@MainActor
private final class HoldingDetailViewModel: ObservableObject {
    @Published var selectedRange: HoldingChartRange = .oneDay
    @Published var selectedPoint: HoldingPricePoint?
    @Published private(set) var priceSeriesByRange: [HoldingChartRange: [HoldingPricePoint]] = [:]
    @Published private(set) var isLoading = false

    private let holding: PortfolioHolding
    private let yahooClient: YahooFinanceClient

    init(holding: PortfolioHolding, yahooClient: YahooFinanceClient? = nil) {
        self.holding = holding
        self.yahooClient = yahooClient ?? YahooFinanceClient()
    }

    var visibleSeries: [HoldingPricePoint] {
        priceSeriesByRange[selectedRange] ?? Self.fallbackSeries(for: holding, range: selectedRange)
    }

    func loadSelectedRangeIfNeeded() async {
        let range = selectedRange
        guard priceSeriesByRange[range] == nil else { return }

        isLoading = true
        defer {
            if selectedRange == range {
                isLoading = false
            }
        }

        do {
            let history = try await yahooClient.priceHistory(for: holding.symbol, range: range)
            guard !Task.isCancelled else { return }
            priceSeriesByRange[range] = normalized(history, currentPrice: holding.currentPrice)
        } catch {
            priceSeriesByRange[range] = Self.fallbackSeries(for: holding, range: range)
        }
    }

    private func normalized(_ points: [HoldingPricePoint], currentPrice: Double) -> [HoldingPricePoint] {
        let sorted = points.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return sorted }

        let lastPoint = sorted[sorted.count - 1]
        guard currentPrice > 0,
              abs(lastPoint.price - currentPrice) / max(abs(currentPrice), 0.01) > 0.002
        else {
            return sorted
        }

        return sorted + [
            HoldingPricePoint(date: max(Date(), lastPoint.date.addingTimeInterval(1)), price: currentPrice)
        ]
    }

    private static func fallbackSeries(for holding: PortfolioHolding, range: HoldingChartRange) -> [HoldingPricePoint] {
        let count = max(range.fallbackPointCount, 2)
        let currentPrice = max(holding.currentPrice, 0.01)
        let seed = Double(holding.symbol.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 31)
        let startPrice = fallbackStartPrice(for: holding, range: range, currentPrice: currentPrice)
        let amplitude = max(currentPrice * amplitudeScale(for: range), abs(currentPrice - startPrice) * 0.22, 0.01)
        let cycles = cyclesForRange(range) + seed.truncatingRemainder(dividingBy: 3)
        let now = Date()
        let startDate = now.addingTimeInterval(-range.fallbackTimeSpan)

        return (0..<count).map { index in
            let progress = Double(index) / Double(count - 1)
            let trend = startPrice + (currentPrice - startPrice) * progress
            let ease = sin(progress * .pi)
            let waveA = sin(progress * .pi * cycles + seed * 0.23)
            let waveB = cos(progress * .pi * (cycles * 0.52 + 1.7) + seed * 0.41)
            let wave = (waveA + waveB * 0.45) * amplitude * ease
            let price: Double
            if index == 0 {
                price = startPrice
            } else if index == count - 1 {
                price = currentPrice
            } else {
                price = max(0.01, trend + wave)
            }

            return HoldingPricePoint(
                date: startDate.addingTimeInterval(range.fallbackTimeSpan * progress),
                price: price
            )
        }
    }

    private static func fallbackStartPrice(
        for holding: PortfolioHolding,
        range: HoldingChartRange,
        currentPrice: Double
    ) -> Double {
        let previousClose = holding.previousClose > 0 ? holding.previousClose : currentPrice * 0.995
        let averageCost = holding.averageCost > 0 ? holding.averageCost : currentPrice

        switch range {
        case .oneDay:
            return previousClose
        case .fiveDays:
            let dailyDelta = currentPrice - previousClose
            return max(0.01, currentPrice - dailyDelta * 2.6 - currentPrice * 0.006)
        case .threeMonths:
            return max(0.01, (averageCost * 0.45 + previousClose * 0.2 + currentPrice * 0.35))
        case .oneYear:
            return max(0.01, averageCost * 0.76 + currentPrice * 0.24)
        case .fiveYears:
            return max(0.01, averageCost * 0.58 + currentPrice * 0.18)
        case .max:
            return max(0.01, averageCost * 0.42 + currentPrice * 0.12)
        }
    }

    private static func amplitudeScale(for range: HoldingChartRange) -> Double {
        switch range {
        case .oneDay:
            0.009
        case .fiveDays:
            0.016
        case .threeMonths:
            0.032
        case .oneYear:
            0.045
        case .fiveYears:
            0.06
        case .max:
            0.07
        }
    }

    private static func cyclesForRange(_ range: HoldingChartRange) -> Double {
        switch range {
        case .oneDay:
            18
        case .fiveDays:
            8
        case .threeMonths:
            7
        case .oneYear:
            9
        case .fiveYears:
            11
        case .max:
            13
        }
    }
}

private struct HoldingDetailTopBar: View {
    let goBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: goBack) {
                HoldingCircleButtonLabel(systemName: "chevron.left", size: 42, background: BitternTheme.surface)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()
        }
    }
}

private struct HoldingCircleButtonLabel: View {
    let systemName: String
    let size: CGFloat
    let background: Color
    var foreground: Color = BitternTheme.secondaryInk

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background)
            .clipShape(Circle())
            .contentShape(Circle())
    }
}

private struct HoldingAssetHeader: View {
    let holding: PortfolioHolding
    let series: [HoldingPricePoint]
    let range: HoldingChartRange
    let selectedPoint: HoldingPricePoint?
    let isPrivacyEnabled: Bool

    private var displayPoint: HoldingPricePoint {
        selectedPoint ?? series.last ?? HoldingPricePoint(date: Date(), price: holding.currentPrice)
    }

    private var basePrice: Double {
        series.first?.price ?? holding.previousClose
    }

    private var priceDelta: Double {
        displayPoint.price - basePrice
    }

    private var priceDeltaPercent: Double {
        guard basePrice != 0 else { return 0 }
        return priceDelta / abs(basePrice)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(holding.name)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.68)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(isPrivacyEnabled ? hiddenDetailMoney(currencyCode: holding.currencyCode) : PortfolioFormat.price(displayPoint.price, currencyCode: holding.currencyCode))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Text(holding.currencyCode)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.ink)
                        .lineLimit(1)
                }

                HStack(spacing: 9) {
                    Text(changeAmountText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.performanceColor(priceDelta))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(PortfolioFormat.percent(priceDeltaPercent, signed: true))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.performanceColor(priceDelta))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(BitternTheme.performanceColor(priceDelta).opacity(0.18))
                        .clipShape(Capsule())

                    Text("· \(selectedPoint == nil ? range.summaryLabel : formattedSelectionDate(displayPoint.date, range: range))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            HoldingDetailAvatar(symbol: holding.symbol, size: 84)
                .accessibilityLabel(holding.symbol)
        }
    }

    private var changeAmountText: String {
        if isPrivacyEnabled {
            if priceDelta > 0 {
                return "+\(hiddenDetailMoney(currencyCode: holding.currencyCode))"
            }

            if priceDelta < 0 {
                return "-\(hiddenDetailMoney(currencyCode: holding.currencyCode))"
            }

            return hiddenDetailMoney(currencyCode: holding.currencyCode)
        }

        return PortfolioFormat.money(priceDelta, currencyCode: holding.currencyCode, signed: true)
    }
}

private struct HoldingDetailAvatar: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Text(String(symbol.prefix(4)))
            .font(.system(size: avatarFontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .frame(width: size, height: size)
            .background(avatarColor)
            .clipShape(Circle())
    }

    private var avatarFontSize: CGFloat {
        let count = max(CGFloat(symbol.prefix(4).count), 1)
        return min(size * 0.38, max(12, size / count * 0.92))
    }

    private var avatarColor: Color {
        let palette = BitternTheme.allocationColors
        let sum = symbol.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

private struct HoldingChartSection: View {
    let series: [HoldingPricePoint]
    let currencyCode: String
    @Binding var range: HoldingChartRange
    @Binding var selectedPoint: HoldingPricePoint?
    let isLoading: Bool

    private var lineColor: Color {
        guard let first = series.first?.price, let last = series.last?.price else {
            return BitternTheme.secondaryInk
        }

        return BitternTheme.performanceColor(last - first)
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(BitternTheme.secondaryInk)
                        .scaleEffect(1.2)
                        .frame(height: 318)
                        .frame(maxWidth: .infinity)
                } else {
                    HoldingPriceChart(
                        points: series,
                        basePrice: series.first?.price,
                        currencyCode: currencyCode,
                        lineColor: lineColor,
                        selectedPoint: $selectedPoint
                    )
                    .frame(height: 318)
                }
            }

            HStack(spacing: 0) {
                ForEach(HoldingChartRange.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            range = option
                            selectedPoint = nil
                        }
                    } label: {
                        Text(option.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(range == option ? BitternTheme.gain : BitternTheme.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background {
                                if range == option {
                                    Capsule()
                                        .fill(BitternTheme.gain.opacity(0.17))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.title) chart range")
                }
            }
        }
    }
}

private struct HoldingPriceChart: View {
    let points: [HoldingPricePoint]
    let basePrice: Double?
    let currencyCode: String
    let lineColor: Color
    @Binding var selectedPoint: HoldingPricePoint?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, canvasSize in
                let metrics = ChartMetrics(points: points, size: canvasSize)
                guard metrics.isDrawable else { return }

                if let basePrice,
                   let baseY = metrics.y(for: basePrice) {
                    var baseline = Path()
                    baseline.move(to: CGPoint(x: 0, y: baseY))
                    baseline.addLine(to: CGPoint(x: canvasSize.width, y: baseY))
                    context.stroke(
                        baseline,
                        with: .color(BitternTheme.softLine.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [7, 7])
                    )

                    let label = Text(PortfolioFormat.price(basePrice, currencyCode: currencyCode))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(BitternTheme.secondaryInk.opacity(0.62))
                    context.draw(label, at: CGPoint(x: canvasSize.width - 28, y: max(12, baseY - 16)))
                }

                let activeIndex = selectedPoint.flatMap { metrics.index(of: $0) }
                let fullPath = metrics.path(through: points.indices)

                if let activeIndex {
                    context.stroke(
                        fullPath,
                        with: .color(lineColor.opacity(0.13)),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
                    )

                    let selectedPath = metrics.path(through: 0...activeIndex)
                    context.stroke(
                        selectedPath,
                        with: .color(lineColor),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
                    )
                } else {
                    context.stroke(
                        fullPath,
                        with: .color(lineColor),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
                    )
                }

                let markerIndex = activeIndex ?? points.indices.last
                if let markerIndex,
                   let marker = metrics.location(for: markerIndex) {
                    let outerRect = CGRect(
                        x: marker.x - 19,
                        y: marker.y - 19,
                        width: 38,
                        height: 38
                    )
                    let innerRect = CGRect(
                        x: marker.x - 6.5,
                        y: marker.y - 6.5,
                        width: 13,
                        height: 13
                    )
                    context.fill(Path(ellipseIn: outerRect), with: .color(lineColor.opacity(0.16)))
                    context.fill(Path(ellipseIn: innerRect), with: .color(lineColor))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectedPoint = nearestPoint(to: value.location.x, in: size.width)
                    }
                    .onEnded { _ in
                        selectedPoint = nil
                    }
            )
        }
    }

    private func nearestPoint(to xPosition: CGFloat, in width: CGFloat) -> HoldingPricePoint? {
        guard points.count > 1, width > 0 else { return points.last }
        let clamped = min(max(xPosition, 0), width)
        let progress = clamped / width
        let index = Int((progress * CGFloat(points.count - 1)).rounded())
        return points[min(max(index, 0), points.count - 1)]
    }
}

private struct ChartMetrics {
    let points: [HoldingPricePoint]
    let size: CGSize
    let minPrice: Double
    let maxPrice: Double
    let topInset: CGFloat = 12
    let bottomInset: CGFloat = 28

    init(points: [HoldingPricePoint], size: CGSize) {
        self.points = points
        self.size = size
        let prices = points.map(\.price)
        let minValue = prices.min() ?? 0
        let maxValue = prices.max() ?? 1
        let padding = 0.01
        minPrice = max(0, minValue - padding)
        maxPrice = maxValue + padding
    }

    var isDrawable: Bool {
        points.count >= 2 && size.width > 0 && size.height > topInset + bottomInset
    }

    func index(of point: HoldingPricePoint) -> Int? {
        points.firstIndex(of: point)
    }

    func location(for index: Int) -> CGPoint? {
        guard points.indices.contains(index) else { return nil }
        let x = points.count == 1 ? size.width : CGFloat(index) / CGFloat(points.count - 1) * size.width
        guard let y = y(for: points[index].price) else { return nil }
        return CGPoint(x: x, y: y)
    }

    func y(for price: Double) -> CGFloat? {
        guard maxPrice > minPrice else { return nil }
        let height = size.height - topInset - bottomInset
        let progress = (price - minPrice) / (maxPrice - minPrice)
        return topInset + (1 - CGFloat(progress)) * height
    }

    func path<R: Sequence>(through indices: R) -> Path where R.Element == Int {
        var path = Path()
        var didMove = false

        for index in indices {
            guard let location = location(for: index) else { continue }
            if didMove {
                path.addLine(to: location)
            } else {
                path.move(to: location)
                didMove = true
            }
        }

        return path
    }
}

private struct HoldingInfoSection: View {
    let holding: PortfolioHolding
    let snapshot: PortfolioSnapshot
    let providerName: String
    let isPrivacyEnabled: Bool

    private var allocation: Double {
        guard snapshot.totalMarketValue > 0 else { return 0 }
        return holding.marketValue / snapshot.totalMarketValue
    }

    private var unitLabel: String {
        providerName.lowercased().contains("binance") ? "Tokens" : "Shares"
    }

    private var formattedQuantity: String {
        if let quantityDisplay = holding.quantityDisplay?.trimmingCharacters(in: .whitespacesAndNewlines),
           !quantityDisplay.isEmpty {
            return quantityDisplay
        }

        return preciseQuantity(holding.quantity)
    }

    private var returnEquation: HoldingReturnEquation? {
        guard holding.averageCost > 0, holding.quantity > 0 else {
            return nil
        }

        let dividendsReceived = holding.dividendsReceived ?? 0
        let dividendReturnPercent = holding.costBasis == 0 ? 0 : dividendsReceived / abs(holding.costBasis)
        let totalReturnAmount = holding.allTimeGainAmount + dividendsReceived
        let totalReturnPercent = holding.costBasis == 0 ? 0 : totalReturnAmount / abs(holding.costBasis)

        return HoldingReturnEquation(
            priceGain: HoldingReturnMetric(
                title: "Price Gain",
                amount: holding.allTimeGainAmount,
                percent: holding.allTimeGainPercent
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("My Holdings")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8)

                Text("\(PortfolioFormat.percent(allocation)) of portfolio")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(BitternTheme.blue.opacity(0.86))
                    .clipShape(Capsule())
            }

            VStack(spacing: 0) {
                HoldingInfoRow(
                    title: "Total",
                    value: isPrivacyEnabled ? hiddenDetailMoney(currencyCode: holding.currencyCode) : PortfolioFormat.money(holding.marketValue, currencyCode: holding.currencyCode)
                )

                Divider().overlay(BitternTheme.softLine)

                HoldingInfoRow(
                    title: "Average Price",
                    value: isPrivacyEnabled ? hiddenDetailMoney(currencyCode: holding.currencyCode) : PortfolioFormat.price(holding.averageCost, currencyCode: holding.currencyCode)
                )

                Divider().overlay(BitternTheme.softLine)

                HoldingInfoRow(title: unitLabel, value: formattedQuantity)

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
}

private struct HoldingInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(BitternTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Spacer(minLength: 14)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
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
            .font(.system(size: 23, weight: .regular, design: .rounded))
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
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(BitternTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            VStack(spacing: 2) {
                Text(amountText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(metricColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text(percentText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
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
            ? hiddenDetailMoney(currencyCode: currencyCode)
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

private func formattedSelectionDate(_ date: Date, range: HoldingChartRange) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")

    switch range {
    case .oneDay:
        formatter.dateFormat = "HH:mm"
    case .fiveDays:
        formatter.dateFormat = "d MMM, HH:mm"
    case .threeMonths, .oneYear, .fiveYears, .max:
        formatter.dateFormat = "d MMM, yyyy"
    }

    return formatter.string(from: date)
}

private func hiddenDetailMoney(currencyCode: String) -> String {
    currencyCode == "USD" ? "$••••" : "\(currencyCode) ••••"
}

private func preciseQuantity(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.maximumFractionDigits = 12
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

#if DEBUG
struct HoldingDetailView_Previews: PreviewProvider {
    static var previews: some View {
        HoldingDetailView(
            holding: DemoPortfolio.snapshot.holdings[3],
            snapshot: DemoPortfolio.snapshot,
            providerName: "SnapTrade Demo"
        )
    }
}
#endif
