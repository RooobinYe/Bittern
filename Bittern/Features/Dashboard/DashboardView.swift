//
//  DashboardView.swift
//  Bittern
//

import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    let showSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.logoSource) private var logoSource
    @State private var viewportSize = CGSize(width: 390, height: 844)
#if DEBUG
    @State private var didRunDebugScreenshotExport = false
#endif
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false

    var body: some View {
        NavigationStack {
            DashboardContent(
                viewModel: viewModel,
                isPrivacyEnabled: $isPrivacyEnabled,
                connectBrokerage: showSettings
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BitternTheme.background)
            .errorToast(message: $viewModel.errorMessage)
            .navigationBarTitleDisplayMode(.inline)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                guard newSize.width > 0, newSize.height > 0 else { return }
                viewportSize = newSize
            }
            .toolbar {
                if providerNames.count > 1 || launchSkeleton?.hasMultipleProviders == true {
                    ToolbarItem(placement: .topBarLeading) {
                        if providerNames.count > 1 {
                            accountFilterMenu
                                .tint(viewModel.selectedProviderName == nil ? nil : BitternTheme.accent)
                        } else {
                            Button {} label: {
                                Label("Filter Accounts", systemImage: "building.columns")
                            }
                            .disabled(true)
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isPrivacyEnabled.toggle()
                        }
                    } label: {
                        Label(
                            isPrivacyEnabled ? "Show Values" : "Hide Values",
                            systemImage: isPrivacyEnabled ? "eye.slash" : "eye"
                        )
                    }

                    if let portfolioShareItem {
                        ShareLink(
                            item: portfolioShareItem,
                            // The share sheet shows a blank placeholder unless the
                            // item brings its own icon; the app icon can't be loaded
                            // by name, so ShareIcon is exported from AppIcon.icon.
                            preview: SharePreview("Bittern Portfolio", icon: Image(.shareIcon))
                        ) {
                            Label("Share Portfolio", systemImage: "square.and.arrow.up")
                        }
                    } else if launchSkeleton != nil {
                        Button {} label: {
                            Label("Share Portfolio", systemImage: "square.and.arrow.up")
                        }
                        .disabled(true)
                    }
                }

                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: showSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
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

    private var providerNames: [String] {
        viewModel.snapshot?.accounts.providerNames ?? []
    }

    private var launchSkeleton: LaunchSkeleton? {
        guard case .loading(let skeleton?) = viewModel.loadState else { return nil }
        return skeleton
    }

    /// Filters the portfolio between all accounts and a single provider.
    private var accountFilterMenu: some View {
        Menu {
            Picker("Account", selection: animatedProviderSelection) {
                Text("All Accounts")
                    .tag(String?.none)

                Divider()

                ForEach(providerNames, id: \.self) { providerName in
                    Text(providerName)
                        .tag(Optional(providerName))
                }
            }
        } label: {
            Label("Filter Accounts", systemImage: "building.columns")
        }
        .accessibilityValue(viewModel.selectedProviderName ?? "All Accounts")
    }

    private var animatedProviderSelection: Binding<String?> {
        Binding(
            get: { viewModel.selectedProviderName },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewModel.selectedProviderName = newValue
                }
            }
        )
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
        guard let visible = viewModel.visibleSnapshot else { return nil }
        let portfolio = includingSmallHoldings
            ? visible
            : visible.filtered(minimumMarketValue: viewModel.minPriceThreshold)

        return DashboardShareSnapshot(
            title: viewModel.selectedProviderName ?? "Portfolio",
            portfolio: portfolio,
            sortedHoldings: viewModel.sortOption.sorted(portfolio.holdings, by: viewModel.performanceMode),
            performanceMode: viewModel.performanceMode,
            sortOption: viewModel.sortOption,
            minimumMarketValue: viewModel.minPriceThreshold,
            hiddenHoldingCount: includingSmallHoldings ? 0 : viewModel.hiddenHoldingCount,
            isPrivacyEnabled: isPrivacyEnabled,
            priceStatus: viewModel.priceStatus,
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
    @State private var viewModel = PreviewSupport.dashboardViewModel(
        credentialsStore: PreviewSupport.credentialsStore()
    )

    var body: some View {
        DashboardView(viewModel: viewModel, showSettings: {})
    }
}
#endif
