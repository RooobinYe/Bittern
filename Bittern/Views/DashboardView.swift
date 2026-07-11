//
//  DashboardView.swift
//  Bittern
//

import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var credentialsStore: CredentialsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var isShowingSettings = false
    @State private var containerWidth: CGFloat = 390
#if DEBUG
    @State private var didRunDebugScreenshotExport = false
#endif
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false
    @AppStorage(AppSettingKey.minPriceThreshold) private var minPriceThreshold = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                BitternTheme.background.ignoresSafeArea()

                DashboardContent(
                    viewModel: viewModel,
                    isPrivacyEnabled: $isPrivacyEnabled,
                    minPriceThreshold: minPriceThreshold
                )
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.large)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                containerWidth = newWidth
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
                    ShareLink(
                        item: portfolioShareItem,
                        preview: SharePreview("Bittern Portfolio")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share portfolio")
                }
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView(credentialsStore: credentialsStore, viewModel: viewModel)
            }
            .navigationDestination(for: PortfolioHolding.self) { holding in
                HoldingDetailView(
                    holding: holding,
                    snapshot: viewModel.visibleSnapshot,
                    providerName: providerName(for: holding.accountID)
                )
            }
#if DEBUG
            .task {
                await exportDebugScreenshotIfNeeded()
            }
#endif
        }
    }

    private func providerName(for accountID: String) -> String {
        viewModel.visibleSnapshot.accounts.first { $0.id == accountID }?.providerName ?? ""
    }

    private var portfolioShareItem: PortfolioShareItem {
        let screenshotWidth = min(
            max(containerWidth, 1),
            DashboardLayoutMetrics.maximumExportWidth
        )
        let screenshotColorScheme = colorScheme
        let screenshotScale = displayScale
        let privacyEnabled = isPrivacyEnabled
        let priceThreshold = minPriceThreshold

        return PortfolioShareItem {
            let content = PortfolioShareScreenshotContent(
                viewModel: viewModel,
                isPrivacyEnabled: .constant(privacyEnabled),
                minPriceThreshold: priceThreshold,
                width: screenshotWidth
            )
            .fontDesign(.rounded)
            .dynamicTypeSize(.large)
            .environment(\.colorScheme, screenshotColorScheme)
            .environment(\.isRenderingScreenshot, true)

            guard let data = ScreenshotRenderer.render(
                content,
                width: screenshotWidth,
                scale: screenshotScale,
                backgroundColor: screenshotColorScheme.systemBackgroundColor
            )?.pngData() else {
                throw PortfolioShareError.renderingFailed
            }

            return data
        }
    }

    // MARK: - Debug

#if DEBUG
    @MainActor
    private func exportDebugScreenshotIfNeeded() async {
        guard !didRunDebugScreenshotExport else { return }
        didRunDebugScreenshotExport = true

        guard ProcessInfo.processInfo.environment["BITTERN_EXPORT_SCREENSHOT_ON_LAUNCH"] == "1" else {
            return
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        let screenshotWidth = min(
            max(containerWidth, 1),
            DashboardLayoutMetrics.maximumExportWidth
        )
        let screenshotColorScheme = colorScheme

        guard let image = ScreenshotRenderer.render(
                  PortfolioShareScreenshotContent(
                      viewModel: viewModel,
                      isPrivacyEnabled: .constant(false),
                      minPriceThreshold: 0,
                      width: screenshotWidth
                  )
                  .fontDesign(.rounded)
                  .dynamicTypeSize(.large)
                  .environment(\.colorScheme, screenshotColorScheme)
                  .environment(\.isRenderingScreenshot, true),
                  width: screenshotWidth,
                  scale: displayScale,
                  backgroundColor: screenshotColorScheme.systemBackgroundColor
              ),
              let data = image.pngData(),
              let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }

        let screenshotURL = cachesURL.appendingPathComponent("bittern-debug-screenshot.png")
        try? data.write(to: screenshotURL, options: [.atomic])
    }
