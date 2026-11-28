//
//  DashboardContent.swift
//  Bittern
//

import SwiftUI

enum DashboardLayoutMetrics {
    /// These are content readability bounds, not device breakpoints. The
    /// allocation and the holdings go side by side whenever both columns
    /// keep their useful minimum width, and meet at the fold of a partially
    /// folded display.
    static let minimumChartColumnWidth: CGFloat = 320
    static let idealChartColumnWidth: CGFloat = 440
    static let minimumHoldingsColumnWidth: CGFloat = 360
    static let columnSpacing: CGFloat = 28
    /// In a shorter column, the card at the column's narrowest (262 pt
    /// tall) leaves under 200 pt for the total and the legend, so the page
    /// stacks and scrolls instead.
    static let minimumSplitHeight: CGFloat = 460
    /// Above and below a fold: room for the total and a card worth
    /// reading on top, and for a few holdings below.
    static let minimumFoldedRowHeight: CGFloat = 240
    /// The allocation's widest, its insets included. One column is never
    /// wider either, so the holdings start where the allocation does.
    static let maximumChartSide: CGFloat = 500
    static let maximumContentWidth: CGFloat = 1_280
    static let maximumExportWidth: CGFloat = maximumContentWidth + 48
    static let horizontalInset: CGFloat = 16
    /// Gap between the allocation section and the holdings section.
    static let sectionSpacing: CGFloat = 24
    /// Top and bottom padding on each holding row; also sets the header-to-first-row
    /// distance so the title sits tightly on its rows.
    static let holdingRowVerticalPadding: CGFloat = 12

    static let panes = PaneRequirements(
        minimumLeadingWidth: minimumChartColumnWidth,
        minimumTrailingWidth: minimumHoldingsColumnWidth,
        preferredWidth: .leading(idealChartColumnWidth),
        columnSpacing: columnSpacing,
        minimumColumnsHeight: minimumSplitHeight,
        minimumRowHeight: minimumFoldedRowHeight
    )

    static func layoutMode(in size: CGSize, fold: FoldDivision? = nil) -> PaneArrangement {
        panes.arrangement(in: size, fold: fold)
    }
}

/// What the live dashboard lets people change. The exported image has no
/// controls, so its containers show the same labels without wrapping them in
/// buttons and menus.
struct DashboardControls {
    // Main-actor function types are Sendable, which `Binding(get:set:)`
    // asks of its setter.
    let selectPerformanceMode: @MainActor (PerformanceMode) -> Void
    let selectSortOption: @MainActor (HoldingSortOption) -> Void
    /// What the user has to fix, shown above the data until it is fixed.
    var attention: PortfolioAttention? = nil
    var openSettings: () -> Void = {}
}

struct DashboardContent: View {
    let viewModel: DashboardViewModel
    @Binding var isPrivacyEnabled: Bool
    let connectBrokerage: () -> Void

