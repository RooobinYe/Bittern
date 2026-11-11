//
//  AllocationCard.swift
//  Bittern
//
//  The Portfolio page's allocation: the total, then each slice a band of
//  color, stacked by size, under a glass lens. The lens can be dragged
//  anywhere on the page and springs back to the card's middle.
//

import SwiftUI

enum AllocationCardMetrics {
    /// The card's width over its height.
    static let aspectRatio: CGFloat = 1.1
    static let cornerRadius: CGFloat = 34
    /// The lens's radius as a fraction of the card's shorter side.
    static let lensRadiusFraction: CGFloat = 0.36

    static func lensRadius(in cardSize: CGSize) -> CGFloat {
        min(cardSize.width, cardSize.height) * lensRadiusFraction
    }
}

/// The lens while it is off its rest: how far it has been dragged from the
/// card's middle, and where the card is. The page draws the lifted lens
/// above everything, so it can go where the finger takes it.
@Observable
final class AllocationLensMotion {
    /// The lens's offset from the card's middle; zero at rest.
    var translation: CGSize = .zero
    /// True from the moment the lens is picked up until it has sprung back.
    var isLifted = false
    /// The card on screen. Global, not a space named on the page: inside a
    /// list, a named space is measured from below the bars. It changes
    /// with every scroll. Only the lifted lens reads it, so a scroll while
    /// the lens springs back carries the lens along with the card, and a
    /// scroll at rest redraws nothing.
    var cardFrame: CGRect = .zero
}

struct PortfolioAllocationSection: View {
    let snapshot: PortfolioSnapshot
    let performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let fillsAvailableSpace: Bool
    /// The legend to the card's side rather than under it, for a space
    /// too short for both, such as above a fold.
    var legendBesideCard = false
    /// Nil shows the return without a control, as in the exported image.
    let selectPerformanceMode: (@MainActor (PerformanceMode) -> Void)?
    /// Nil keeps the lens still, as in the exported image.
    let lensMotion: AllocationLensMotion?