#endif
}

private extension ColorScheme {
    var systemBackgroundColor: UIColor {
        UIColor.systemBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: userInterfaceStyle)
        )
    }

    private var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .dark:
            .dark
        default:
            .light
        }
    }
}

private struct PortfolioShareItem: Transferable, @unchecked Sendable {
    let renderPNG: @MainActor @Sendable () throws -> Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await item.renderPNG()
        }
        .suggestedFileName("Bittern Portfolio.png")
    }
}

private enum PortfolioShareError: Error {
    case renderingFailed
}

// MARK: - Navigation and Share Header

private struct PortfolioAvatarIcon: View {
    let size: CGFloat

    init(size: CGFloat = 36) {
        self.size = size
    }

    var body: some View {
        Image(systemName: "leaf.fill")
            .font(.title3.bold())
            .foregroundStyle(BitternTheme.blue)
            .frame(width: size, height: size)
            .offset(x: -1, y: -1)
    }
}

private struct PortfolioShareHeader: View {
    var body: some View {
        ZStack {
            HStack {
                PortfolioAvatarIcon(size: 42)

                Spacer()

                Image(systemName: "square.and.arrow.up")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BitternTheme.secondaryInk)
            }

            Text("Portfolio")
                .font(.title2.bold())
                .foregroundStyle(BitternTheme.ink)
        }
    }
}

// MARK: - Share Screenshot Content

private struct PortfolioShareScreenshotContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPrivacyEnabled: Bool
    let minPriceThreshold: Double
    let width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            PortfolioShareHeader()
                .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .background(BitternTheme.background)

            DashboardContent(
                viewModel: viewModel,
                isPrivacyEnabled: $isPrivacyEnabled,
                minPriceThreshold: minPriceThreshold
            )
            .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
            .padding(.horizontal, 24)
        }
        .frame(width: width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(BitternTheme.background)
    }
}

// MARK: - Dashboard Content

private enum DashboardLayoutMetrics {
    /// These are content readability bounds, not device breakpoints. The split
    /// layout appears whenever both panes can keep their useful minimum width.
    static let minimumChartColumnWidth: CGFloat = 320
    static let idealChartColumnWidth: CGFloat = 440
    static let minimumHoldingsColumnWidth: CGFloat = 360
    static let columnSpacing: CGFloat = 28
    static let contentHorizontalPadding: CGFloat = 24
    static let preferredSplitWidth: CGFloat = 756
    static let minimumSplitHeight: CGFloat = 460
    static let maximumChartSide: CGFloat = 500
    static let maximumContentWidth: CGFloat = 1_280
    static let maximumExportWidth: CGFloat = maximumContentWidth + 48

    static func usesColumns(in size: CGSize) -> Bool {
        return size.width >= preferredSplitWidth
            && size.height >= minimumSplitHeight
    }
}

