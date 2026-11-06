//
//  PerformanceLineChartSection.swift
//  Bittern
//

import Charts
import SwiftUI

nonisolated enum PerformanceChartLineStyle: Equatable {
    /// Colored by gain or loss.
    case primary
    /// Gray: extended hours, and the segment joining them to the regular
    /// session, which belongs to neither.
    case neutral
}

enum PerformanceChartXScale<Point> {
    case unavailable
    case indexed
    case time(domain: PriceChartTimeDomain, timestamp: (Point) -> Date)

    var isValid: Bool {
        switch self {
        case .unavailable:
            return false
        case .indexed:
            return true
        case .time(let domain, _):
            return domain.duration > 0
        }
    }
}

/// How the chart marks the point being inspected.
enum PerformanceChartCursorStyle: CaseIterable {
    /// A thin line up from the point to a glass capsule with the date.
    case dateCapsule
    /// The same, with the value beside the date.
    case dateAndValueCapsule
    /// A line through the whole plot height, with the date capsule on top.
    case fullHeightLine
}

struct PerformanceLineChartSection<Point: Hashable, RangeOption: Identifiable & Equatable>: View {
    let points: [Point]
    let value: (Point) -> Double
    let xScale: PerformanceChartXScale<Point>
    /// A short label for a point on the horizontal axis, such as a time or day.
    let axisLabel: (Point) -> String
    /// The date of a point, for the cursor and VoiceOver.
    let selectionLabel: (Point) -> String
    /// A value as text, or nil while values are hidden.
    let valueLabel: ((Double) -> String)?
    let baseValue: Double?
    let baselineLabel: String?
    let primaryLineValue: Double?
    let lineStyle: (Point) -> PerformanceChartLineStyle
    let ranges: [RangeOption]
    let rangeTitle: (RangeOption) -> String
    @Binding var selectedRange: RangeOption
    @Binding var selectedPoint: Point?
    let isLoading: Bool
    var cursorStyle: PerformanceChartCursorStyle = .dateCapsule
    /// Behind the chart, so the cursor's dot can be ringed in it.
    var background: Color = BitternTheme.background

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 280

    private var lineColor: Color {
        guard let baseValue, let primaryLineValue else {
            return BitternTheme.secondaryInk
        }

        return BitternTheme.performanceColor(primaryLineValue - baseValue)
    }

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if isLoading {
                    ProgressView()
                } else if points.count < 2 || !xScale.isValid {
                    ContentUnavailableView("No Chart Data", systemImage: "chart.xyaxis.line")
                } else {
                    PerformanceLineChart(
                        points: points,
                        value: value,
                        xScale: xScale,
                        axisLabel: axisLabel,
                        selectionLabel: selectionLabel,
                        valueLabel: valueLabel,
                        baseValue: baseValue,
                        baselineLabel: baselineLabel,
                        lineColor: lineColor,
                        lineStyle: lineStyle,
                        cursorStyle: cursorStyle,
                        background: background,
                        selectedPoint: $selectedPoint
                    )
                }
            }
            .frame(height: min(chartHeight, 420))
            .frame(maxWidth: .infinity)
            // Axis labels past this size would leave no room for the line.
            // VoiceOver reads each point's date and value instead.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            RangeSelector(
                ranges: ranges,
                title: rangeTitle,
                selectedRange: $selectedRange,
                selectedColor: lineColor
            ) {
                selectedPoint = nil
            }
            // Six ranges share one row.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
}

private struct RangeSelector<RangeOption: Identifiable & Equatable>: View {
    let ranges: [RangeOption]
    let title: (RangeOption) -> String
    @Binding var selectedRange: RangeOption
    let selectedColor: Color
    let didSelect: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ranges) { option in
                let isSelected = selectedRange == option
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedRange = option
                        didSelect()
                    }
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? selectedColor : BitternTheme.secondaryInk)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(selectedColor.opacity(0.15))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(title(option)) range")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

private struct PerformanceLineChart<Point: Hashable>: View {
    let points: [Point]
    let value: (Point) -> Double
    let xScale: PerformanceChartXScale<Point>
    let axisLabel: (Point) -> String
    let selectionLabel: (Point) -> String
    let valueLabel: ((Double) -> String)?
    let baseValue: Double?
    let baselineLabel: String?
    let lineColor: Color
    let lineStyle: (Point) -> PerformanceChartLineStyle
    let cursorStyle: PerformanceChartCursorStyle
    let background: Color
    @Binding var selectedPoint: Point?