    var body: some View {
        let slices = AllocationSlice.slices(of: snapshot)

        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                PerformanceSummary(
                    total: totalMarketValueText,
                    change: performanceText,
                    changeColor: BitternTheme.performanceColor(performanceAmount),
                    mode: performanceMode,
                    select: selectPerformanceMode
                )

                if legendBesideCard {
                    HStack(alignment: .center, spacing: 24) {
                        AllocationLensCard(slices: slices, motion: lensMotion)
                            .aspectRatio(AllocationCardMetrics.aspectRatio, contentMode: .fit)
                            .frame(maxWidth: DashboardLayoutMetrics.maximumChartSide)

                        AllocationLegend(slices: slices)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    AllocationLensCard(slices: slices, motion: lensMotion)
                        .aspectRatio(AllocationCardMetrics.aspectRatio, contentMode: .fit)
                }
            }

            if !legendBesideCard {
                AllocationLegend(slices: slices)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: legendBesideCard ? nil : DashboardLayoutMetrics.maximumChartSide)
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsAvailableSpace ? .infinity : nil,
            alignment: legendBesideCard ? .top : .center
        )
    }

    private var performanceAmount: Double? {
        snapshot.performanceAmount(for: performanceMode)
    }

    private var performancePercent: Double? {
        snapshot.performancePercent(for: performanceMode)
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


/// A slice of the allocation as drawn: its band and its legend chip.
private struct AllocationSlice: Identifiable {
    let id: String
    let symbol: String
    let isOther: Bool
    let logoURL: URL?
    let share: Double
    /// The band's color, from its rank. Also behind the symbol when there
    /// is no logo, as in the holding rows.
    let bandColor: Color

    /// No total means no honest shares, so the card stays empty.
    static func slices(of snapshot: PortfolioSnapshot) -> [AllocationSlice] {
        guard snapshot.totalMarketValue != nil else { return [] }
        let slices = PortfolioAllocation.slices(of: snapshot.holdings)
        let bandColors = BitternTheme.allocationBandColors(count: slices.count)

        return zip(slices, bandColors).map { slice, bandColor in
            switch slice.kind {
            case .holding(let holding):
                AllocationSlice(
                    id: slice.id,
                    symbol: holding.symbol,
                    isOther: false,
                    logoURL: holding.logoURL,
                    share: slice.share,
                    bandColor: bandColor
                )
            case .other:
                AllocationSlice(
                    id: slice.id,
                    symbol: "Other",
                    isOther: true,
                    logoURL: nil,
                    share: slice.share,
                    bandColor: bandColor
                )
            }
        }
    }
}

// MARK: - Card

/// The bands, largest at the top, under a Liquid Glass lens. The lens rests
/// in the middle; dragged, it lifts onto the page, which draws it
/// (`LiftedAllocationLens`), and on release it springs back.
private struct AllocationLensCard: View {
    let slices: [AllocationSlice]
    let motion: AllocationLensMotion?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let radius = AllocationCardMetrics.lensRadius(in: size)
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)

            ZStack {
                bands(height: size.height)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipShape(.rect(cornerRadius: AllocationCardMetrics.cornerRadius, style: .continuous))
                    .allocationAccessibility(slices)

                if motion?.isLifted != true {
                    AllocationLensGlass(radius: radius)
                        .position(middle)
                }

                if let motion {
                    // Stays at rest while the lens moves: the drag is measured
                    // here, and a fixed view gives a steady measure.
                    Color.clear
                        .frame(width: radius * 2, height: radius * 2)
                        .contentShape(.circle)
                        .position(middle)
                        .gesture(lensDrag(motion))
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            motion?.cardFrame = frame
        }
    }

    @ViewBuilder
    private func bands(height: CGFloat) -> some View {
        if slices.isEmpty {
            Color(uiColor: .secondarySystemFill)
        } else {
            VStack(spacing: 0) {
                ForEach(slices) { slice in
                    Rectangle()
                        .fill(slice.bandColor)
                        .frame(height: height * slice.share)
                }
            }
        }
    }

    private func lensDrag(_ motion: AllocationLensMotion) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                // Follow the finger at once, even mid-spring.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    motion.isLifted = true
                    motion.translation = value.translation
                }
            }
            .onEnded { value in
                // The spring starts at the finger's speed, so a flung lens
                // carries on a little before it swings back.
                let spring = Animation.interpolatingSpring(
                    duration: 0.5,
                    bounce: 0.3,
                    initialVelocity: Self.returnVelocity(value.velocity, from: motion.translation)
                )
                // Put the lens back on the card only once the spring has
                // settled. A bouncy spring is logically complete while it is
                // still swinging past the middle, and the card's lens, drawn
                // at the exact middle, would take over with a jump.
                withAnimation(spring, completionCriteria: .removed) {
                    motion.translation = .zero
                } completion: {
                    // Another drag may have picked it up meanwhile.
                    if motion.translation == .zero {
                        motion.isLifted = false
                    }
                }
            }
    }

    /// The finger's velocity as the spring takes it: the share of the way
    /// back to the middle covered per second, positive toward the middle.
    /// The spring moves the lens along the line to the middle, so only the
    /// velocity along that line carries over.
    static func returnVelocity(_ velocity: CGSize, from translation: CGSize) -> Double {
        let distanceSquared = translation.width * translation.width + translation.height * translation.height
        guard distanceSquared > 0 else { return 0 }
        let outward = velocity.width * translation.width + velocity.height * translation.height
        return -outward / distanceSquared
    }
}

/// The lens: its shadow, Liquid Glass and rim. The Liquid Glass bends
/// whatever is under it, the bands or the page, so the lens looks the same
/// at rest and lifted, on the card and off it.
struct AllocationLensGlass: View {
    let radius: CGFloat
    /// The shadow's strength. A placeholder card under the lens is pale, so
    /// a lighter shadow keeps the lens from looking heavier than the card.
    var shadowOpacity: Double = 0.28

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(shadowOpacity), lineWidth: 10)
                .frame(width: radius * 2 + 8, height: radius * 2 + 8)
                .blur(radius: 8)
                .offset(y: 3)

            Color.clear
                .frame(width: radius * 2, height: radius * 2)
                .glassEffect(.clear, in: .circle)

            AllocationLensRim()
                .frame(width: radius * 2, height: radius * 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The lens's rim: a fine dark edge, with light catching its top.
private struct AllocationLensRim: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.black.opacity(0.22), lineWidth: 1)

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.8), .white.opacity(0.05), .white.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .padding(1)
        }
    }
}

/// The lens while it is lifted, drawn by the page above everything, where
/// the card's middle plus the drag puts it.
struct LiftedAllocationLens: View {
    let motion: AllocationLensMotion

    var body: some View {
        if motion.isLifted {
            GeometryReader { proxy in
                let page = proxy.frame(in: .global)
                let card = motion.cardFrame
                // The drag and the card apart: the spring animates the
                // offset, while a scroll moves the position at once, without
                // cutting the spring short.
                AllocationLensGlass(radius: AllocationCardMetrics.lensRadius(in: card.size))
                    .offset(motion.translation)
                    .position(x: card.midX - page.minX, y: card.midY - page.minY)
            }
        }
    }
}

