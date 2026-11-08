//
//  DashboardContent.swift
//  Bittern
//

import SwiftUI

enum DashboardLayoutMetrics {
    /// These are content readability bounds, not device breakpoints. The split
    /// layout appears whenever both panes can keep their useful minimum width.
    static let minimumChartColumnWidth: CGFloat = 320
    static let idealChartColumnWidth: CGFloat = 440
    static let minimumHoldingsColumnWidth: CGFloat = 360
    static let columnSpacing: CGFloat = 28
    static let preferredSplitWidth: CGFloat = 756
    static let minimumSplitHeight: CGFloat = 460
    static let maximumChartSide: CGFloat = 500
    static let maximumContentWidth: CGFloat = 1_280
    static let maximumExportWidth: CGFloat = maximumContentWidth + 48

    static func layoutMode(in size: CGSize) -> DashboardLayoutMode {
        size.width >= preferredSplitWidth
            && size.height >= minimumSplitHeight
            ? .split
            : .stacked
    }
}

enum DashboardLayoutMode: Sendable {
    case stacked
    case split
}

/// What the live dashboard lets people change. The exported image has no
/// controls, so its containers show the same labels without wrapping them in
/// buttons and menus.
struct DashboardControls {
    // Main-actor function types are Sendable, which `Binding(get:set:)`
    // asks of its setter.
    let selectPerformanceMode: @MainActor (PerformanceMode) -> Void
    let selectSortOption: @MainActor (HoldingSortOption) -> Void
    let refresh: () async -> Void
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
        case .loading:
            ProgressView("Loading portfolio…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Portfolio Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.fullRefresh() }
                }
            }
        case .loaded(let snapshot):
            GeometryReader { proxy in
                DashboardVisualContent(
                    portfolio: viewModel.displaySnapshot ?? snapshot,
                    sortedHoldings: viewModel.sortedHoldings,
                    performanceMode: viewModel.performanceMode,
                    sortOption: viewModel.sortOption,
                    minimumMarketValue: viewModel.minPriceThreshold,
                    hiddenHoldingCount: viewModel.hiddenHoldingCount,
                    isPrivacyEnabled: isPrivacyEnabled,
                    layoutMode: DashboardLayoutMetrics.layoutMode(in: proxy.size),
                    controls: controls
                )
            }
        }
    }

    private var controls: DashboardControls {
        DashboardControls(
            selectPerformanceMode: { viewModel.performanceMode = $0 },
            selectSortOption: { viewModel.sortOption = $0 },
            refresh: { await viewModel.refresh() }
        )
    }
}

/// The single visual source for both the live dashboard and its exported image.
/// The live dashboard is a system list; the export lays the same rows out in
/// stacks, with no controls, and renders every row. The responsive layout
/// mode always comes from the viewport that initiated the share.
struct DashboardVisualContent: View {
    let portfolio: PortfolioSnapshot
    let sortedHoldings: [PortfolioHolding]
    let performanceMode: PerformanceMode
    let sortOption: HoldingSortOption
    let minimumMarketValue: Double
    let hiddenHoldingCount: Int
    let isPrivacyEnabled: Bool
    let layoutMode: DashboardLayoutMode
    /// Nil when rendering the exported image.
    let controls: DashboardControls?

    @State private var marketTime = Date()
    @State private var lensMotion = AllocationLensMotion()

    /// The bands' colors, so a holding without a logo matches its band.
    private var holdingColorLookup: [String: Color] {
        BitternTheme.holdingAllocationColors(for: portfolio.holdings)
    }

    /// When the next pre- or post-market session shown in a row ends, so the
    /// row can stop showing it.
    private var nextExtendedHoursBoundary: Date? {
        sortedHoldings.flatMap { holding in
            [
                holding.activePreMarketChange(at: marketTime)?.sessionEnd,
                holding.activePostMarketChange(at: marketTime)?.sessionEnd
            ].compactMap { $0 }
        }.min()
    }

