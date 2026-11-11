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

/// The dot at the latest point while nothing is selected.
nonisolated enum PerformanceChartEndMarker: Equatable {
    /// A filled dot.
    case plain
    /// A filled dot with a ring spreading from it: the price is moving
    /// now. Plain under Reduce Motion.
    case live
    /// A hollow gray dot: the line isn't current.
    case stale
}

/// What the chart area shows while it has no line to draw.
enum PerformanceChartPlaceholder {
    case none
    /// One block over the plot and both axes, for a range on its way.
    case loading
    /// A range that couldn't load for want of a network.
    case unavailableOffline
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
    /// The values the value axis covers, when it should hold still: it
    /// then widens only when a value leaves it. Nil fits the points.
    var valueBounds: ClosedRange<Double>? = nil
    var endMarker = PerformanceChartEndMarker.plain
    /// A gray line, for data that isn't current.
    var isStale = false
    /// What shows in place of the line. `.none` keeps the spinner while
    /// `isLoading`.
    var placeholder = PerformanceChartPlaceholder.none
    var plotHeight = PerformanceChartPlotHeight.standard
    /// False when the screen places the ranges itself, as below a fold.
    var showsRangeSelector = true

    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 280

    private var lineColor: Color {
        guard !isStale, let baseValue, let primaryLineValue else {
            return BitternTheme.neutralLine
        }

        return BitternTheme.performanceColor(primaryLineValue - baseValue)
    }

    var body: some View {
        VStack(spacing: 16) {
            Group {
                switch placeholder {
                case .loading:
                    SkeletonBlock(cornerRadius: 16)
                        .accessibilityElement()
                        .accessibilityLabel("Loading chart")
                case .unavailableOffline:
                    OfflineChartPlaceholder()
                case .none:
                    chartOrState
                }
            }
            .modifier(PlotHeightModifier(plotHeight: plotHeight, standardHeight: min(chartHeight, 420)))
            .frame(maxWidth: .infinity)
            // Axis labels past this size would leave no room for the line.
            // VoiceOver reads each point's date and value instead.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            if showsRangeSelector {
                ChartRangeSelector(
                    ranges: ranges,
                    title: rangeTitle,
                    selectedRange: $selectedRange
                ) {
                    selectedPoint = nil
                }
            }
        }
    }

    @ViewBuilder
    private var chartOrState: some View {
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
                valueBounds: valueBounds,
                endMarker: endMarker,
                selectedPoint: $selectedPoint
            )
        }
    }
}

/// How tall the plot is.
enum PerformanceChartPlotHeight {
    /// A fixed height that grows with the text size, as in a scrolling page.
    case standard
    /// The height the screen leaves, for a chart that sits beside other
    /// content and doesn't scroll.
    case fill
}

private struct PlotHeightModifier: ViewModifier {
    let plotHeight: PerformanceChartPlotHeight
    let standardHeight: CGFloat

    /// Below this the line and its axes have no room to read.
    private static let minimumFillHeight: CGFloat = 160

    func body(content: Content) -> some View {
        switch plotHeight {
        case .standard:
            content.frame(height: standardHeight)
        case .fill:
            content.frame(minHeight: Self.minimumFillHeight, maxHeight: .infinity)
        }
    }
}

/// A range that has never loaded and can't while there is no network.
private struct OfflineChartPlaceholder: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.title2)
                .foregroundStyle(BitternTheme.secondaryInk)
                .accessibilityHidden(true)
            Text("Chart unavailable offline")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BitternTheme.ink)
            Text("It loads when you’re back online.")
                .font(.footnote)
                .foregroundStyle(BitternTheme.secondaryInk)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BitternTheme.skeleton, in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The ranges as plain labels spread across the row, the chosen one in a
/// light gray capsule that fits its label, so it is the same size whether
/// the row holds four ranges or eight. The labels sit an equal distance
/// apart, so a wide "MAX" doesn't crowd its neighbours the way equal
/// columns would; in a wide row they stop spreading and gather in the
/// middle. When even that doesn't fit (large text), the row scrolls
/// instead of truncating. The capsule is neutral: gain or loss is the
/// line's to show, not the control's.
struct ChartRangeSelector<RangeOption: Identifiable & Equatable>: View {
    let ranges: [RangeOption]
    let title: (RangeOption) -> String
    @Binding var selectedRange: RangeOption
    let didSelect: () -> Void

    @Namespace private var selection
    @ScaledMetric(relativeTo: .subheadline) private var capsuleHeight: CGFloat = 32

    var body: some View {
        rows
            // Up to eight ranges share one row, scrolling past that.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var rows: some View {
        ViewThatFits(in: .horizontal) {
            row

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    row
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    proxy.scrollTo(selectedRange.id, anchor: .center)
                }
                .onChange(of: selectedRange) { _, range in
                    withAnimation {
                        proxy.scrollTo(range.id, anchor: .center)
                    }
                }
            }
        }
    }

    private var row: some View {
        // A capsule's height apart at most, so four ranges on a wide
        // screen read as one control rather than four strays.
        RangeRowLayout(maximumSpare: capsuleHeight) {
            ForEach(ranges) { option in
                rangeButton(option)
                    .id(option.id)
            }
        }
    }

    private func rangeButton(_ option: RangeOption) -> some View {
        let isSelected = selectedRange == option

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedRange = option
                didSelect()
            }
        } label: {
            // The label is as wide as its semibold self either way, so
            // choosing a range doesn't nudge the others along the row.
            Text(title(option))
                .font(.subheadline.weight(.semibold))
                .hidden()
                .overlay {
                    Text(title(option))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? BitternTheme.ink : BitternTheme.secondaryInk)
                }
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minWidth: capsuleHeight, minHeight: capsuleHeight)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .matchedGeometryEffect(id: "selection", in: selection)
                    }
                }
                // Each range answers to its whole share of the row, at
                // least 44 pt tall, not just to its capsule.
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(title(option)) range")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Places each range at its own width and shares the row's spare width out
/// evenly among them, so the gaps between labels match, up to
/// `maximumSpare` each; what is left over sits evenly at both ends.
/// Without a width to fill, it asks for the labels' total, which is how
/// `ViewThatFits` knows when to fall back to scrolling.
struct RangeRowLayout: Layout {
    let maximumSpare: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let idealWidth = sizes.reduce(0) { $0 + $1.width }
        let height = sizes.map(\.height).max() ?? 0