private struct DashboardContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPrivacyEnabled: Bool
    let minPriceThreshold: Double
    @Environment(\.isRenderingScreenshot) private var isForScreenshot

    @ViewBuilder
    var body: some View {
        if isForScreenshot {
            stackedSections
        } else {
            GeometryReader { proxy in
                if DashboardLayoutMetrics.usesColumns(in: proxy.size) {
                    splitContent
                        .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
                        .padding(.horizontal, DashboardLayoutMetrics.contentHorizontalPadding)
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        stackedSections
                            .frame(maxWidth: DashboardLayoutMetrics.maximumContentWidth)
                            .frame(maxWidth: .infinity)
                    }
                    .contentMargins(.horizontal, DashboardLayoutMetrics.contentHorizontalPadding, for: .scrollContent)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .refreshable { await viewModel.refresh() }
                }
            }
        }
    }

    private var accountFilter: some View {
        AccountFilterBar(
            accounts: viewModel.snapshot.accounts,
            selectedProviderName: $viewModel.selectedProviderName,
            isPrivacyEnabled: $isPrivacyEnabled
        )
    }

    private var stackedDonut: some View {
        PortfolioDonutSection(
            snapshot: viewModel.visibleSnapshot,
            performanceMode: $viewModel.performanceMode,
            isPrivacyEnabled: isPrivacyEnabled,
            minPriceThreshold: minPriceThreshold,
            fillsAvailableSpace: false
        )
    }

    private var splitDonut: some View {
        PortfolioDonutSection(
            snapshot: viewModel.visibleSnapshot,
            performanceMode: $viewModel.performanceMode,
            isPrivacyEnabled: isPrivacyEnabled,
            minPriceThreshold: minPriceThreshold,
            fillsAvailableSpace: true
        )
    }

    private var holdings: some View {
        HoldingsSection(
            viewModel: viewModel,
            isPrivacyEnabled: isPrivacyEnabled,
            minPriceThreshold: minPriceThreshold
        )
    }

    private var stackedSections: some View {
        VStack(spacing: 24) {
            accountFilter
            stackedDonut

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            holdings
        }
        .padding(.bottom, 14)
    }

    private var splitContent: some View {
        VStack(spacing: 20) {
            accountFilter

            HStack(alignment: .top, spacing: DashboardLayoutMetrics.columnSpacing) {
                splitDonut
                    .frame(
                        minWidth: DashboardLayoutMetrics.minimumChartColumnWidth,
                        idealWidth: DashboardLayoutMetrics.idealChartColumnWidth,
                        maxWidth: DashboardLayoutMetrics.maximumChartSide,
                        maxHeight: .infinity
                    )

                ScrollView {
                    VStack(spacing: 16) {
                        if let errorMessage = viewModel.errorMessage {
                            ErrorBanner(message: errorMessage)
                        }

                        holdings
                    }
                    .padding(.bottom, 14)
                }
                .frame(minWidth: DashboardLayoutMetrics.minimumHoldingsColumnWidth)
                .contentMargins(.horizontal, 8, for: .scrollContent)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .refreshable { await viewModel.refresh() }
            }
        }
    }
}

// MARK: - Account Filter Bar

private struct AccountFilterBar: View {
    let accounts: [PortfolioAccount]
    @Binding var selectedProviderName: String?
    @Binding var isPrivacyEnabled: Bool
    @Environment(\.isRenderingScreenshot) private var isForScreenshot

    private var providerNames: [String] {
        var seen: Set<String> = []
        return accounts.reduce(into: []) { result, account in
            let name = account.providerName
            if seen.insert(name).inserted {
                result.append(name)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if isForScreenshot {
                    HStack(spacing: 20) {
                        AccountTabLabel(
                            title: "All",
                            systemImage: nil,
                            isSelected: selectedProviderName == nil
                        )

                        ForEach(providerNames, id: \.self) { providerName in
                            AccountTabLabel(
                                title: providerName,
                                systemImage: nil,
                                isSelected: selectedProviderName == providerName
                            )
                        }
                    }
                    .padding(.trailing, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            AccountTabButton(
                                title: "All",
                                systemImage: nil,
                                isSelected: selectedProviderName == nil
                            ) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    selectedProviderName = nil
                                }
                            }

                            ForEach(providerNames, id: \.self) { providerName in
                                AccountTabButton(
                                    title: providerName,
                                    systemImage: nil,
                                    isSelected: selectedProviderName == providerName
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selectedProviderName = providerName
                                    }
                                }
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }

                if isForScreenshot {
                    Image(systemName: isPrivacyEnabled ? "eye.slash" : "eye")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(BitternTheme.secondaryInk)
                        .frame(width: 30, height: 38)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isPrivacyEnabled.toggle()
                        }
                    } label: {
                        Image(systemName: isPrivacyEnabled ? "eye.slash" : "eye")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(BitternTheme.secondaryInk)
                            .frame(width: 30, height: 38)
                    }
                    .accessibilityLabel(isPrivacyEnabled ? "Show values" : "Hide values")
                }
            }

            Divider()
                .frame(height: 1)
                .overlay(BitternTheme.softLine)
        }
    }
}

