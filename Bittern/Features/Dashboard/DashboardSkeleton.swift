//
//  DashboardSkeleton.swift
//  Bittern
//
//  What launch shows while the data is on its way: the dashboard's own
//  shape, with blocks where its figures will be. Text that doesn't depend
//  on the data, such as "Holdings", the return's name and the sort menu,
//  is real.
//

import SwiftUI

struct DashboardSkeleton: View {
    let skeleton: LaunchSkeleton
    let performanceMode: PerformanceMode
    let sortOption: HoldingSortOption
    var isPrivacyEnabled = false
    let layoutMode: PaneArrangement
    let controls: DashboardControls

    /// The same places as the loaded dashboard, so nothing moves when the
    /// data comes.
    var body: some View {
        switch layoutMode {
        case .single:
            ScrollView {
                VStack(spacing: DashboardLayoutMetrics.sectionSpacing) {
                    SkeletonAllocation(
                        performanceMode: performanceMode,
                        legendChips: skeleton.legendChips
                    )
                    holdingsSection
                }
                .padding(.bottom, 14)
                .frame(maxWidth: DashboardLayoutMetrics.maximumChartSide)
                .frame(maxWidth: .infinity)
            }
            .softNavigationBarEdge()

        case .columns, .rows:
            PaneSplit(arrangement: layoutMode) {
                SkeletonAllocation(
                    performanceMode: performanceMode,
                    legendChips: skeleton.legendChips,
                    fillsAvailableSpace: true,
                    legendBesideCard: layoutMode.isRows
                )
            } second: {
                ScrollView {
                    holdingsSection
                        .padding(.top, 8)
                        .padding(.bottom, 14)
                }
                .softNavigationBarEdge()
            }
            .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var holdingsSection: some View {
        VStack(spacing: 0) {
            HoldingsHeader(
                performanceMode: performanceMode,
                sortOption: sortOption,
                controls: controls
            )
            .padding(.horizontal, DashboardLayoutMetrics.horizontalInset)

            ForEach(0..<skeleton.rowCount, id: \.self) { index in
                SkeletonHoldingRow(index: index, isPrivacyEnabled: isPrivacyEnabled)
                    .padding(.horizontal, DashboardLayoutMetrics.horizontalInset)
                    .padding(.vertical, DashboardLayoutMetrics.holdingRowVerticalPadding)
                    .opacity(fade(at: index))

                if index < skeleton.rowCount - 1 {
                    Divider()
                        .padding(.horizontal, DashboardLayoutMetrics.horizontalInset)
                        .opacity(fade(at: index))
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// Without a cache the row count is a guess, so the list fades out
    /// rather than ending on a row the data may not have.
    private func fade(at index: Int) -> Double {
        guard !skeleton.isRowCountKnown else { return 1 }
        let fromEnd = skeleton.rowCount - 1 - index
        return switch fromEnd {
        case 0: 0.2
        case 1: 0.45
        case 2: 0.75
        default: 1
        }
    }
}

/// The total, the return with its mode's name, the card under its lens and
/// the legend, as blocks.
private struct SkeletonAllocation: View {
    let performanceMode: PerformanceMode
    let legendChips: [LaunchSkeleton.LegendChip]
    var fillsAvailableSpace = false
    var legendBesideCard = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    // Hidden figures hold the real lines' heights, so
                    // nothing moves when the data comes.
                    Text(verbatim: "US$0")
                        .font(.keyFigure(.largeTitle, weight: .bold))
                        .hidden()
                        .frame(width: 196, alignment: .leading)
                        .overlay {
                            SkeletonBlock(cornerRadius: 8)
                                .padding(.vertical, 5)
                        }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "+0")
                            .font(.keyFigure(.body))
                            .hidden()
                            .frame(width: 148, alignment: .leading)
                            .overlay {
                                SkeletonBlock(cornerRadius: 6)
                                    .padding(.vertical, 2)
                            }

                        Text(performanceMode.title)
                            .font(.subheadline)
                            .foregroundStyle(BitternTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if legendBesideCard {
                    HStack(alignment: .center, spacing: 24) {
                        card
                            .frame(maxWidth: DashboardLayoutMetrics.maximumChartSide)
                        legend
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    card
                }
            }

            if !legendBesideCard {
                legend
            }
        }
        .padding(.horizontal, DashboardLayoutMetrics.horizontalInset)
        .padding(.top, 8)
        .padding(.bottom, fillsAvailableSpace ? 8 : 0)
        .frame(maxWidth: legendBesideCard ? nil : DashboardLayoutMetrics.maximumChartSide)
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsAvailableSpace ? .infinity : nil,
            alignment: legendBesideCard ? .top : .center
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading portfolio")
    }

    private var card: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                SkeletonBlock(cornerRadius: AllocationCardMetrics.cornerRadius)
                AllocationLensGlass(radius: AllocationCardMetrics.lensRadius(in: size), shadowOpacity: 0.1)
                    .position(x: size.width / 2, y: size.height / 2)
            }
        }
        .aspectRatio(AllocationCardMetrics.aspectRatio, contentMode: .fit)
    }

    private var legend: some View {
        CenteredFlowLayout(
            spacing: AllocationLegendMetrics.spacing,
            lineSpacing: AllocationLegendMetrics.lineSpacing
        ) {
            ForEach(legendChips.indices, id: \.self) { index in
                let chip = legendChips[index]
                SkeletonLegendChip(symbol: chip.symbol, percent: chip.percent)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// A legend chip block sized by hidden text with the same metrics as `LegendChip`,
/// so rows wrap identically across Dynamic Type sizes.
private struct SkeletonLegendChip: View {
    let symbol: String
    let percent: String

    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = AllocationLegendMetrics.iconSize

    var body: some View {
        let height = iconSize + AllocationLegendMetrics.chipVerticalPaddingTotal

        HStack(spacing: AllocationLegendMetrics.chipSpacing) {
            Color.clear
                .frame(width: iconSize, height: iconSize)

            Text(verbatim: symbol)
                .font(.caption.weight(.semibold))

            Text(verbatim: percent)
                .font(.keyFigure(.caption))

            Color.clear
                .frame(width: AllocationLegendMetrics.dotSize, height: AllocationLegendMetrics.dotSize)
        }
        .lineLimit(1)
        .padding(.leading, AllocationLegendMetrics.chipLeadingPadding)
        .padding(.trailing, AllocationLegendMetrics.chipTrailingPadding)
        .frame(minHeight: height)
        .hidden()
        .overlay {
            SkeletonBlock(cornerRadius: height / 2)
        }
    }
}

/// A holding row as blocks: the logo, the symbol and quantity, the value,
/// the share and the change.
private struct SkeletonHoldingRow: View {
    let index: Int
    let isPrivacyEnabled: Bool

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Widths that vary row to row, so the list reads as text, not stripes.
    private static let widths: [(symbol: CGFloat, quantity: CGFloat, value: CGFloat, change: CGFloat)] = [
        (56, 92, 74, 136), (60, 86, 68, 140), (48, 96, 56, 128), (42, 104, 52, 130),
        (54, 72, 52, 132), (56, 52, 52, 128), (52, 50, 52, 132), (36, 78, 52, 128),
        (50, 56, 52, 136)
    ]

    var body: some View {
        let widths = Self.widths[index % Self.widths.count]

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    line(width: widths.symbol, font: .headline)
                    line(width: widths.value, font: .headline)
                    line(width: widths.change, font: .subheadline, faint: true)
                    line(width: isPrivacyEnabled ? 56 : 140, font: .subheadline, faint: true)
                }
            } else {
                HStack(spacing: 12) {
                    SkeletonBlock(cornerRadius: iconSize / 2)
                        .frame(width: iconSize, height: iconSize)

                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                line(width: widths.symbol, font: .headline)
                                if !isPrivacyEnabled {
                                    line(width: widths.quantity, font: .subheadline, faint: true)
                                }
                            }
                            Spacer(minLength: 8)
                            line(width: widths.value, font: .headline)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            line(width: 46, font: .subheadline, faint: true)
                            Spacer(minLength: 8)
                            line(width: widths.change, font: .subheadline, faint: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A block the height of a line of `font`, a little inset so lines
    /// stay apart.
    private func line(width: CGFloat, font: Font, faint: Bool = false) -> some View {
        Text(verbatim: "Hg")
            .font(font)
            .hidden()
            .frame(width: width)
            .overlay {
                SkeletonBlock(cornerRadius: 5)
                    .padding(.vertical, 3)
                    .opacity(faint ? 0.7 : 1)
            }
    }
}

/// A placeholder block with a light passing over it, still under Reduce
/// Motion.
struct SkeletonBlock: View {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(BitternTheme.skeleton)
            .overlay {
                if !reduceMotion {
                    SkeletonShimmer()
                        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .accessibilityHidden(true)
    }
}

/// A band of light that crosses its block every 1.4 seconds. Every block
/// reads the same clock, so they shimmer together.
private struct SkeletonShimmer: View {
    private static let period: TimeInterval = 1.4

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.period) / Self.period
            GeometryReader { proxy in
                let width = proxy.size.width
                LinearGradient(
                    colors: [.white.opacity(0), BitternTheme.skeletonHighlight, .white.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width)
                .offset(x: (phase * 2 - 1) * width)
            }
        }
        .allowsHitTesting(false)
    }
}