        guard let width = proposal.width, width.isFinite else {
            return CGSize(width: idealWidth, height: height)
        }
        return CGSize(width: max(width, idealWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }

        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let frames = Self.slots(widths: widths, in: bounds.width, maximumSpare: maximumSpare)

        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: frame.width, height: bounds.height)
            )
        }
    }

    /// Each range's slot along the row, from the row's leading edge: its
    /// own width plus its share of the spare width.
    nonisolated static func slots(
        widths: [CGFloat],
        in rowWidth: CGFloat,
        maximumSpare: CGFloat
    ) -> [(minX: CGFloat, width: CGFloat)] {
        guard !widths.isEmpty else { return [] }
        let total = widths.reduce(0, +)
        let spare = min(max(0, rowWidth - total) / CGFloat(widths.count), maximumSpare)
        var x = max(0, rowWidth - total - spare * CGFloat(widths.count)) / 2

        return widths.map { width in
            defer { x += width + spare }
            return (minX: x, width: width + spare)
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
    let valueBounds: ClosedRange<Double>?
    let endMarker: PerformanceChartEndMarker
    @Binding var selectedPoint: Point?

    @State private var rawSelection: Double?

    var body: some View {
        let geometry = PerformanceChartGeometry(
            values: points.map(value),
            positions: points.indices.map(position(at:)),
            xExtent: xExtent,
            baseValue: baseValue,
            valueBounds: valueBounds
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

            let marker = selectedIndex == nil ? endMarker : .plain
            ZStack {
                if marker == .live {
                    PulsingRing(color: color)
                }
                if marker == .stale {
                    Circle()
                        .fill(background)
                        .frame(width: 9, height: 9)
                        .overlay {
                            Circle().stroke(BitternTheme.neutralLine, lineWidth: 2)
                        }
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 9, height: 9)
                        .overlay {
                            Circle().stroke(background, lineWidth: 2.5)
                        }
                }
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

    /// A time axis covers its whole domain, so a session in progress stops
    /// short of its scheduled close. Indexed points fill the axis.
    private var xExtent: ClosedRange<Double>? {
        switch xScale {
        case .unavailable, .indexed:
            return nil
        case .time(let domain, _):
            return 0...domain.duration
        }
    }

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

/// A ring spreading from the latest point and fading, every 1.6 seconds,
/// while its price moves. Drawn from the clock rather than animated, so the
/// dot it surrounds moves to a new price without an animation. Nothing
/// under Reduce Motion.
private struct PulsingRing: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: TimeInterval = 1.6

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.period) / Self.period
                // Eased out, as the ring slows while it spreads.
                let progress = 1 - pow(1 - phase, 3)
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .scaleEffect(1 + 1.8 * progress)
                    .opacity(0.55 * (1 - progress))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

    /// - Parameters:
    ///   - xExtent: The positions the horizontal axis must cover, when it
    ///     should reach past the plotted points rather than fit them.
    ///   - valueBounds: The values the value axis must cover, when it
    ///     should hold still rather than fit `values`.
    init(
        values: [Double],
        positions: [Double?],
        xExtent: ClosedRange<Double>? = nil,
        baseValue: Double?,
        valueBounds: ClosedRange<Double>? = nil
    ) {
        self.values = values
        self.positions = positions

        var plotted = positions.compactMap { $0 }
        if let xExtent {
            plotted += [xExtent.lowerBound, xExtent.upperBound]
        }
        xDomain = (plotted.min() ?? 0)...max(plotted.max() ?? 1, (plotted.min() ?? 0) + 1)

        var range = valueBounds.map { [$0.lowerBound, $0.upperBound] } ?? values
        if let baseValue {
            range.append(baseValue)
        }
        yDomain = Self.valueDomain(low: range.min() ?? 0, high: range.max() ?? 1)
    }

    /// The value axis for values from `low` to `high`, with headroom above
    /// the line for the cursor's capsule.
    static func valueDomain(low: Double, high: Double) -> ClosedRange<Double> {
        let span = high > low ? high - low : max(abs(high) * 0.01, 0.01)
        return max(0, low - span * 0.08)...(high + span * 0.2)
    }

    /// `bounds` once `value` is plotted against them: the same while the
    /// value axis they give already covers it, so the axis holds still,
    /// and widened to take it only when it leaves the axis.
    static func valueBounds(
        _ bounds: ClosedRange<Double>,
        including value: Double
    ) -> ClosedRange<Double> {
        guard value.isFinite,
              !valueDomain(low: bounds.lowerBound, high: bounds.upperBound).contains(value)
        else {
            return bounds
        }
        return min(bounds.lowerBound, value)...max(bounds.upperBound, value)
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
