//
//  PerformanceLineChartSection.swift
//  Bittern
//

import SwiftUI

enum PerformanceChartLineStyle: Equatable {
    case primary
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
    let baseValue: Double?
    let baselineLabel: String?
    let primaryLineValue: Double?
    let lineStyle: (Point) -> PerformanceChartLineStyle
    let ranges: [RangeOption]
    let rangeTitle: (RangeOption) -> String
    @Binding var selectedRange: RangeOption
    @Binding var selectedPoint: Point?
    let isLoading: Bool

    private var lineColor: Color {
        guard let baseValue, let primaryLineValue else {
            return BitternTheme.secondaryInk
        }

        return BitternTheme.performanceColor(primaryLineValue - baseValue)
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
                } else if points.count < 2 || !xScale.isValid {
                    Text("N/A")
                        .font(.title3.bold())
                        .foregroundStyle(BitternTheme.secondaryInk)
                        .frame(height: 318)
                        .frame(maxWidth: .infinity)
                } else {
                    PerformanceLineChart(
                        points: points,
                        value: value,
                        xScale: xScale,
                        baseValue: baseValue,
                        baselineLabel: baselineLabel,
                        lineColor: lineColor,
                        lineStyle: lineStyle,
                        selectedPoint: $selectedPoint
                    )
                    .frame(height: 318)
                    .padding(.horizontal, -performanceChartSideInset)
                }
            }

            HStack(spacing: 0) {
                ForEach(ranges) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedRange = option
                            selectedPoint = nil
                        }
                    } label: {
                        Text(rangeTitle(option))
                            .font(.title3.bold())
                            .foregroundStyle(selectedRange == option ? lineColor : BitternTheme.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background {
                                if selectedRange == option {
                                    Capsule()
                                        .fill(lineColor.opacity(0.17))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(rangeTitle(option)) chart range")
                }
            }
        }
    }
}

private struct PerformanceLineChart<Point: Hashable>: View {
    let points: [Point]
    let value: (Point) -> Double
    let xScale: PerformanceChartXScale<Point>
    let baseValue: Double?
    let baselineLabel: String?
    let lineColor: Color
    let lineStyle: (Point) -> PerformanceChartLineStyle
    @Binding var selectedPoint: Point?

    private var precomputedMinMax: (min: Double, max: Double) {
        var values = points.map(value)
        if let baseValue {
            values.append(baseValue)
        }

        guard let minValue = values.min(),
              let maxValue = values.max()
        else {
            return (0, 1)
        }

        let padding = 0.01
        return (max(0, minValue - padding), maxValue + padding)
    }