// MARK: - Donut Section

private struct PortfolioDonutSection: View {
    let snapshot: PortfolioSnapshot
    @Binding var performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let minPriceThreshold: Double
    let fillsAvailableSpace: Bool

    @ViewBuilder
    var body: some View {
        if fillsAvailableSpace {
            GeometryReader { proxy in
                let side = max(
                    min(
                        proxy.size.width,
                        proxy.size.height,
                        DashboardLayoutMetrics.maximumChartSide
                    ),
                    1
                )

                chart
                    .frame(width: side, height: side)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        } else {
            chart
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: DashboardLayoutMetrics.maximumChartSide)
                .frame(maxWidth: .infinity)
        }
    }

    private var chart: some View {
        DonutPortfolioChart(
            snapshot: snapshot,
            performanceMode: $performanceMode,
            isPrivacyEnabled: isPrivacyEnabled,
            minPriceThreshold: minPriceThreshold
        )
    }
}

private struct DonutPortfolioChart: View {
    let snapshot: PortfolioSnapshot
    @Binding var performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let minPriceThreshold: Double
    @Environment(\.isRenderingScreenshot) private var isForScreenshot

    private var filteredHoldings: [PortfolioHolding] {
        snapshot.holdings.filter { $0.marketValue.map { $0 >= minPriceThreshold } ?? true }
    }

    private var performanceAmount: Double? {
        snapshot.performanceAmount(for: performanceMode)
    }

    private var performancePercent: Double? {
        snapshot.performancePercent(for: performanceMode)
    }

    private var segments: [DonutSegmentInfo] {
        guard snapshot.totalMarketValue != nil else { return [] }
        return makeSegments(from: filteredHoldings)
    }