/// The total, and under it the return, which a tap switches between today
/// and all time. The same choice is in the holdings menu. The mode's name
/// stays as it is in every state: "Today" names the return, not the date.
private struct PerformanceSummary: View {
    let total: String
    let change: String
    let changeColor: Color
    let mode: PerformanceMode
    let select: (@MainActor (PerformanceMode) -> Void)?

    @Environment(\.priceStatus) private var priceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(total)
                .font(.keyFigure(.largeTitle, weight: .bold))
                .foregroundStyle(priceStatus.keyFigureColor(BitternTheme.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityLabel(priceStatus.accessibilityLabel(for: total))

            if let select {
                Button {
                    withAnimation(.snappy) { select(mode.next) }
                } label: {
                    returnLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Return")
                .accessibilityValue("\(mode.title), \(priceStatus.accessibilityLabel(for: change))")
                .accessibilityHint("Switches between today and all time")
                .sensoryFeedback(.selection, trigger: mode)
            } else {
                returnLabel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var returnLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(change)
                .font(.keyFigure(.body))
                .foregroundStyle(priceStatus.figureColor(changeColor))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Animates only the switch between today and all time; new
                // prices replace the figure without a transition.
                .contentTransition(.numericText())

            Text(mode.title)
                .font(.subheadline)
                .foregroundStyle(BitternTheme.secondaryInk)
                .lineLimit(1)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}


// MARK: - Legend

/// One chip per band: its logo, symbol, share and band color.
private struct AllocationLegend: View {
    let slices: [AllocationSlice]

    var body: some View {
        GlassEffectContainer {
            CenteredFlowLayout(spacing: 8, lineSpacing: 10) {
                ForEach(slices) { slice in
                    LegendChip(slice: slice)
                }
            }
        }
        // Chips past this size would wrap into more rows than the legend is
        // worth. VoiceOver reads the same shares from the card.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityHidden(true)
    }
}

private struct LegendChip: View {
    let slice: AllocationSlice

    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 22
    @Environment(\.self) private var environment

    var body: some View {
        HStack(spacing: 6) {
            icon

            Text(slice.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BitternTheme.ink)

            Text(PortfolioFormat.percent(slice.share, fractionDigits: 0))
                .font(.keyFigure(.caption))
                .foregroundStyle(BitternTheme.secondaryInk)

            Circle()
                .fill(slice.bandColor)
                .frame(width: 8, height: 8)
        }
        .lineLimit(1)
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(minHeight: iconSize + 8)
        .glassEffect(.clear, in: .capsule)
    }

    @ViewBuilder
    private var icon: some View {
        if slice.isOther {
            Image(systemName: "ellipsis")
                .font(.system(size: iconSize * 0.42, weight: .bold))
                .foregroundStyle(slice.bandColor.contrastingForeground(in: environment))
                .frame(width: iconSize, height: iconSize)
                .background(slice.bandColor, in: .circle)
        } else {
            HoldingSymbolIcon(
                symbol: slice.symbol,
                logoURL: slice.logoURL,
                color: slice.bandColor,
                size: iconSize,
                fallbackLabel: String(slice.symbol.prefix(4))
            )
        }
    }
}

/// Rows of views that wrap, each row centered.
struct CenteredFlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = Row()
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

// MARK: - Accessibility

private extension View {
    /// VoiceOver reads the card as one chart, with the allocation as its
    /// value and an audio graph through the descriptor.
    func allocationAccessibility(_ slices: [AllocationSlice]) -> some View {
        accessibilityElement()
            .accessibilityLabel("Allocation")
            .accessibilityValue(
                slices
                    .map { "\($0.symbol) \(PortfolioFormat.percent($0.share, fractionDigits: 0))" }
                    .joined(separator: ", ")
            )
            .accessibilityChartDescriptor(
                AllocationChartDescriptor(slices: slices.map { ($0.symbol, $0.share) })
            )
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

extension PerformanceMode {
    var systemImage: String {
        switch self {
        case .today:
            "sun.max"
        case .allTime:
            "clock.arrow.circlepath"
        }
    }

    /// The other mode, for a control that switches with one tap.
    var next: PerformanceMode {
        let modes = Self.allCases
        let index = modes.firstIndex(of: self) ?? modes.startIndex
        return modes[(index + 1) % modes.count]
    }
}
