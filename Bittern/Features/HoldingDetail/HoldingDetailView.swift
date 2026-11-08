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
        List {
            Section {
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
                .listRowBackground(Color.clear)
                .listRowInsets(.horizontal, 4)
            }

            Section {
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
                    endMarker: priceStatus.isStale ? .stale : isLive ? .live : .plain
                )
                .listRowBackground(Color.clear)
                .listRowInsets(.horizontal, 4)
            }

            HoldingInfoSection(
                holding: holding,
                snapshot: portfolio,
                isPrivacyEnabled: isPrivacyEnabled
            )
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .frame(maxWidth: Self.maximumContentWidth)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollContentBackground(.hidden)
        .softNavigationBarEdge()
        .refreshable {
            // An unstructured task, so a redraw during the pull doesn't
            // cancel the reload.
            let range = model.selectedRange
            await Task {
                await model.load(range, for: holding, using: repository, isOnline: isOnline, reload: true)
            }.value
        }
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

    private static let maximumContentWidth: CGFloat = 900
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
