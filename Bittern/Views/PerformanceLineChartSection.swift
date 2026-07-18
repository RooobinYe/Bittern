//
//  PerformanceLineChartSection.swift
//  Bittern
//

import SwiftUI

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
            return domain.start < domain.end
        }
    }
}

struct PerformanceLineChartSection<Point: Hashable, RangeOption: Identifiable & Equatable>: View {
    let points: [Point]
    let value: (Point) -> Double
    let xScale: PerformanceChartXScale<Point>
    let baseValue: Double?
    let baselineLabel: String?
    let ranges: [RangeOption]
    let rangeTitle: (RangeOption) -> String
    @Binding var selectedRange: RangeOption
    @Binding var selectedPoint: Point?
    let isLoading: Bool

    private var lineColor: Color {
        guard let baseValue, let lastPoint = points.last else {
            return BitternTheme.secondaryInk
        }

        return BitternTheme.performanceColor(value(lastPoint) - baseValue)
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
                }

                let markerIndex = activeIndex ?? points.indices.last
                if let markerIndex,
                   let marker = metrics.location(for: markerIndex) {
                    Circle()
                        .fill(lineColor)
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

}

private let performanceChartSideInset: CGFloat = 19

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

    var isDrawable: Bool {
        points.count >= 2
            && size.width > sideInset * 2
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

        let plotWidth = size.width - sideInset * 2
        switch xScale {
        case .unavailable:
            return nil

        case .indexed:
            guard points.count > 1 else { return size.width / 2 }
            return sideInset + CGFloat(index) / CGFloat(points.count - 1) * plotWidth

        case .time(let domain, let timestamp):
            let duration = domain.end.timeIntervalSince(domain.start)
            guard duration > 0 else { return nil }
            let elapsed = timestamp(points[index]).timeIntervalSince(domain.start)
            let progress = min(max(elapsed / duration, 0), 1)
            return sideInset + CGFloat(progress) * plotWidth
        }
    }
}
