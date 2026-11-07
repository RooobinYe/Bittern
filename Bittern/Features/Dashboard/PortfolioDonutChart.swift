//
//  PortfolioDonutChart.swift
//  Bittern
//

import SwiftUI

struct PortfolioDonutSection: View {
    let snapshot: PortfolioSnapshot
    let holdingColorLookup: [String: Color]
    let performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let fillsAvailableSpace: Bool
    /// Nil shows the mode without a menu, as in the exported image.
    let selectPerformanceMode: (@MainActor (PerformanceMode) -> Void)?

    @ViewBuilder
    var body: some View {
        if fillsAvailableSpace {
            GeometryReader { proxy in
                let side = max(
                    min(
                        proxy.size.width,
                        proxy.size.height,
                        DashboardLayoutMetrics.maximumChartSide
                    ),
                    1
                )

                chart
                    .frame(width: side, height: side)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        } else {
            chart
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: DashboardLayoutMetrics.maximumChartSide)
                .frame(maxWidth: .infinity)
        }
    }

    private var chart: some View {
        DonutPortfolioChart(
            snapshot: snapshot,
            holdingColorLookup: holdingColorLookup,
            performanceMode: performanceMode,
            isPrivacyEnabled: isPrivacyEnabled,
            selectPerformanceMode: selectPerformanceMode
        )
    }
}

private struct DonutPortfolioChart: View {
    let snapshot: PortfolioSnapshot
    let holdingColorLookup: [String: Color]
    let performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let selectPerformanceMode: (@MainActor (PerformanceMode) -> Void)?

    private var performanceAmount: Double? {
        snapshot.performanceAmount(for: performanceMode)
    }

    private var performancePercent: Double? {
        snapshot.performancePercent(for: performanceMode)
    }