    var body: some View {
        GeometryReader { proxy in
            let canvasSide = min(proxy.size.width, proxy.size.height)
            let labelExtent = min(max(canvasSide * 0.19, 64), 84)
            let labelRadiusFactor = 0.64
            // Solve for the largest ring whose outer labels still fit in the
            // canvas instead of tying the ring to a device or screen ratio.
            let side = max((canvasSide - labelExtent) / (labelRadiusFactor * 2), 1)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let labelRadius = side * labelRadiusFactor
            let strokeWidth = max(side * 0.17, 1)
            let centerSpacing = min(max(side * 0.025, 3), 7)
            let labelScale = min(max(canvasSide / 340, 0.78), 1.08)

            ZStack {
                Circle()
                    .stroke(BitternTheme.surface, lineWidth: strokeWidth)
                    .frame(width: side, height: side)
                    .position(center)

                ForEach(segments) { segment in
                    DonutSegmentShape(
                        startAngle: .degrees(segment.startAngle),
                        endAngle: .degrees(segment.endAngle)
                    )
                    .stroke(segment.color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))
                    .frame(width: side, height: side)
                    .position(center)
                }

                VStack(spacing: centerSpacing) {
                    Text(totalAssetsText)
                        .font(.title.bold().monospacedDigit())
                        .foregroundStyle(BitternTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Text(performanceText)
                        .font(.headline.bold().monospacedDigit())
                        .foregroundStyle(BitternTheme.performanceColor(performanceAmount))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    if isForScreenshot {
                        PerformanceModeLabel(
                            title: performanceMode.title,
                            foregroundStyle: BitternTheme.ink
                        )
                    } else {
                        Menu {
                            ForEach(PerformanceMode.allCases) { mode in
                                Button {
                                    performanceMode = mode
                                } label: {
                                    Label(mode.title, systemImage: mode.systemImage)
                                }
                            }
                        } label: {
                            PerformanceModeLabel(
                                title: performanceMode.title,
                                foregroundStyle: BitternTheme.ink
                            )
                        }
                    }
                }
                .frame(width: side * 0.58)
                .position(center)

                ForEach(segments) { segment in
                    AllocationBubble(
                        symbol: segment.symbol,
                        percent: segment.percent,
                        color: segment.color,
                        scale: labelScale
                    )
                    .position(
                        x: center.x + cos(segment.midAngle.radians) * labelRadius,
                        y: center.y + sin(segment.midAngle.radians) * labelRadius
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var performanceText: String {
        guard let performanceAmount, let performancePercent else { return "N/A" }

        if isPrivacyEnabled {
            let sign = performanceAmount < 0 ? "-" : performanceAmount > 0 ? "+" : ""
            return "\(sign)\(hiddenMoney(currencyCode: snapshot.currencyCode))"
        }

        return PortfolioFormat.change(performanceAmount, percent: performancePercent, currencyCode: snapshot.currencyCode)
    }

    private var totalAssetsText: String {
        if isPrivacyEnabled {
            return snapshot.totalAssets == nil ? "N/A" : hiddenMoney(currencyCode: snapshot.currencyCode)
        }

        guard let totalAssets = snapshot.totalAssets else { return "N/A" }
        return PortfolioFormat.wholeMoney(totalAssets, currencyCode: snapshot.currencyCode)
    }
}

// MARK: - Holdings Section

private struct HoldingsSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    let isPrivacyEnabled: Bool
    let minPriceThreshold: Double

    private var filteredHoldings: [PortfolioHolding] {
        viewModel.sortedHoldings.filter { $0.marketValue.map { $0 >= minPriceThreshold } ?? true }
    }

    private var accountProviderLookup: [String: String] {
        Dictionary(uniqueKeysWithValues: viewModel.visibleSnapshot.accounts.map { ($0.id, $0.providerName) })
    }

    private var holdingColorLookup: [String: Color] {
        makeHoldingColorLookup(from: viewModel.visibleSnapshot.holdings.filter { $0.marketValue.map { $0 >= minPriceThreshold } ?? false })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 8)

            if filteredHoldings.isEmpty {
                EmptyHoldingsView()
                    .padding(.top, 24)
            } else {
                HoldingsList(
                    filteredHoldings: filteredHoldings,
                    visibleSnapshot: viewModel.visibleSnapshot,
                    performanceMode: viewModel.performanceMode,
                    isPrivacyEnabled: isPrivacyEnabled,
                    accountProviderLookup: accountProviderLookup,
                    holdingColorLookup: holdingColorLookup
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                holdingsTitle
                updatedLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            sortMenu
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, 3)
        }
    }

    private var holdingsTitle: some View {
        Text("Holdings")
            .font(.title2.bold())
            .foregroundStyle(BitternTheme.ink)
    }

    private var updatedLabel: some View {
        Text("Updated \(PortfolioFormat.timeWithSeconds(viewModel.visibleSnapshot.lastUpdated))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(BitternTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sortMenu: some View {
        HoldingsSortMenu(
            performanceMode: $viewModel.performanceMode,
            sortOption: $viewModel.sortOption
        )
    }
}

private struct HoldingsList: View {
    let filteredHoldings: [PortfolioHolding]
    let visibleSnapshot: PortfolioSnapshot
    let performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let accountProviderLookup: [String: String]
    let holdingColorLookup: [String: Color]
    @Environment(\.isRenderingScreenshot) private var isForScreenshot

    var body: some View {
        if isForScreenshot {
            VStack(spacing: 0) {
                ForEach(Array(filteredHoldings.enumerated()), id: \.element.id) { index, holding in
                    HoldingListRow(
                        holding: holding,
                        totalMarketValue: visibleSnapshot.totalMarketValue,
                        performanceMode: performanceMode,
                        isPrivacyEnabled: isPrivacyEnabled,
                        providerName: accountProviderLookup[holding.accountID] ?? "",
                        color: holdingColorLookup[holding.id] ?? fallbackAllocationColor,
                        showsDivider: index < filteredHoldings.count - 1
                    )
                }
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredHoldings.enumerated()), id: \.element.id) { index, holding in
                    NavigationLink(value: holding) {
                        HoldingListRow(
                            holding: holding,
                            totalMarketValue: visibleSnapshot.totalMarketValue,
                            performanceMode: performanceMode,
                            isPrivacyEnabled: isPrivacyEnabled,
                            providerName: accountProviderLookup[holding.accountID] ?? "",
                            color: holdingColorLookup[holding.id] ?? fallbackAllocationColor,
                            showsDivider: index < filteredHoldings.count - 1
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct HoldingsSortMenu: View {
    @Binding var performanceMode: PerformanceMode
    @Binding var sortOption: HoldingSortOption
    @Environment(\.isRenderingScreenshot) private var isForScreenshot

    var body: some View {
        if isForScreenshot {
            HoldingsSortLabel(title: headerTitle)
        } else {
            Menu {
                Section("Return") {
                    ForEach(PerformanceMode.allCases) { mode in
                        Button {
                            performanceMode = mode
                        } label: {
                            Label(mode.title, systemImage: mode.systemImage)
                        }
                    }
                }

                Section("Sort") {
                    ForEach(HoldingSortOption.allCases) { option in
                        Button {
                            sortOption = option
                        } label: {
                            Label(option.title, systemImage: option.systemImage)
                        }
                    }
                }
            } label: {
                HoldingsSortLabel(title: headerTitle)
            }
            .accessibilityLabel("Holding return and sort options")
        }
    }

    private var headerTitle: String {
        if sortOption == .marketValue {
            return "Market value"
        }

        let prefix: String
        switch performanceMode {
        case .today:
            prefix = "Today's"
        case .allTime:
            prefix = "All-time"
        }

        switch sortOption {
        case .gainAmount:
            return "\(prefix) gain"
        case .lossAmount:
            return "\(prefix) loss"
        case .percent:
            return "\(prefix) return (%)"
        case .marketValue:
            return "Market value"
        }
    }
}

// MARK: - Shared Subviews

private struct AccountTabLabel: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.title3.weight(isSelected ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.bold())
            }
        }
        .foregroundStyle(isSelected ? BitternTheme.ink : BitternTheme.secondaryInk)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(BitternTheme.blue)
                    .frame(height: 2)
                    .offset(y: 1)
            }
        }
    }
}

private struct AccountTabButton: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.title3.weight(isSelected ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.bold())
                }
            }
            .foregroundStyle(isSelected ? BitternTheme.ink : BitternTheme.secondaryInk)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(BitternTheme.blue)
                        .frame(height: 2)
                        .offset(y: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DonutSegmentInfo: Identifiable {
    let id: String
    let symbol: String
    let value: Double
    let total: Double
    let startAngle: Double
    let endAngle: Double
    let color: Color

    var percent: Double {
        total == 0 ? 0 : value / total
    }

    var midAngle: Double {
        (startAngle + endAngle) / 2
    }
}

private struct PerformanceModeLabel: View {
    let title: String
    let foregroundStyle: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(foregroundStyle)
    }
}

private struct DonutSegmentShape: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        return path
    }
}