    var body: some View {
        let minMax = precomputedMinMax

        GeometryReader { proxy in
            let size = proxy.size
            let metrics = PerformanceChartMetrics(
                points: points,
                value: value,
                xScale: xScale,
                size: size,
                minValue: minMax.min,
                maxValue: minMax.max
            )
            let activeIndex = selectedPoint.flatMap { metrics.index(of: $0) }

            ZStack {
                Canvas { context, canvasSize in
                    guard metrics.isDrawable else { return }

                    if let baseValue,
                       let baseY = metrics.y(for: baseValue) {
                        var baseline = Path()
                        baseline.move(to: CGPoint(x: metrics.sideInset, y: baseY))
                        baseline.addLine(to: CGPoint(x: canvasSize.width - metrics.sideInset, y: baseY))
                        context.stroke(
                            baseline,
                            with: .color(BitternTheme.softLine.opacity(0.55)),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [7, 7])
                        )

                        if let baselineLabel {
                            let label = Text(baselineLabel)
                                .font(.footnote.bold().monospacedDigit())
                                .foregroundColor(BitternTheme.secondaryInk.opacity(0.62))
                            context.draw(
                                label,
                                at: CGPoint(x: canvasSize.width - metrics.sideInset - 28, y: max(12, baseY - 16))
                            )
                        }
                    }

                    if let activeIndex {
                        stroke(
                            context: context,
                            metrics: metrics,
                            indices: points.indices,
                            opacity: 0.13
                        )

                        stroke(
                            context: context,
                            metrics: metrics,
                            indices: 0...activeIndex,
                            opacity: 1
                        )
                    } else {
                        stroke(
                            context: context,
                            metrics: metrics,
                            indices: points.indices,
                            opacity: 1
                        )
                    }
                }

                let markerIndex = activeIndex ?? points.indices.last
                if let markerIndex,
                   let marker = metrics.location(for: markerIndex) {
                    Circle()
                        .fill(color(for: points[markerIndex]))
                        .frame(width: 13, height: 13)
                        .frame(width: 38, height: 38)
                        .glassEffect(.regular, in: .circle)
                        .position(marker)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        selectedPoint = metrics.nearestPoint(to: drag.location.x)
                    }
                    .onEnded { _ in
                        selectedPoint = nil
                    }
            )
        }
    }

    private func stroke<R: Sequence>(
        context: GraphicsContext,
        metrics: PerformanceChartMetrics<Point>,
        indices: R,
        opacity: Double
    ) where R.Element == Int {
        let indices = Array(indices)
        guard indices.count >= 2 else { return }

        let strokeStyle = StrokeStyle(
            lineWidth: 4.5,
            lineCap: .round,
            lineJoin: .round
        )
        context.stroke(
            metrics.path(through: indices),
            with: shading(
                metrics: metrics,
                indices: indices,
                opacity: opacity
            ),
            style: strokeStyle
        )
    }

    private func shading(
        metrics: PerformanceChartMetrics<Point>,
        indices: [Int],
        opacity: Double
    ) -> GraphicsContext.Shading {
        var currentStyle = lineStyle(points[indices[0]])
        var stops = [
            Gradient.Stop(
                color: color(for: currentStyle).opacity(opacity),
                location: 0
            )
        ]

        for offset in 1..<indices.count {
            let nextStyle = lineStyle(points[indices[offset]])
            guard nextStyle != currentStyle,
                  let transitionStart = metrics.horizontalProgress(
                    for: indices[offset - 1]
                  ),
                  let nextPointLocation = metrics.horizontalProgress(
                    for: indices[offset]
                  )
            else {
                continue
            }

            let transitionEnd = min(
                nextPointLocation,
                transitionStart
                    + performanceChartMaximumTransitionWidth / metrics.plotWidth
            )
            stops.append(
                Gradient.Stop(
                    color: color(for: currentStyle).opacity(opacity),
                    location: transitionStart
                )
            )
            stops.append(
                Gradient.Stop(
                    color: color(for: nextStyle).opacity(opacity),
                    location: max(transitionStart, transitionEnd)
                )
            )
            currentStyle = nextStyle
        }

        guard stops.count > 1 else {
            return .color(color(for: currentStyle).opacity(opacity))
        }

        stops.append(
            Gradient.Stop(
                color: color(for: currentStyle).opacity(opacity),
                location: 1
            )
        )
        return .linearGradient(
            Gradient(stops: stops),
            startPoint: CGPoint(x: metrics.sideInset, y: 0),
            endPoint: CGPoint(
                x: metrics.size.width - metrics.sideInset,
                y: 0
            )
        )
    }

    private func color(for point: Point) -> Color {
        color(for: lineStyle(point))
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

private let performanceChartSideInset: CGFloat = 19
private let performanceChartMaximumTransitionWidth: CGFloat = 12

private struct PerformanceChartMetrics<Point: Hashable> {
    let points: [Point]
    let value: (Point) -> Double
    let xScale: PerformanceChartXScale<Point>
    let size: CGSize
    let minValue: Double
    let maxValue: Double
    let topInset: CGFloat = 12
    let bottomInset: CGFloat = 28
    let sideInset: CGFloat = performanceChartSideInset

    var plotWidth: CGFloat {
        max(0, size.width - sideInset * 2)
    }

    var isDrawable: Bool {
        points.count >= 2
            && plotWidth > 0
            && size.height > topInset + bottomInset
            && xScale.isValid
    }

    func index(of point: Point) -> Int? {
        points.firstIndex(of: point)
    }

    func location(for index: Int) -> CGPoint? {
        guard points.indices.contains(index) else { return nil }
        guard let x = x(for: index) else { return nil }
        guard let y = y(for: value(points[index])) else { return nil }
        return CGPoint(x: x, y: y)
    }

    func nearestPoint(to xPosition: CGFloat) -> Point? {
        guard isDrawable else { return points.last }

        let clampedX = min(max(xPosition, sideInset), size.width - sideInset)
        let nearestIndex = points.indices.min { lhs, rhs in
            guard let lhsX = x(for: lhs), let rhsX = x(for: rhs) else { return false }
            return abs(lhsX - clampedX) < abs(rhsX - clampedX)
        }
        return nearestIndex.map { points[$0] }
    }

    func horizontalProgress(for index: Int) -> CGFloat? {
        guard let x = x(for: index) else { return nil }
        guard plotWidth > 0 else { return nil }
        return min(max((x - sideInset) / plotWidth, 0), 1)
    }

    func y(for value: Double) -> CGFloat? {
        guard maxValue > minValue else { return nil }
        let height = size.height - topInset - bottomInset
        let progress = (value - minValue) / (maxValue - minValue)
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

    private func x(for index: Int) -> CGFloat? {
        guard points.indices.contains(index) else { return nil }

        switch xScale {
        case .unavailable:
            return nil

        case .indexed:
            guard points.count > 1 else { return size.width / 2 }
            return sideInset + CGFloat(index) / CGFloat(points.count - 1) * plotWidth

        case .time(let domain, let timestamp):
            let duration = domain.duration
            guard duration > 0 else { return nil }
            guard let elapsed = domain.elapsedTime(
                for: timestamp(points[index])
            ) else {
                return nil
            }
            let progress = min(max(elapsed / duration, 0), 1)
            return sideInset + CGFloat(progress) * plotWidth
        }
    }
}