    var body: some View {
        content
            // Above the list, so the lifted lens can go anywhere on the page.
            .overlay { LiftedAllocationLens(motion: lensMotion) }
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
        case (.stacked, let controls?):
            List {
                Section {
                    allocation(fillsAvailableSpace: false)
                        .padding(.vertical, 8)
                        .listRowInsets(.horizontal, 0)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                holdingsSection(controls: controls)
            }
            .listStyle(.plain)
            .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
            .frame(maxWidth: .infinity)
            .softNavigationBarEdge()
            .refreshable { await controls.refresh() }

        case (.split, let controls?):
            HStack(alignment: .top, spacing: DashboardLayoutMetrics.columnSpacing) {
                allocation(fillsAvailableSpace: true)
                    .frame(
                        minWidth: DashboardLayoutMetrics.minimumChartColumnWidth,
                        idealWidth: DashboardLayoutMetrics.idealChartColumnWidth,
                        maxWidth: DashboardLayoutMetrics.maximumChartSide,
                        maxHeight: .infinity
                    )

                List {
                    holdingsSection(controls: controls)
                }
                .listStyle(.plain)
                .frame(minWidth: DashboardLayoutMetrics.minimumHoldingsColumnWidth)
                .softNavigationBarEdge()
                .refreshable { await controls.refresh() }
            }
            .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
            .padding(.leading)
            .frame(maxWidth: .infinity)

        // The export's insets mirror the live list's: the allocation brings
        // its own and spans the row, the holdings sit 16 in from each side.
        // A narrower allocation would wrap the legend differently.
        case (.stacked, nil):
            VStack(spacing: 24) {
                allocation(fillsAvailableSpace: false)
                exportHoldings
                    .padding(.horizontal)
            }
            .padding(.bottom, 14)
            .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
            .frame(maxWidth: .infinity)

        case (.split, nil):
            HStack(alignment: .top, spacing: DashboardLayoutMetrics.columnSpacing) {
                allocation(fillsAvailableSpace: false)
                    .frame(
                        minWidth: DashboardLayoutMetrics.minimumChartColumnWidth,
                        idealWidth: DashboardLayoutMetrics.idealChartColumnWidth,
                        maxWidth: DashboardLayoutMetrics.maximumChartSide,
                        alignment: .top
                    )

                exportHoldings
                    .padding(.horizontal)
                    .frame(minWidth: DashboardLayoutMetrics.minimumHoldingsColumnWidth)
            }
            .padding(.bottom, 14)
            .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
            .padding(.leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func allocation(fillsAvailableSpace: Bool) -> some View {
        PortfolioAllocationSection(
            snapshot: portfolio,
            performanceMode: performanceMode,
            isPrivacyEnabled: isPrivacyEnabled,
            fillsAvailableSpace: fillsAvailableSpace,
            selectPerformanceMode: controls?.selectPerformanceMode,
            lensMotion: controls == nil ? nil : lensMotion
        )
    }

    private func header(controls: DashboardControls?) -> HoldingsHeader {
        HoldingsHeader(
            lastUpdated: portfolio.lastUpdated,
            performanceMode: performanceMode,
            sortOption: sortOption,
            controls: controls
        )
    }

    /// The header is the section's first row rather than its header: a plain
    /// list pins headers over the rows scrolling under them.
    private func holdingsSection(controls: DashboardControls) -> some View {
        Section {
            header(controls: controls)
                .listRowSeparator(.hidden)
                .listRowInsets(.horizontal, 16)

            if sortedHoldings.isEmpty {
                EmptyHoldingsView(hiddenNote: hiddenNote)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(sortedHoldings) { holding in
                    NavigationLink(value: HoldingRoute(holdingID: holding.id)) {
                        row(for: holding)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .listRowInsets(.horizontal, 16)
                    // A line under the last row divides it from nothing.
                    .listRowSeparator(
                        holding.id == sortedHoldings.last?.id ? .hidden : .automatic,
                        edges: .bottom
                    )
                }
            }
        }
    }

    /// The export's version of the holdings section.
    private var exportHoldings: some View {
        VStack(spacing: 0) {
            header(controls: nil)
                .padding(.bottom, 8)

            if sortedHoldings.isEmpty {
                EmptyHoldingsView(hiddenNote: hiddenNote)
                    .padding(.top, 24)
            } else {
                ForEach(sortedHoldings) { holding in
                    row(for: holding)
                        .padding(.vertical, 12)

                    if holding.id != sortedHoldings.last?.id {
                        Divider()
                    }
                }
            }
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
