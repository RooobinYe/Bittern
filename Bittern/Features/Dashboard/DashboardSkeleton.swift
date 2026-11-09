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
    let layoutMode: DashboardLayoutMode
    let controls: DashboardControls

    var body: some View {
        switch layoutMode {
        case .stacked:
            List {
                Section {
                    SkeletonAllocation(performanceMode: performanceMode)
                        .padding(.vertical, 8)
                        .listRowInsets(.horizontal, 0)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                holdingsSection
            }
            .listStyle(.plain)
            .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
            .frame(maxWidth: .infinity)
            .softNavigationBarEdge()

        case .split:
            HStack(alignment: .top, spacing: DashboardLayoutMetrics.columnSpacing) {
                SkeletonAllocation(performanceMode: performanceMode)
                    .frame(
                        minWidth: DashboardLayoutMetrics.minimumChartColumnWidth,
                        idealWidth: DashboardLayoutMetrics.idealChartColumnWidth,
                        maxWidth: DashboardLayoutMetrics.maximumChartSide,
                        maxHeight: .infinity,
                        alignment: .top
                    )

                List {
                    holdingsSection
                }
                .listStyle(.plain)
                .frame(minWidth: DashboardLayoutMetrics.minimumHoldingsColumnWidth)
                .softNavigationBarEdge()
            }
            .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
            .padding(.leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var holdingsSection: some View {
        Section {
            HoldingsHeader(
                performanceMode: performanceMode,
                sortOption: sortOption,
                controls: controls
            )
            .listRowSeparator(.hidden)
            .listRowInsets(.horizontal, 16)
            .listRowInsets(.bottom, 0)

            ForEach(0..<skeleton.rowCount, id: \.self) { index in
                SkeletonHoldingRow(index: index)
                    .opacity(fade(at: index))
                    .listRowInsets(.horizontal, 16)
                    .listRowSeparator(
                        index == skeleton.rowCount - 1 ? .hidden : .automatic,
                        edges: .bottom
                    )
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

    /// The legend's chips, as wide as typical ones.
    private static let chipWidths: [CGFloat] = [128, 134, 114, 110, 122, 96]

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
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

                    HStack(alignment: .center, spacing: 8) {
                        Text(verbatim: "+0")
                            .font(.keyFigure(.body))
                            .hidden()
                            .frame(width: 132, alignment: .leading)
                            .overlay {
                                SkeletonBlock(cornerRadius: 6)
                                    .padding(.vertical, 2)
                            }

                        Text(performanceMode.title)
                            .font(.subheadline)
                            .foregroundStyle(BitternTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    .frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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

            CenteredFlowLayout(spacing: 8, lineSpacing: 10) {
                ForEach(Self.chipWidths.indices, id: \.self) { index in
                    SkeletonBlock(cornerRadius: 15)
                        .frame(width: Self.chipWidths[index], height: 30)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: DashboardLayoutMetrics.maximumChartSide)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading portfolio")
    }
}

/// A holding row as blocks: the logo, the symbol and quantity, the value,
/// the share and the change.
private struct SkeletonHoldingRow: View {
    let index: Int

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40

    /// Widths that vary row to row, so the list reads as text, not stripes.
    private static let widths: [(symbol: CGFloat, quantity: CGFloat, value: CGFloat, change: CGFloat)] = [
        (56, 92, 70, 128), (60, 86, 64, 132), (48, 96, 52, 120), (42, 104, 48, 122),
        (54, 72, 48, 124), (56, 52, 48, 120), (52, 50, 48, 124), (36, 78, 48, 120),
        (50, 56, 48, 128)
    ]

    var body: some View {
        let widths = Self.widths[index % Self.widths.count]
        HStack(spacing: 12) {
            SkeletonBlock(cornerRadius: iconSize / 2)
                .frame(width: iconSize, height: iconSize)

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    line(width: widths.symbol, font: .headline)
                    line(width: widths.quantity, font: .subheadline, faint: true)
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