    @State private var rawSelection: Double?

    var body: some View {
        let geometry = PerformanceChartGeometry(
            values: points.map(value),
            positions: points.indices.map(position(at:)),
            baseValue: baseValue
        )
        let selectedIndex = selectedPoint.flatMap { points.firstIndex(of: $0) }
        let runs = PerformanceChartRuns.runs(
            styles: points.map(lineStyle),
            isPlotted: geometry.positions.map { $0 != nil },
            selectedIndex: selectedIndex
        )

        Chart {
            if let baseValue {
                RuleMark(y: .value("Baseline", baseValue))
                    .foregroundStyle(BitternTheme.softLine)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        if let baselineLabel {
                            Text(baselineLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHidden(true)
            }

            ForEach(Array(runs.enumerated()), id: \.offset) { runIndex, run in
                ForEach(run.indices, id: \.self) { index in
                    if let position = geometry.positions[index] {
                        LineMark(
                            x: .value("Time", position),
                            y: .value("Value", geometry.values[index]),
                            series: .value("Run", runIndex)
                        )
                        .foregroundStyle(color(for: run.style).opacity(run.isDimmed ? 0.2 : 1))
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .accessibilityLabel(selectionLabel(points[index]))
                        .accessibilityValue(valueLabel?(geometry.values[index]) ?? "Hidden")
                    }
                }
            }
        }
        .chartXScale(domain: geometry.xDomain)
        .chartYScale(domain: geometry.yDomain)
        .chartXAxis {
            AxisMarks(values: geometry.axisTickIndices.compactMap { geometry.positions[$0] }) { mark in
                AxisValueLabel {
                    if let position = mark.as(Double.self),
                       let index = geometry.nearestIndex(to: position) {
                        Text(axisLabel(points[index]))
                    }
                }
            }
        }
        .chartYAxis {
            if let valueLabel {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { mark in
                    AxisValueLabel {
                        if let value = mark.as(Double.self) {
                            Text(valueLabel(value))
                        }
                    }
                }
            }
        }
        .chartXSelection(value: $rawSelection)
        .chartOverlay { proxy in
            GeometryReader { reader in
                if let plotAnchor = proxy.plotFrame {
                    cursor(
                        plotFrame: reader[plotAnchor],
                        proxy: proxy,
                        geometry: geometry,
                        selectedIndex: selectedIndex
                    )
                }
            }
            .allowsHitTesting(false)
        }
        .onChange(of: rawSelection) { _, newValue in
            selectedPoint = newValue
                .flatMap { geometry.nearestIndex(to: $0) }
                .map { points[$0] }
        }
        .onChange(of: selectedPoint) { _, newValue in
            if newValue == nil {
                rawSelection = nil
            } else if let newValue {
                AccessibilityNotification.Announcement(announcement(for: newValue)).post()
            }
        }
    }

    // MARK: - Cursor

    /// The latest point while nothing is selected; the selected point with
    /// its line and date capsule while dragging.
    @ViewBuilder
    private func cursor(
        plotFrame: CGRect,
        proxy: ChartProxy,
        geometry: PerformanceChartGeometry,
        selectedIndex: Int?
    ) -> some View {
        let markerIndex = selectedIndex ?? geometry.lastPlottedIndex
        if let markerIndex,
           let position = geometry.positions[markerIndex],
           let x = proxy.position(forX: position),
           let y = proxy.position(forY: geometry.values[markerIndex]) {
            let point = CGPoint(x: plotFrame.minX + x, y: plotFrame.minY + y)
            let color = color(for: lineStyle(points[markerIndex]))

            if selectedIndex != nil {
                let lineBottom = cursorStyle == .fullHeightLine ? plotFrame.maxY : point.y
                Rectangle()
                    .fill(color.opacity(0.6))
                    .frame(width: 1, height: max(lineBottom - plotFrame.minY, 0))
                    .position(x: point.x, y: (plotFrame.minY + lineBottom) / 2)

                CursorCapsule(
                    text: capsuleText(for: markerIndex, geometry: geometry)
                )
                .fixedSize()
                .position(
                    x: min(max(point.x, plotFrame.minX + 60), plotFrame.maxX - 60),
                    y: plotFrame.minY
                )
            }

            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle().stroke(background, lineWidth: 2.5)
                }
                .position(point)
        }
    }

    private func capsuleText(for index: Int, geometry: PerformanceChartGeometry) -> String {
        let date = selectionLabel(points[index])
        guard cursorStyle == .dateAndValueCapsule,
              let valueLabel
        else {
            return date
        }
        return "\(date)\(PortfolioFormat.separator)\(valueLabel(geometry.values[index]))"
    }

    private func announcement(for point: Point) -> String {
        let date = selectionLabel(point)
        guard let valueLabel else { return date }
        return "\(date), \(valueLabel(value(point)))"
    }

    // MARK: - Scales

    private func position(at index: Int) -> Double? {
        switch xScale {
        case .unavailable:
            return nil
        case .indexed:
            return Double(index)
        case .time(let domain, let timestamp):
            return domain.elapsedTime(for: timestamp(points[index]))
        }
    }

    private func color(for style: PerformanceChartLineStyle) -> Color {
        switch style {
        case .primary:
            lineColor
        case .neutral:
            BitternTheme.secondaryInk
        }
    }
}

private struct CursorCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(BitternTheme.ink)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Where the chart's points sit and what range its axes cover.
nonisolated struct PerformanceChartGeometry {
    let values: [Double]
    /// Each point's horizontal position, or nil when it falls outside the
    /// chart's time domain.
    let positions: [Double?]
    let xDomain: ClosedRange<Double>
    let yDomain: ClosedRange<Double>

    init(values: [Double], positions: [Double?], baseValue: Double?) {
        self.values = values
        self.positions = positions

        let plotted = positions.compactMap { $0 }
        xDomain = (plotted.min() ?? 0)...max(plotted.max() ?? 1, (plotted.min() ?? 0) + 1)

        var range = values
        if let baseValue {
            range.append(baseValue)
        }
        let low = range.min() ?? 0
        let high = range.max() ?? 1
        let span = high > low ? high - low : max(abs(high) * 0.01, 0.01)
        // Headroom above the line for the cursor's capsule.
        yDomain = max(0, low - span * 0.08)...(high + span * 0.2)
    }

    var lastPlottedIndex: Int? {
        positions.lastIndex { $0 != nil }
    }

    func nearestIndex(to position: Double) -> Int? {
        positions.indices
            .filter { positions[$0] != nil }
            .min { abs(positions[$0]! - position) < abs(positions[$1]! - position) }
    }

    /// Four labelled points, inset from the edges so no label is clipped.
    var axisTickIndices: [Int] {
        let span = xDomain.upperBound - xDomain.lowerBound
        let indices = [0.125, 0.375, 0.625, 0.875].compactMap { fraction in
            nearestIndex(to: xDomain.lowerBound + span * fraction)
        }
        var seen = Set<Int>()
        return indices.filter { seen.insert($0).inserted }
    }
}

/// A stretch of the line drawn in one style.
nonisolated struct PerformanceChartRun: Equatable {
    let indices: [Int]
    let style: PerformanceChartLineStyle
    /// After the selected point, the line fades so the selection stands out.
    let isDimmed: Bool
}

nonisolated enum PerformanceChartRuns {
    /// Splits the line into runs that each keep one style.
    ///
    /// The segment between two points of different styles is its own neutral
    /// run, and the line after `selectedIndex` is dimmed. Neighbouring runs
    /// share their boundary point so the line stays continuous. Points that
    /// aren't plotted break the line.
    static func runs(
        styles: [PerformanceChartLineStyle],
        isPlotted: [Bool],
        selectedIndex: Int?
    ) -> [PerformanceChartRun] {
        precondition(styles.count == isPlotted.count)
        guard styles.count >= 2 else { return [] }

        var runs: [PerformanceChartRun] = []
        for start in 0..<(styles.count - 1) {
            let end = start + 1
            guard isPlotted[start], isPlotted[end] else { continue }

            let style = styles[start] == styles[end] ? styles[start] : .neutral
            let isDimmed = selectedIndex.map { start >= $0 } ?? false

            if let last = runs.last,
               last.indices.last == start,
               last.style == style,
               last.isDimmed == isDimmed {
                runs[runs.count - 1] = PerformanceChartRun(
                    indices: last.indices + [end],
                    style: style,
                    isDimmed: isDimmed
                )
            } else {
                runs.append(PerformanceChartRun(indices: [start, end], style: style, isDimmed: isDimmed))
            }
        }
        return runs
    }
}
