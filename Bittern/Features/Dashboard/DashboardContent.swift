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
    let selectProvider: (String?) -> Void
    let togglePrivacy: () -> Void
    let selectPerformanceMode: (PerformanceMode) -> Void
    let selectSortOption: (HoldingSortOption) -> Void
    let refresh: () async -> Void
}

struct DashboardContent: View {
    let viewModel: DashboardViewModel
    @Binding var isPrivacyEnabled: Bool

    var body: some View {
        switch viewModel.loadState {
        case .notLoaded:
            ContentUnavailableView(
                "No Portfolio Connected",
                systemImage: "building.columns",
                description: Text("Connect a brokerage in Settings to see your holdings.")
            )
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
                    filterAccounts: snapshot.accounts,
                    portfolio: viewModel.displaySnapshot ?? snapshot,
                    allocationHoldings: snapshot.holdings,
                    sortedHoldings: viewModel.sortedHoldings,
                    selectedProviderName: viewModel.selectedProviderName,
                    performanceMode: viewModel.performanceMode,
                    sortOption: viewModel.sortOption,
                    isPrivacyEnabled: isPrivacyEnabled,
                    layoutMode: DashboardLayoutMetrics.layoutMode(in: proxy.size),
                    controls: controls
                )
            }
        }
    }

    private var controls: DashboardControls {
        DashboardControls(
            selectProvider: { providerName in
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewModel.selectedProviderName = providerName
                }
            },
            togglePrivacy: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isPrivacyEnabled.toggle()
                }
            },
            selectPerformanceMode: { viewModel.performanceMode = $0 },
            selectSortOption: { viewModel.sortOption = $0 },
            refresh: { await viewModel.refresh() }
        )
    }
}

/// The single visual source for both the live dashboard and its exported image.
/// Export leaves out the controls and renders every row; the responsive layout
/// mode always comes from the viewport that initiated the share.
struct DashboardVisualContent: View {
    let filterAccounts: [PortfolioAccount]
    let portfolio: PortfolioSnapshot
    let allocationHoldings: [PortfolioHolding]
    let sortedHoldings: [PortfolioHolding]
    let selectedProviderName: String?
    let performanceMode: PerformanceMode
    let sortOption: HoldingSortOption
    let isPrivacyEnabled: Bool
    let layoutMode: DashboardLayoutMode
    /// Nil when rendering the exported image.
    let controls: DashboardControls?

    private var holdingColorLookup: [String: Color] {
        BitternTheme.holdingAllocationColors(for: allocationHoldings)
    }

    @ViewBuilder
    var body: some View {
        switch (layoutMode, controls) {
        case (.stacked, let controls?):
            ScrollView {
                stackedSections
                    .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity)
            }
            .softNavigationBarEdge()
            .refreshable { await controls.refresh() }

        case (.stacked, nil):
            stackedSections
                .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
                .padding(.horizontal)
                .frame(maxWidth: .infinity)

        case (.split, let controls):
            splitContent(refresh: controls?.refresh)
                .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
        }
    }

    private var accountFilter: some View {
        AccountFilterBar(
            providerNames: filterAccounts.providerNames,
            selectedProviderName: selectedProviderName,
            isPrivacyEnabled: isPrivacyEnabled,
            controls: controls
        )
    }

    private func donut(fillsAvailableSpace: Bool) -> some View {
        PortfolioDonutSection(
            snapshot: portfolio,
            holdingColorLookup: holdingColorLookup,
            performanceMode: performanceMode,
            isPrivacyEnabled: isPrivacyEnabled,
            fillsAvailableSpace: fillsAvailableSpace,
            selectPerformanceMode: controls?.selectPerformanceMode
        )
    }

    private var holdings: some View {
        HoldingsSection(
            sortedHoldings: sortedHoldings,
            snapshot: portfolio,
            holdingColorLookup: holdingColorLookup,
            performanceMode: performanceMode,
            sortOption: sortOption,
            isPrivacyEnabled: isPrivacyEnabled,
            controls: controls
        )
    }

    private var stackedSections: some View {
        VStack(spacing: 24) {
            accountFilter
            donut(fillsAvailableSpace: false)
            holdings
        }
        .padding(.bottom, 14)
    }

    /// The live split view scrolls its holdings beside a chart that fills the
    /// column; the export lays both out at their natural height.
    private func splitContent(refresh: (() async -> Void)?) -> some View {
        VStack(spacing: 20) {
            accountFilter

            HStack(alignment: .top, spacing: DashboardLayoutMetrics.columnSpacing) {
                if let refresh {
                    donut(fillsAvailableSpace: true)
                        .frame(
                            minWidth: DashboardLayoutMetrics.minimumChartColumnWidth,
                            idealWidth: DashboardLayoutMetrics.idealChartColumnWidth,
                            maxWidth: DashboardLayoutMetrics.maximumChartSide,
                            maxHeight: .infinity
                        )

                    ScrollView {
                        splitHoldings
                    }
                    .frame(minWidth: DashboardLayoutMetrics.minimumHoldingsColumnWidth)
                    .contentMargins(.horizontal, 8, for: .scrollContent)
                    .softNavigationBarEdge()
                    .refreshable { await refresh() }
                } else {
                    donut(fillsAvailableSpace: false)
                        .frame(
                            minWidth: DashboardLayoutMetrics.minimumChartColumnWidth,
                            idealWidth: DashboardLayoutMetrics.idealChartColumnWidth,
                            maxWidth: DashboardLayoutMetrics.maximumChartSide,
                            alignment: .top
                        )

                    splitHoldings
                        .frame(minWidth: DashboardLayoutMetrics.minimumHoldingsColumnWidth)
                }
            }
        }
    }

    private var splitHoldings: some View {
        holdings
            .padding(.bottom, 14)
    }
}
