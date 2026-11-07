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

struct PerformanceLineChartSection<Point: Hashable, RangeOption: Identifiable & Equatable>: View {
    let points: [Point]
    let value: (Point) -> Double
    let xScale: PerformanceChartXScale<Point>
    /// When a point was observed, for the time axis.
    let date: (Point) -> Date
    /// The calendar unit the time axis is labelled in.
    let axisUnit: PerformanceChartAxisUnit
    /// The date of a point, for the cursor and VoiceOver.
    let selectionLabel: (Point) -> String
    /// A value as text, or nil while values are hidden.
    let valueLabel: ((Double) -> String)?
    /// A whole value as text, for the value axis when every one of its
    /// values is whole. Nil uses `valueLabel`.
    var wholeValueLabel: ((Double) -> String)? = nil
    let baseValue: Double?
    let baselineLabel: String?
    let primaryLineValue: Double?
    let lineStyle: (Point) -> PerformanceChartLineStyle
    let ranges: [RangeOption]
    let rangeTitle: (RangeOption) -> String
    @Binding var selectedRange: RangeOption
    @Binding var selectedPoint: Point?
    let isLoading: Bool
    /// Behind the chart, so the cursor's dot can be ringed in it.
    var background: Color = BitternTheme.background

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 280

    private var lineColor: Color {
        guard let baseValue, let primaryLineValue else {
            return BitternTheme.neutralLine
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
                        date: date,
                        axisUnit: axisUnit,
                        selectionLabel: selectionLabel,
                        valueLabel: valueLabel,
                        wholeValueLabel: wholeValueLabel,
                        baseValue: baseValue,
                        baselineLabel: baselineLabel,
                        lineColor: lineColor,
                        lineStyle: lineStyle,
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
                selectedRange: $selectedRange
            ) {
                selectedPoint = nil
            }
            // Six ranges share one row.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
}

/// The ranges as plain labels spread across the row, the chosen one in a
/// light gray capsule that fits its label, so it is the same size whether
/// the row holds four ranges or six. The capsule is neutral: gain or loss
/// is the line's to show, not the control's.
private struct RangeSelector<RangeOption: Identifiable & Equatable>: View {
    let ranges: [RangeOption]
    let title: (RangeOption) -> String
    @Binding var selectedRange: RangeOption
    let didSelect: () -> Void

