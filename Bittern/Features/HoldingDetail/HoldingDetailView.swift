//
//  HoldingDetailView.swift
//  Bittern
//

import SwiftUI

/// Navigates by id, so the detail always shows the latest data for the
/// holding rather than the copy that was tapped.
struct HoldingRoute: Hashable {
    let holdingID: String
}

/// Looks the holding up in the current portfolio each time it draws.
struct HoldingDetailDestination: View {
    let route: HoldingRoute
    let viewModel: DashboardViewModel

    var body: some View {
        if let snapshot = viewModel.snapshot,
           let holding = snapshot.holdings.first(where: { $0.id == route.holdingID }) {
            HoldingDetailView(
                holding: holding,
                portfolio: viewModel.displaySnapshot ?? snapshot,
                isLive: viewModel.isLive(holding),
                isOnline: viewModel.isOnline
            )
            .environment(\.priceStatus, viewModel.priceStatus)
        } else {
            ContentUnavailableView(
                "Holding Unavailable",
                systemImage: "questionmark.circle",
                description: Text("This holding is no longer in your portfolio.")
            )
        }
    }
}

struct HoldingDetailView: View {
    let holding: PortfolioHolding
    /// The portfolio the holding's allocation is a share of.
    let portfolio: PortfolioSnapshot
    /// The holding's price is moving and current.
    var isLive = false
    var isOnline = true

    @State private var model = HoldingDetailModel()
    @Environment(\.portfolioRepository) private var repository
    @Environment(\.priceStatus) private var priceStatus
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false

    var body: some View {
        PaneGeometryReader { size, fold in
            let arrangement = Self.panes.arrangement(in: size, fold: fold)

            switch arrangement {
            case .single:
                list {
                    Section {
                        header
                            .listRowBackground(Color.clear)
                            .listRowInsets(.horizontal, 4)
                    }

                    Section {
                        chart(plotHeight: .standard, showsRangeSelector: true)
                            .listRowBackground(Color.clear)
                            .listRowInsets(.horizontal, 4)
                    }

                    info
                }
                .frame(maxWidth: Self.maximumContentWidth)
                .frame(maxWidth: .infinity)

            // The price and its chart lead, My Holdings beside them on the
            // first screen; above a fold, the price and chart, with the
            // ranges and My Holdings below.
            case .columns, .rows:
                PaneSplit(arrangement: arrangement) {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                            .padding(.horizontal, 4)
                        chart(plotHeight: .fill, showsRangeSelector: !arrangement.isRows)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, arrangement.isRows ? 24 : 0)
                    .padding(.top, 8)
                    .padding(.bottom, arrangement.isRows ? 0 : 16)
                } second: {
                    list {
                        if arrangement.isRows {
                            Section {
                                ChartRangeSelector(
                                    ranges: model.availableRanges,
                                    title: { $0.title },
                                    selectedRange: $model.selectedRange
                                ) {
                                    model.selectedPoint = nil
                                }
                                .listRowBackground(Color.clear)
                                .listRowInsets(.horizontal, 4)
                            }
                        }

                        info
                    }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        // The header shows the full name; the symbol stays readable once it
        // scrolls away and never truncates in the inline bar.
        .navigationTitle(holding.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .errorToast(message: $model.errorMessage)
        .task(id: model.selectedRange) {
            await model.load(model.selectedRange, for: holding, using: repository, isOnline: isOnline)
        }
        // New prices move the chart's last bar; no animation.
        .onChange(of: holding) { _, holding in
            for range in model.follow(holding) {
                Task {
                    await model.load(range, for: holding, using: repository, isOnline: isOnline, reload: true)
                }
            }
        }
        .onChange(of: isOnline) { _, isOnline in
            guard isOnline else { return }
            let range = model.selectedRange
            Task {
                await model.load(range, for: holding, using: repository, isOnline: true)
            }
        }
    }

    private func list<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        List {
            content()
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .softNavigationBarEdge()
    }

    private var header: some View {
        HoldingAssetHeader(
            holding: holding,
            series: model.visibleSeries?.points ?? [],
            range: model.selectedRange,
            selectedPoint: model.selectedPoint,
            seriesBaselinePrice: model.visibleSeries?.baselinePrice,
            isPrivacyEnabled: isPrivacyEnabled,
            isRangeLoading: model.isLoading,
            avatarColor: BitternTheme.holdingAllocationColor(
                for: holding,
                in: portfolio.holdings
            )
        )
    }

    private func chart(
        plotHeight: PerformanceChartPlotHeight,
        showsRangeSelector: Bool
    ) -> some View {
        HoldingChartSection(
            series: model.visibleSeries?.points ?? [],
            timeDomain: model.visibleSeries?.timeDomain,
            valueBounds: model.visibleValueBounds,
            previousClose: holding.previousClose,
            seriesBaselinePrice: model.visibleSeries?.baselinePrice,
            currencyCode: holding.currencyCode,
            isPrivacyEnabled: isPrivacyEnabled,
            ranges: model.availableRanges,
            range: $model.selectedRange,
            selectedPoint: $model.selectedPoint,
            isLoading: model.isLoading,
            isUnavailableOffline: model.isVisibleRangeUnavailableOffline,
            endMarker: priceStatus.isStale ? .stale : isLive ? .live : .plain,
            plotHeight: plotHeight,
            showsRangeSelector: showsRangeSelector
        )
    }

    private var info: some View {
        HoldingInfoSection(
            holding: holding,
            snapshot: portfolio,
            isPrivacyEnabled: isPrivacyEnabled
        )
    }

    private static let maximumContentWidth: CGFloat = 900

    /// The price and its chart need about an iPhone's width; My Holdings,
    /// room for its labels beside their values. Side by side only when
    /// wider than tall: a tall view shows My Holdings under the chart.
    static let panes = PaneRequirements(
        minimumLeadingWidth: 360,
        minimumTrailingWidth: 280,
        preferredWidth: .trailing(330),
        // An inset list keeps no margin on an edge inside the screen.
        columnSpacing: 20,
        minimumColumnsHeight: 360,
        columnsOnlyWhenWide: true,
        minimumRowHeight: 240
    )
}

#if DEBUG
#Preview {
    let snapshot = DemoPortfolio.snapshot
    NavigationStack {
        HoldingDetailView(
            holding: snapshot.holdings[3],
            portfolio: snapshot
        )
    }
}
#endif
