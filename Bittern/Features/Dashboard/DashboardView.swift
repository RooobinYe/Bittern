//
//  DashboardView.swift
//  Bittern
//

import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    let credentialsStore: CredentialsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.logoSource) private var logoSource
    @State private var isShowingSettings = false
    @State private var viewportSize = CGSize(width: 390, height: 844)
#if DEBUG
    @State private var didRunDebugScreenshotExport = false
#endif
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false

    var body: some View {
        NavigationStack {
            ZStack {
                BitternTheme.background.ignoresSafeArea()

                DashboardContent(
                    viewModel: viewModel,
                    isPrivacyEnabled: $isPrivacyEnabled
                )
                .frame(maxWidth: .infinity)
            }
            .errorToast(message: $viewModel.errorMessage)
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.large)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                guard newSize.width > 0, newSize.height > 0 else { return }
                viewportSize = newSize
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        PortfolioAvatarIcon()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("SnapTrade settings")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if let portfolioShareItem {
                        ShareLink(
                            item: portfolioShareItem,
                            preview: SharePreview("Bittern Portfolio")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share portfolio")
                    }
                }
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView(credentialsStore: credentialsStore, viewModel: viewModel)
            }
            .navigationDestination(for: HoldingRoute.self) { route in
                HoldingDetailDestination(route: route, viewModel: viewModel)
            }
#if DEBUG
            .task {
                await exportDebugScreenshotIfNeeded()
            }
#endif
        }
    }

    private var portfolioShareItem: PortfolioShareItem? {
        guard let shareSnapshot = shareSnapshot() else { return nil }
        let screenshotColorScheme = colorScheme
        let screenshotScale = displayScale
        let screenshotDynamicTypeSize = dynamicTypeSize
        let logoSource = logoSource

        return PortfolioShareItem {
            guard let data = await shareSnapshot.renderPNG(
                colorScheme: screenshotColorScheme,
                scale: screenshotScale,
                dynamicTypeSize: screenshotDynamicTypeSize,
                logoSource: logoSource
            ) else {
                throw PortfolioShareError.renderingFailed
            }

            return data
        }
    }

    /// What the dashboard shows now, frozen for rendering into an image.
    private func shareSnapshot(includingSmallHoldings: Bool = false) -> DashboardShareSnapshot? {
        guard let snapshot = viewModel.snapshot,
              let visible = viewModel.visibleSnapshot
        else {
            return nil
        }
        let portfolio = includingSmallHoldings
            ? visible
            : visible.filtered(minimumMarketValue: viewModel.minPriceThreshold)

        return DashboardShareSnapshot(
            filterAccounts: snapshot.accounts,
            portfolio: portfolio,
            allocationHoldings: snapshot.holdings,
            sortedHoldings: viewModel.sortOption.sorted(portfolio.holdings, by: viewModel.performanceMode),
            selectedProviderName: viewModel.selectedProviderName,
            performanceMode: viewModel.performanceMode,
            sortOption: viewModel.sortOption,
            isPrivacyEnabled: isPrivacyEnabled,
            viewportSize: viewportSize,
            layoutMode: DashboardLayoutMetrics.layoutMode(in: viewportSize)
        )
    }

    // MARK: - Debug

#if DEBUG
    private func exportDebugScreenshotIfNeeded() async {
        guard !didRunDebugScreenshotExport else { return }
        didRunDebugScreenshotExport = true

        guard ProcessInfo.processInfo.environment["BITTERN_EXPORT_SCREENSHOT_ON_LAUNCH"] == "1" else {
            return
        }

        try? await Task.sleep(for: .milliseconds(500))

        // The debug export always captures the full, unfiltered portfolio.
        guard var shareSnapshot = shareSnapshot(includingSmallHoldings: true) else { return }
        shareSnapshot.isPrivacyEnabled = false

        guard let data = await shareSnapshot.renderPNG(
                  colorScheme: colorScheme,
                  scale: displayScale,
                  dynamicTypeSize: dynamicTypeSize,
                  logoSource: logoSource
              ),
              let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else {
            return
        }

        let screenshotURL = cachesURL.appendingPathComponent("bittern-debug-screenshot.png")
        try? data.write(to: screenshotURL, options: [.atomic])
    }
#endif
}

struct PortfolioAvatarIcon: View {
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: "leaf.fill")
            .font(.title3.bold())
            .foregroundStyle(BitternTheme.accent)
            .frame(width: size, height: size)
            .offset(x: -1, y: -1)
    }
}

#if DEBUG
#Preview("Phone Portrait", traits: .fixedLayout(width: 393, height: 852)) {
    DashboardPreview()
}

#Preview("Phone Landscape", traits: .fixedLayout(width: 852, height: 393)) {
    DashboardPreview()
}

#Preview("Compact Window", traits: .fixedLayout(width: 600, height: 500)) {
    DashboardPreview()
}

#Preview("iPad Landscape", traits: .fixedLayout(width: 1_024, height: 768)) {
    DashboardPreview()
}

#Preview("Wide Window", traits: .fixedLayout(width: 1_200, height: 700)) {
    DashboardPreview()
}

private struct DashboardPreview: View {
    @State private var credentialsStore: CredentialsStore
    @State private var viewModel: DashboardViewModel

    init() {
        let credentialsStore = PreviewSupport.credentialsStore()
        _credentialsStore = State(initialValue: credentialsStore)
        _viewModel = State(
            initialValue: PreviewSupport.dashboardViewModel(credentialsStore: credentialsStore)
        )
    }

    var body: some View {
        DashboardView(viewModel: viewModel, credentialsStore: credentialsStore)
    }
}
#endif