private struct AllocationBubble: View {
    let symbol: String
    let percent: Double
    let color: Color
    let scale: CGFloat

    private var circleSize: CGFloat { 24 * scale }

    private var isOther: Bool { symbol == "OTHER" }

    var body: some View {
        HStack(spacing: 5 * scale) {
            symbolIcon

            Text(PortfolioFormat.percent(percent, fractionDigits: 0))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(BitternTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.leading, 4 * scale)
        .padding(.trailing, 7 * scale)
        .frame(height: 34 * scale)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(symbol), \(PortfolioFormat.percent(percent, fractionDigits: 0))")
    }

    @ViewBuilder
    private var symbolIcon: some View {
        if isOther {
            Text("⋯")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: circleSize, height: circleSize)
                .background(color)
                .clipShape(Circle())
        } else {
            HoldingSymbolIcon(
                symbol: symbol,
                color: color,
                size: circleSize
            )
        }
    }
}

private struct HoldingsSortLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(BitternTheme.secondaryInk)
    }
}

private struct HoldingListRow: View {
    let holding: PortfolioHolding
    let totalMarketValue: Double?
    let performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let providerName: String
    let color: Color
    let showsDivider: Bool

    private var unitLabel: String {
        providerName.lowercased().contains("binance") ? "tokens" : "shares"
    }