    var body: some View {
        switch viewModel.loadState {
        case .notLoaded:
            ContentUnavailableView {
                Label("No Portfolio Connected", systemImage: "building.columns")
            } description: {
                Text("Connect a brokerage to see your holdings.")
            } actions: {
                Button("Connect Brokerage", action: connectBrokerage)
                    .buttonStyle(.borderedProminent)
            }
        case .loading(nil):
            // The first moments of launch: a load that answers this fast
            // shows its data without a skeleton in between.
            Color.clear
        case .loading(let skeleton?):
            PaneGeometryReader { size, fold in
                DashboardSkeleton(
                    skeleton: skeleton,
                    performanceMode: viewModel.performanceMode,
                    sortOption: viewModel.sortOption,
                    isPrivacyEnabled: isPrivacyEnabled,
                    layoutMode: DashboardLayoutMetrics.layoutMode(in: size, fold: fold),
                    controls: controls
                )
            }
        case .failed(let failure):
            if let attention = failure.attention {
                ContentUnavailableView {
                    Label("Portfolio Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(attention.message)
                } actions: {
                    Button("Settings", action: connectBrokerage)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("Portfolio Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure.message)
                } actions: {
                    Button("Try Again") {
                        Task { await viewModel.retryLaunch() }
                    }
                }
            }
        case .loaded(let snapshot):
            PaneGeometryReader { size, fold in
                DashboardVisualContent(
                    portfolio: viewModel.displaySnapshot ?? snapshot,
                    scopeTitle: viewModel.selectedProviderName,
                    sortedHoldings: viewModel.sortedHoldings,
                    performanceMode: viewModel.performanceMode,
                    sortOption: viewModel.sortOption,
                    minimumMarketValue: viewModel.minPriceThreshold,
                    hiddenHoldingCount: viewModel.hiddenHoldingCount,
                    isPrivacyEnabled: isPrivacyEnabled,
                    layoutMode: DashboardLayoutMetrics.layoutMode(in: size, fold: fold),
                    controls: controls
                )
            }
            .environment(\.priceStatus, viewModel.priceStatus)
        }
    }

    private var controls: DashboardControls {
        DashboardControls(
            selectPerformanceMode: { viewModel.performanceMode = $0 },
            selectSortOption: { viewModel.sortOption = $0 },
            attention: viewModel.attention,
            openSettings: connectBrokerage
        )
    }
}

/// A problem only the user can fix, over the data it concerns: what, why,
/// and the way to Settings. It stays until the problem is gone.
struct AttentionBanner: View {
    let attention: PortfolioAttention
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(BitternTheme.attention)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(attention.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BitternTheme.ink)
                Text(attention.message)
                    .font(.footnote)
                    .foregroundStyle(BitternTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button("Settings", action: openSettings)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .background(BitternTheme.attentionBackground, in: .rect(cornerRadius: 18, style: .continuous))
    }
}

/// The single visual source for both the live dashboard and its exported image.
/// Both render the exact same stacks and spacing; the live dashboard wraps the
/// layout in a `ScrollView` and makes holding rows navigable.
struct DashboardVisualContent: View {
    let portfolio: PortfolioSnapshot
    /// Shown above the total when filtered to a single brokerage, and in the
    /// exported image where there is no tab bar to name the view.
    var scopeTitle: String? = nil
    let sortedHoldings: [PortfolioHolding]
    let performanceMode: PerformanceMode
    let sortOption: HoldingSortOption
    let minimumMarketValue: Double
    let hiddenHoldingCount: Int
    let isPrivacyEnabled: Bool
    let layoutMode: PaneArrangement
    /// Nil when rendering the exported image.
    let controls: DashboardControls?

    @State private var marketTime = Date()
    @Environment(\.allocationLensMotion) private var sharedLensMotion
    @State private var fallbackLensMotion = AllocationLensMotion()

    private var lensMotion: AllocationLensMotion {
        sharedLensMotion ?? fallbackLensMotion
    }

    /// The bands' colors, so a holding without a logo matches its band.
    private var holdingColorLookup: [String: Color] {
        BitternTheme.holdingAllocationColors(for: portfolio.holdings)
    }

    /// When the next pre-market, post-market or overnight session shown in
    /// a row ends, so the row can stop showing it.
    private var nextExtendedHoursBoundary: Date? {
        sortedHoldings.flatMap { holding in
            [
                holding.activePreMarketChange(at: marketTime)?.sessionEnd,
                holding.activePostMarketChange(at: marketTime)?.sessionEnd,
                holding.activeOvernightChange(at: marketTime)?.sessionEnd
            ].compactMap { $0 }
        }.min()
    }

    var body: some View {
        content
            // Fallback when DashboardVisualContent is hosted outside ContentView.
            .overlay {
                if sharedLensMotion == nil {
                    LiftedAllocationLens(motion: fallbackLensMotion)
                }
            }
            .onChange(of: portfolio.lastUpdated) { _, _ in
                marketTime = Date()
            }
            .task(id: nextExtendedHoursBoundary) {
                guard let boundary = nextExtendedHoursBoundary else { return }
                do {
                    try await Task.sleep(for: .seconds(max(boundary.timeIntervalSinceNow, 0)))
                } catch {
                    return
                }
                marketTime = Date()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch (layoutMode, controls) {
        case (.single, let controls?):
            ScrollView {
                singleColumnContent(controls: controls)
            }
            .softNavigationBarEdge()

        // Side by side, or above and below a fold. The banner heads the
        // holdings, so it never crosses the fold.
        case (_, let controls?):
            PaneSplit(arrangement: layoutMode) {
                allocation(fillsAvailableSpace: true)
            } second: {
                ScrollView {
                    VStack(spacing: DashboardLayoutMetrics.sectionSpacing) {
                        if let attention = controls.attention {
                            attentionBanner(attention, controls: controls)
                        }

                        holdingsSection(controls: controls)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }
                .softNavigationBarEdge()
            }
            .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
            .frame(maxWidth: .infinity)

        // The export uses the exact same stacks without scroll containers or
        // interactive controls, and is never split at a fold.
        case (.columns, nil):
            PaneSplit(arrangement: layoutMode) {
                allocation(fillsAvailableSpace: false)
            } second: {
                holdingsSection(controls: nil)
                    .padding(.top, 8)
            }
            .padding(.bottom, 14)
            .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
            .frame(maxWidth: .infinity)

        case (_, nil):
            singleColumnContent(controls: nil)
        }
    }

    private func singleColumnContent(controls: DashboardControls?) -> some View {
        VStack(spacing: DashboardLayoutMetrics.sectionSpacing) {
            if let controls, let attention = controls.attention {
                attentionBanner(attention, controls: controls)
            }

            allocation(fillsAvailableSpace: false)
            holdingsSection(controls: controls)
        }
        .padding(.bottom, 14)
        .frame(maxWidth: DashboardLayoutMetrics.maximumChartSide)
        .frame(maxWidth: .infinity)
    }

    private func attentionBanner(_ attention: PortfolioAttention, controls: DashboardControls) -> some View {
        AttentionBanner(attention: attention, openSettings: controls.openSettings)
            .padding(.horizontal, DashboardLayoutMetrics.horizontalInset)
            .padding(.top, 8)
    }

    private func allocation(fillsAvailableSpace: Bool) -> some View {
        PortfolioAllocationSection(
            snapshot: portfolio,
            scopeTitle: scopeTitle,
            performanceMode: performanceMode,
            isPrivacyEnabled: isPrivacyEnabled,
            fillsAvailableSpace: fillsAvailableSpace,
            // Above a fold the card is short, so the legend goes beside it.
            legendBesideCard: layoutMode.isRows,
            selectPerformanceMode: controls?.selectPerformanceMode,
            lensMotion: controls == nil ? nil : lensMotion
        )
    }

    private func holdingsSection(controls: DashboardControls?) -> some View {
        VStack(spacing: 0) {
            HoldingsHeader(
                performanceMode: performanceMode,
                sortOption: sortOption,
                controls: controls
            )
            .padding(.horizontal, DashboardLayoutMetrics.horizontalInset)

            if sortedHoldings.isEmpty {
                EmptyHoldingsView(hiddenNote: hiddenNote)
                    .padding(.horizontal, DashboardLayoutMetrics.horizontalInset)
                    .padding(.top, 24)
            } else {
                ForEach(sortedHoldings) { holding in
                    holdingRow(for: holding, interactive: controls != nil)

                    if holding.id != sortedHoldings.last?.id {
                        Divider()
                            .padding(.horizontal, DashboardLayoutMetrics.horizontalInset)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func holdingRow(for holding: PortfolioHolding, interactive: Bool) -> some View {
        let content = row(for: holding)
            .padding(.horizontal, DashboardLayoutMetrics.horizontalInset)
            .padding(.vertical, DashboardLayoutMetrics.holdingRowVerticalPadding)

        if interactive {
            NavigationLink(value: HoldingRoute(holdingID: holding.id)) {
                content
            }
            .buttonStyle(HoldingRowButtonStyle())
        } else {
            content
        }
    }

    private func row(for holding: PortfolioHolding) -> HoldingListRow {
        HoldingListRow(
            holding: holding,
            allocation: portfolio.allocation(of: holding),
            performanceMode: performanceMode,
            isPrivacyEnabled: isPrivacyEnabled,
            color: holdingColorLookup[holding.id] ?? BitternTheme.unallocatedHoldingColor,
            marketTime: marketTime
        )
    }

    /// Why the list is empty when the minimum market value hides every
    /// holding. With some left, the page says nothing about the hidden ones:
    /// holdings that small aren't worth a line, and Settings shows the count.
    private var hiddenNote: String? {
        guard hiddenHoldingCount > 0 else { return nil }
        let minimum = PortfolioFormat.price(minimumMarketValue, currencyCode: portfolio.currencyCode)
        let holdings = hiddenHoldingCount == 1 ? "1 holding" : "\(hiddenHoldingCount) holdings"
        return "\(holdings) under \(minimum) hidden"
    }
}

/// Native press highlight for navigable holding rows inside a `ScrollView`.
private struct HoldingRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color(uiColor: .systemFill)
                    : Color.clear
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