    /// No total means no honest shares, so the ring stays empty.
    private var segments: [DonutSegment] {
        guard snapshot.totalMarketValue != nil else { return [] }
        return DonutSegment.segments(
            for: PortfolioAllocation.slices(of: snapshot.holdings),
            holdingColorLookup: holdingColorLookup
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasSide = min(proxy.size.width, proxy.size.height)
            let labelExtent = min(max(canvasSide * 0.19, 64), 84)
            let labelRadiusFactor = 0.60
            // Solve for the largest ring whose outer labels still fit in the
            // canvas. Keeping label centers close to the ring's outer edge
            // lets the glass capsules refract more of each segment's color.
            let side = max((canvasSide - labelExtent) / (labelRadiusFactor * 2), 1)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let labelRadius = side * labelRadiusFactor
            let strokeWidth = max(side * 0.17, 1)
            let centerSpacing = min(max(side * 0.025, 3), 7)
            let labelScale = min(max(canvasSide / 340, 0.78), 1.08)
            let segments = segments

            ZStack {
                Circle()
                    .stroke(Color(uiColor: .secondarySystemFill), lineWidth: strokeWidth)
                    .frame(width: side, height: side)
                    .position(center)

                // VoiceOver reads the ring as one chart, with the allocation
                // as its value and an audio graph through the descriptor.
                ZStack {
                    ForEach(segments) { segment in
                        DonutSegmentShape(
                            startAngle: .degrees(segment.startAngle),
                            endAngle: .degrees(segment.endAngle)
                        )
                        .stroke(segment.color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))
                        .frame(width: side, height: side)
                        .position(center)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Allocation")
                .accessibilityValue(allocationSummary(segments))
                .accessibilityChartDescriptor(
                    AllocationChartDescriptor(slices: segments.map { ($0.symbol, $0.share) })
                )

                VStack(spacing: centerSpacing) {
                    Text(totalMarketValueText)
                        .font(.keyFigure(.title, weight: .bold))
                        .foregroundStyle(BitternTheme.ink)
                        .lineLimit(1)
                        // The ring's hole is a fixed size; at large text sizes
                        // the total must shrink to stay inside it.
                        .minimumScaleFactor(0.5)

                    Text(performanceText)
                        .font(.keyFigure(.headline))
                        .foregroundStyle(BitternTheme.performanceColor(performanceAmount))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    performanceModeControl
                }
                .frame(width: side * 0.62)
                // The ring's hole doesn't grow with the text, so the centre
                // stops growing where its figures would no longer fit.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .position(center)

                GlassEffectContainer {
                    BubbleRingLayout(radius: labelRadius, outerRingOffset: 36 * labelScale) {
                        ForEach(segments) { segment in
                            AllocationBubble(
                                symbol: segment.symbol,
                                logoURL: segment.logoURL,
                                percent: segment.share,
                                color: segment.color,
                                scale: labelScale
                            )
                            .preferredBubbleAngle(segment.midAngle * .pi / 180)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                // Bubbles past this size would cover the ring and each other.
                // VoiceOver reads the same shares from the ring itself.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .accessibilityHidden(true)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func allocationSummary(_ segments: [DonutSegment]) -> String {
        segments
            .map { "\($0.symbol) \(PortfolioFormat.percent($0.share, fractionDigits: 0))" }
            .joined(separator: ", ")
    }

    @ViewBuilder
    private var performanceModeControl: some View {
        let label = PerformanceModeLabel(title: performanceMode.title)
        if let selectPerformanceMode {
            Menu {
                Picker("Return", selection: Binding(
                    get: { performanceMode },
                    set: selectPerformanceMode
                )) {
                    ForEach(PerformanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                label
            }
            .accessibilityLabel("Return")
            .accessibilityValue(performanceMode.title)
        } else {
            label
        }
    }

    private var performanceText: String {
        guard let performanceAmount, let performancePercent else { return PortfolioFormat.missing }

        if isPrivacyEnabled {
            return PortfolioFormat.hiddenChange(
                amount: performanceAmount,
                percent: performancePercent,
                currencyCode: snapshot.currencyCode
            )
        }

        return PortfolioFormat.change(performanceAmount, percent: performancePercent, currencyCode: snapshot.currencyCode)
    }

    private var totalMarketValueText: String {
        guard let totalMarketValue = snapshot.totalMarketValue else { return PortfolioFormat.missing }
        return isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: snapshot.currencyCode)
            : PortfolioFormat.wholeMoney(totalMarketValue, currencyCode: snapshot.currencyCode)
    }
}

/// The allocation for VoiceOver's audio graph and chart summary: each slice's
/// share of the portfolio.
private struct AllocationChartDescriptor: AXChartDescriptorRepresentable {
    let slices: [(symbol: String, share: Double)]

    func makeChartDescriptor() -> AXChartDescriptor {
        let symbols = slices.map(\.symbol)
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Holding",
            categoryOrder: symbols
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Share of portfolio",
            range: 0...100,
            gridlinePositions: []
        ) { value in
            PortfolioFormat.percent(value / 100, fractionDigits: 0)
        }
        let series = AXDataSeriesDescriptor(
            name: "Allocation",
            isContinuous: false,
            dataPoints: slices.map { slice in
                AXDataPoint(x: slice.symbol, y: slice.share * 100)
            }
        )

        return AXChartDescriptor(
            title: "Allocation",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }

}

/// A slice of the allocation as drawn: its arc and its label's color.
private struct DonutSegment: Identifiable {
    let id: String
    let symbol: String
    let logoURL: URL?
    let share: Double
    let startAngle: Double
    let endAngle: Double
    let color: Color

    var midAngle: Double {
        (startAngle + endAngle) / 2
    }

    /// Arcs start at twelve o'clock and run clockwise, separated by a small
    /// gap that narrow slices give up first.
    static func segments(
        for slices: [PortfolioAllocation.Slice],
        holdingColorLookup: [String: Color]
    ) -> [DonutSegment] {
        guard !slices.isEmpty else { return [] }

        var cursor = -90.0
        let gap = 2.2
        let shrink = gap / 2 * Double(slices.count - 1) / Double(slices.count)

        return slices.map { slice in
            let span = slice.share * 360
            let inset = min(shrink, span * 0.18)
            let startAngle = cursor + inset
            let endAngle = cursor + span - inset
            cursor += span

            switch slice.kind {
            case .holding(let holding):
                return DonutSegment(
                    id: slice.id,
                    symbol: holding.symbol,
                    logoURL: holding.logoURL,
                    share: slice.share,
                    startAngle: startAngle,
                    endAngle: max(startAngle, endAngle),
                    color: holdingColorLookup[holding.id] ?? BitternTheme.allocationColor(at: 0)
                )
            case .other:
                return DonutSegment(
                    id: slice.id,
                    symbol: AllocationBubble.otherSymbol,
                    logoURL: nil,
                    share: slice.share,
                    startAngle: startAngle,
                    endAngle: max(startAngle, endAngle),
                    color: BitternTheme.otherAllocationColor
                )
            }
        }
    }
}

private struct PerformanceModeLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .accessibilityHidden(true)
        }
        .foregroundStyle(BitternTheme.secondaryInk)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

nonisolated private struct DonutSegmentShape: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

private struct AllocationBubble: View {
    static let otherSymbol = "OTHER"

    let symbol: String
    let logoURL: URL?
    let percent: Double
    let color: Color
    let scale: CGFloat

    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 24

    private var isOther: Bool { symbol == Self.otherSymbol }

    var body: some View {
        HStack(spacing: 5 * scale) {
            HoldingSymbolIcon(
                symbol: symbol,
                logoURL: logoURL,
                color: isOther ? BitternTheme.ink : color,
                size: iconSize * scale,
                fallbackLabel: isOther ? Self.otherSymbol : String(symbol.prefix(4))
            )

            Text(PortfolioFormat.percent(percent, fractionDigits: 0))
                .font(.keyFigure(.caption2, weight: .semibold))
                .foregroundStyle(BitternTheme.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 4 * scale)
        .padding(.trailing, 7 * scale)
        .frame(minHeight: (iconSize + 10) * scale)
        .glassEffect(.clear, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(symbol), \(PortfolioFormat.percent(percent, fractionDigits: 0))")
    }
}

extension PerformanceMode {
    var systemImage: String {
        switch self {
        case .today:
            "sun.max"
        case .allTime:
            "clock.arrow.circlepath"
        }
    }
}