    private var formattedQuantity: String {
        unitLabel == "tokens"
            ? PortfolioFormat.tokens(holding.quantity)
            : PortfolioFormat.shares(holding.quantity)
    }

    private var allocation: Double? {
        guard let marketValue = holding.marketValue,
              let totalMarketValue,
              totalMarketValue > 0
        else {
            return nil
        }

        return marketValue / totalMarketValue
    }

    private var performanceAmount: Double? {
        holding.performanceAmount(for: performanceMode)
    }

    private var performancePercent: Double? {
        holding.performancePercent(for: performanceMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SymbolAvatar(symbol: holding.symbol, color: color)

                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(holding.symbol)
                            .font(.headline)
                            .foregroundStyle(BitternTheme.ink)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Spacer(minLength: 8)

                        Text(marketValueText)
                            .font(.headline.bold().monospacedDigit())
                            .foregroundStyle(BitternTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .layoutPriority(1)
                    }

                    secondaryMetrics
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            if showsDivider {
                Divider()
                    .overlay(BitternTheme.softLine.opacity(0.7))
            }
        }
    }

    private var secondaryMetrics: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(isPrivacyEnabled ? allocationText : "\(formattedQuantity) \(unitLabel) | \(allocationText)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(BitternTheme.secondaryInk)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            performanceLabel
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var performanceLabel: some View {
        Text(performanceText)
            .font(.footnote.bold().monospacedDigit())
            .foregroundStyle(BitternTheme.performanceColor(performanceAmount))
            .lineLimit(1)
    }

    private var performanceText: String {
        guard let performanceAmount, let performancePercent else { return "N/A" }

        if isPrivacyEnabled {
            let sign = performanceAmount < 0 ? "-" : performanceAmount > 0 ? "+" : ""
            return "\(sign)\(hiddenMoney(currencyCode: holding.currencyCode))"
        }

        return "\(PortfolioFormat.money(performanceAmount, currencyCode: holding.currencyCode, signed: true)) (\(PortfolioFormat.percent(performancePercent, signed: true)))"
    }

    private var marketValueText: String {
        if isPrivacyEnabled {
            return holding.marketValue == nil ? "N/A" : hiddenMoney(currencyCode: holding.currencyCode)
        }

        guard let marketValue = holding.marketValue else { return "N/A" }
        return PortfolioFormat.wholeMoney(marketValue, currencyCode: holding.currencyCode)
    }

    private var allocationText: String {
        guard let allocation else { return "N/A" }
        return PortfolioFormat.percent(allocation)
    }
}

private struct SymbolAvatar: View {
    let symbol: String
    let color: Color

    var body: some View {
        HoldingSymbolIcon(symbol: symbol, color: color, size: 40)
    }
}

private struct HoldingSymbolIcon: View {
    let symbol: String
    let color: Color
    let size: CGFloat
    var borderColor: Color? = nil
    var borderWidth: CGFloat = 0

    private var label: String {
        let prefix = String(symbol.prefix(4))
        return prefix.isEmpty ? "?" : prefix
    }

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(Circle())
            .overlay {
                if let borderColor, borderWidth > 0 {
                    Circle().stroke(borderColor, lineWidth: borderWidth)
                }
            }
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BitternTheme.loss)