    @Namespace private var selection
    @ScaledMetric(relativeTo: .subheadline) private var capsuleHeight: CGFloat = 32

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
                        .foregroundStyle(isSelected ? BitternTheme.ink : BitternTheme.secondaryInk)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 52, minHeight: capsuleHeight)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color(uiColor: .tertiarySystemFill))
                                    .matchedGeometryEffect(id: "selection", in: selection)
                            }
                        }
                        // Each range answers to its whole share of the row,
                        // at least 44 pt tall, not just to its capsule.
                        .frame(maxWidth: .infinity, minHeight: 44)
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
    let date: (Point) -> Date
    let axisUnit: PerformanceChartAxisUnit
    let selectionLabel: (Point) -> String
    let valueLabel: ((Double) -> String)?
    let wholeValueLabel: ((Double) -> String)?
    let baseValue: Double?
    let baselineLabel: String?
    let lineColor: Color
    let lineStyle: (Point) -> PerformanceChartLineStyle
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
        let timeTicks = timeTicks(in: geometry)
        // The baseline's own label takes the place of values close to it.
        let valueTicks = geometry.valueTicks(avoiding: baselineLabel == nil ? nil : baseValue)
        let axisValueLabel = valueTicks.allSatisfy { $0 == $0.rounded() }
            ? (wholeValueLabel ?? valueLabel)
            : valueLabel

        Chart {
            if let baseValue {
                RuleMark(y: .value("Baseline", baseValue))
                    .foregroundStyle(BitternTheme.softLine)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
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
                        // Dimmed by mixing into the background rather than
                        // by opacity, so overlapping run ends don't darken.
                        .foregroundStyle(
                            run.isDimmed
                                ? color(for: run.style).mix(with: background, by: 0.8)
                                : color(for: run.style)
                        )
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
            // Each label starts at its boundary and reads as "from here".
            AxisMarks(values: timeTicks.map(\.position)) { mark in
                AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(BitternTheme.softLine)
                AxisValueLabel(anchor: .topLeading) {
                    if let position = mark.as(Double.self),
                       let tick = timeTicks.first(where: { $0.position == position }) {
                        Text(timeLabel(for: tick))
                    }
                }
            }
        }
        .chartYAxis {
            if let axisValueLabel {
                AxisMarks(position: .trailing, values: valueTicks) { mark in
                    AxisValueLabel {
                        if let value = mark.as(Double.self) {
                            Text(axisValueLabel(value))
                        }
                    }
                }
            }
            // The baseline is labelled on the value axis, outside the plot,
            // so the line never runs through its label.
            if let baseValue, let baselineLabel {
                AxisMarks(position: .trailing, values: [baseValue]) { _ in
                    AxisValueLabel {
                        BaselineCapsule(text: baselineLabel)
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
                // A thin line up from the point to a glass capsule with the
                // date. The header above the chart shows the value.
                Rectangle()
                    .fill(color.opacity(0.6))
                    .frame(width: 1, height: max(point.y - plotFrame.minY, 0))
                    .position(x: point.x, y: (plotFrame.minY + point.y) / 2)

                CursorCapsule(text: selectionLabel(points[markerIndex]))
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

    private func announcement(for point: Point) -> String {
        let date = selectionLabel(point)
        guard let valueLabel else { return date }
        return "\(date), \(valueLabel(value(point)))"
    }

    // MARK: - Time axis

    private func timeTicks(in geometry: PerformanceChartGeometry) -> [PerformanceChartTimeTick] {
        let calendar = Calendar.autoupdatingCurrent
        let ticks: [PerformanceChartTimeTick]

        switch xScale {
        case .unavailable:
            return []
        case .indexed:
            ticks = PerformanceChartTimeAxis.indexedTicks(
                dates: points.map(date),
                unit: axisUnit,
                calendar: calendar
            )
        case .time(let domain, _):
            ticks = PerformanceChartTimeAxis.hourBoundaries(
                from: domain.start,
                to: domain.end,
                // The plotted stretch, which is shorter than the domain
                // while a round-the-clock day is still under way.
                visibleDuration: geometry.xDomain.upperBound - geometry.xDomain.lowerBound,
                calendar: calendar
            )
            .compactMap { boundary in
                // A boundary in a no-trade gap has no place on the axis.
                domain.elapsedTime(for: boundary).map {
                    PerformanceChartTimeTick(position: $0, date: boundary, kind: .time)
                }
            }
        }

        return PerformanceChartTimeAxis.spaced(ticks, in: geometry.xDomain)
    }

    private func timeLabel(for tick: PerformanceChartTimeTick) -> String {
        switch tick.kind {
        case .time:
            PortfolioFormat.time(tick.date)
        case .day:
            PortfolioFormat.day(tick.date)
        case .month:
            PortfolioFormat.month(tick.date)
        case .year:
            PortfolioFormat.year(tick.date)
        }
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
            BitternTheme.neutralLine
        }
    }
}

/// The baseline's value on the value axis, set apart from the axis's own
/// values. The capsule reaches out past the label column by its padding,
/// so its text lines up with the values above and below it.
private struct BaselineCapsule: View {
    let text: String

    private static let horizontalPadding: CGFloat = 5

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(BitternTheme.secondaryInk)
            .lineLimit(1)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 1)
            .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
            .offset(x: -Self.horizontalPadding)
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

    /// Round values for the value axis, such as 40.4, 40.6 and 40.8: the
    /// widest round step that still gives three of them. Values at the very
    /// edge, whose labels the chart would clip, are left out, as are values
    /// within a tenth of the axis of `baseValue`, whose own label sits there.
    func valueTicks(avoiding baseValue: Double?) -> [Double] {
        let span = yDomain.upperBound - yDomain.lowerBound
        guard span > 0 else { return [] }

        // 1, 2, 2.5 and 5 times a power of ten, widest first, from the
        // power of ten at or above the whole range.
        let magnitude = pow(10, ceil(log10(span)))
        let steps = [1, 0.5, 0.25, 0.2, 0.1, 0.05, 0.025, 0.02, 0.01].map { $0 * magnitude }

        var ticks: [Double] = []
        for step in steps {
            ticks = values(every: step, span: span)
            if ticks.count >= 3 { break }
        }

        return ticks.filter { value in
            guard let baseValue else { return true }
            return abs(value - baseValue) >= span * 0.1
        }
    }

    private func values(every step: Double, span: Double) -> [Double] {
        let first = Int((yDomain.lowerBound / step).rounded(.up))
        let last = Int((yDomain.upperBound / step).rounded(.down))
        guard first <= last else { return [] }

        // Rounded to the step's own precision so 0.1 + 0.2 style errors don't
        // leak into the labels.
        let precision = pow(10, max(0, -floor(log10(step))) + 3)
        return (first...last)
            .map { (Double($0) * step * precision).rounded() / precision }
            .filter { value in
                value - yDomain.lowerBound >= span * 0.04
                    && yDomain.upperBound - value >= span * 0.04
            }
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