            Text(message)
                .font(.footnote)
                .foregroundStyle(BitternTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(BitternTheme.loss.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EmptyHoldingsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(BitternTheme.secondaryInk)

            Text("No holdings")
                .font(.headline)
                .foregroundStyle(BitternTheme.ink)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
        .background(BitternTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Helpers

private func makeSegments(from holdings: [PortfolioHolding]) -> [DonutSegmentInfo] {
    let sortedHoldings = sortedAllocationHoldings(from: holdings)

    let total = sortedHoldings.reduce(0) { $0 + ($1.marketValue ?? 0) }
    guard total > 0 else { return [] }

    let minAllocation = total * 0.04 // 小于 4% 的 Holdings 进入 Others
    let visibleHoldings = sortedHoldings.filter {
        ($0.marketValue ?? 0) >= minAllocation
    }
    let visibleIDs = Set(visibleHoldings.map(\.id))
    let otherValue = sortedHoldings
        .filter { !visibleIDs.contains($0.id) }
        .reduce(0) { $0 + ($1.marketValue ?? 0) }

    var segments: [(symbol: String, value: Double, id: String)] = visibleHoldings.map {
        ($0.symbol, $0.marketValue ?? 0, $0.id)
    }
    if otherValue > 0 {
        segments.append(("OTHER", otherValue, "other"))
    }

    guard !segments.isEmpty else { return [] }

    var cursor = -90.0
    let gap = 2.2
    let shrink = gap / 2 * Double(segments.count - 1) / Double(segments.count)

    return segments.enumerated().map { index, item in
        let span = item.value / total * 360
        let startAngle = cursor + min(shrink, span * 0.18)
        let endAngle = cursor + span - min(shrink, span * 0.18)
        let segment = DonutSegmentInfo(
            id: item.id,
            symbol: item.symbol,
            value: item.value,
            total: total,
            startAngle: startAngle,
            endAngle: max(startAngle, endAngle),
            color: allocationColor(at: index)
        )
        cursor += span
        return segment
    }
}

private func makeHoldingColorLookup(from holdings: [PortfolioHolding]) -> [String: Color] {
    Dictionary(
        uniqueKeysWithValues: sortedAllocationHoldings(from: holdings).enumerated().map { index, holding in
            (holding.id, allocationColor(at: index))
        }
    )
}

private func sortedAllocationHoldings(from holdings: [PortfolioHolding]) -> [PortfolioHolding] {
    holdings
        .filter { ($0.marketValue ?? 0) > 0 }
        .sorted { lhs, rhs in
            if lhs.marketValue != rhs.marketValue {
                return (lhs.marketValue ?? 0) > (rhs.marketValue ?? 0)
            }

            if lhs.symbol != rhs.symbol {
                return lhs.symbol < rhs.symbol
            }

            return lhs.id < rhs.id
        }
}

private func allocationColor(at index: Int) -> Color {
    BitternTheme.allocationColors[index % BitternTheme.allocationColors.count]
}

private var fallbackAllocationColor: Color {
    BitternTheme.allocationColors.first ?? BitternTheme.blue
}

private func hiddenMoney(currencyCode: String) -> String {
    currencyCode == "USD" ? "$••••" : "\(currencyCode) ••••"
}

private extension Double {
    var radians: Double {
        self * .pi / 180
    }
}

private extension PerformanceMode {
    var systemImage: String {
        switch self {
        case .today:
            "sun.max"
        case .allTime:
            "clock.arrow.circlepath"
        }
    }
}

#if DEBUG
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            preview(width: 393, height: 852, name: "Phone Portrait")
            preview(width: 852, height: 393, name: "Phone Landscape")
            preview(width: 600, height: 500, name: "Compact Window")
            preview(width: 1_024, height: 768, name: "iPad Landscape")
            preview(width: 1_200, height: 700, name: "Wide Window")
        }
    }

    @MainActor
    private static func preview(width: CGFloat, height: CGFloat, name: String) -> some View {
        let store = CredentialsStore()
        let viewModel = DashboardViewModel(
            credentialsStore: store,
            initialSnapshot: DemoPortfolio.snapshot
        )

        return DashboardView(viewModel: viewModel, credentialsStore: store)
            .previewLayout(.fixed(width: width, height: height))
            .previewDisplayName(name)
    }
}
#endif
