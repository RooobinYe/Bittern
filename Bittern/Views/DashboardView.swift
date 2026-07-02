//
//  DashboardView.swift
//  Bittern
//

import SwiftUI
import UIKit

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var credentialsStore: CredentialsStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingSettings = false
    @State private var isShowingShareSheet = false
    @State private var shareImage: UIImage?
    @State private var isGeneratingScreenshot = false
    @State private var showScreenshotError = false
    @State private var screenshotErrorMessage = ""
    @State private var screenshotTask: Task<Void, Never>?
#if DEBUG
    @State private var didRunDebugScreenshotExport = false
#endif
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false
    @AppStorage(AppSettingKey.minPriceThreshold) private var minPriceThreshold = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                BitternTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    PortfolioTopBar(
                        openSettings: { isShowingSettings = true },
                        openShare: {
                            screenshotTask = Task {
                                await generateAndShareScreenshot()
                            }
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                    .background(BitternTheme.background)

                    ScrollView {
                        DashboardContent(
                            viewModel: viewModel,
                            isPrivacyEnabled: $isPrivacyEnabled,
                            minPriceThreshold: minPriceThreshold
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 34)
                    }
                    .refreshable { await viewModel.refresh() }
                }

                // Screenshot generation progress overlay
                if isGeneratingScreenshot {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.4)
                            .tint(.white)

                        Text("Generating screenshot…")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Button {
                            screenshotTask?.cancel()
                            isGeneratingScreenshot = false
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(.white.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .transition(.opacity)
                    }
                    .padding(28)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.scale.combined(with: .opacity))
                }

                // Screenshot error toast
                if showScreenshotError {
                    VStack {
                        Spacer()
                        Text(screenshotErrorMessage)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isGeneratingScreenshot)
            .animation(.easeInOut(duration: 0.22), value: showScreenshotError)
            .toolbar(.hidden, for: .navigationBar)
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
            .sheet(isPresented: $isShowingShareSheet, onDismiss: {
                shareImage = nil
            }) {
                if let shareImage {
                    ShareSheet(items: [shareImage], colorScheme: colorScheme)
                }
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

    // MARK: - Screenshot

    @MainActor
    private func generateAndShareScreenshot() async {
        guard !isGeneratingScreenshot else { return }
        isGeneratingScreenshot = true
        defer { isGeneratingScreenshot = false }

        let screenshotWidth = UIScreen.main.bounds.width
        let screenshotColorScheme = colorScheme

        // Build screenshot content with the privacy value frozen at capture time.
        let privacyBinding = Binding<Bool>(
            get: { isPrivacyEnabled },
            set: { _ in }
        )

        let content = PortfolioShareScreenshotContent(
            viewModel: viewModel,
            isPrivacyEnabled: privacyBinding,
            minPriceThreshold: minPriceThreshold,
            width: screenshotWidth
        )
        .environment(\.colorScheme, screenshotColorScheme)
        .environment(\.isRenderingScreenshot, true)

        // Race the synchronous render against a 15-second timeout.
        // withTaskGroup ensures the continuation is resumed exactly once —
        // whichever task finishes first, the other is cancelled.
        let image: UIImage? = await withTaskGroup(of: UIImage?.self) { group in
            group.addTask { @MainActor in
                ScreenshotRenderer.render(
                    content,
                    width: screenshotWidth,
                    scale: UIScreen.main.scale,
                    backgroundColor: screenshotColorScheme.systemBackgroundColor
                )
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(15))
                return nil
            }

            let result = await group.next()!
            group.cancelAll()
            return result
        }

        guard !Task.isCancelled else { return }

        guard let image else {
            showError("Screenshot timed out")
            return
        }

        shareImage = image
        isShowingShareSheet = true
    }

    @MainActor
    private func showError(_ message: String) {
        screenshotErrorMessage = message
        showScreenshotError = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showScreenshotError = false
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

        let screenshotWidth = UIScreen.main.bounds.width
        let screenshotColorScheme = colorScheme

        guard let image = ScreenshotRenderer.render(
                  PortfolioShareScreenshotContent(
                      viewModel: viewModel,
                      isPrivacyEnabled: .constant(false),
                      minPriceThreshold: 0,
                      width: screenshotWidth
                  )
                  .environment(\.colorScheme, screenshotColorScheme)
                  .environment(\.isRenderingScreenshot, true),
                  width: screenshotWidth,
                  scale: UIScreen.main.scale,
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

// MARK: - Top Bar

private struct PortfolioTopBar: View {
    let openSettings: () -> Void
    let openShare: () -> Void
    @Environment(\.isRenderingScreenshot) private var isForScreenshot

    var body: some View {
        ZStack {
            HStack {
                if isForScreenshot {
                    settingsIcon
                } else {
                    Button(action: openSettings) {
                        settingsIcon
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("SnapTrade settings")
                }

                Spacer()

                if isForScreenshot {
                    shareIcon
                } else {
                    Button(action: openShare) {
                        shareIcon
                    }
                    .accessibilityLabel("Share portfolio")
                }
            }

            Text("Portfolio")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(BitternTheme.ink)
        }
    }

    private var settingsIcon: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 42, height: 42)

            Image(systemName: "leaf.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(BitternTheme.blue)
                .offset(x: -1, y: -1)
        }
    }

    private var shareIcon: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(BitternTheme.secondaryInk)
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
            PortfolioTopBar(openSettings: {}, openShare: {})
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .background(BitternTheme.background)

            DashboardContent(
                viewModel: viewModel,
                isPrivacyEnabled: $isPrivacyEnabled,
                minPriceThreshold: minPriceThreshold
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
        }
        .frame(width: width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(BitternTheme.background)
    }
}

// MARK: - Dashboard Content

private struct DashboardContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPrivacyEnabled: Bool
    let minPriceThreshold: Double

    var body: some View {
        VStack(spacing: 24) {
            AccountFilterBar(
                accounts: viewModel.snapshot.accounts,
                selectedProviderName: $viewModel.selectedProviderName,
                isPrivacyEnabled: $isPrivacyEnabled
            )

            PortfolioDonutSection(
                snapshot: viewModel.visibleSnapshot,
                performanceMode: $viewModel.performanceMode,
                isPrivacyEnabled: isPrivacyEnabled,
                minPriceThreshold: minPriceThreshold
            )

            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            HoldingsSection(
                viewModel: viewModel,
                isPrivacyEnabled: isPrivacyEnabled,
                minPriceThreshold: minPriceThreshold
            )
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(BitternTheme.secondaryInk)
                        .frame(width: 30, height: 38)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isPrivacyEnabled.toggle()
                        }
                    } label: {
                        Image(systemName: isPrivacyEnabled ? "eye.slash" : "eye")
                            .font(.system(size: 18, weight: .semibold))
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

    var body: some View {
        VStack(spacing: 0) {
            DonutPortfolioChart(
                snapshot: snapshot,
                performanceMode: $performanceMode,
                isPrivacyEnabled: isPrivacyEnabled,
                minPriceThreshold: minPriceThreshold
            )
            .frame(height: 300)
            .padding(.vertical, 22)
        }
    }
}

private struct DonutPortfolioChart: View {
    let snapshot: PortfolioSnapshot
    @Binding var performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let minPriceThreshold: Double
    @Environment(\.isRenderingScreenshot) private var isForScreenshot

    private var filteredHoldings: [PortfolioHolding] {
        snapshot.holdings.filter { $0.marketValue >= minPriceThreshold }
    }

    private var performanceAmount: Double? {
        snapshot.performanceAmount(for: performanceMode)
    }

    private var performancePercent: Double? {
        snapshot.performancePercent(for: performanceMode)
    }

    private var segments: [DonutSegmentInfo] {
        makeSegments(from: filteredHoldings)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width * 0.7, proxy.size.width - 80)
            let center = CGPoint(x: proxy.size.width / 2, y: side / 2 + 20)
            let labelRadius = side * 0.64

            ZStack {
                Circle()
                    .stroke(BitternTheme.surface, lineWidth: side * 0.17)
                    .frame(width: side, height: side)
                    .position(center)

                ForEach(segments) { segment in
                    DonutSegmentShape(
                        startAngle: .degrees(segment.startAngle),
                        endAngle: .degrees(segment.endAngle)
                    )
                    .stroke(segment.color, style: StrokeStyle(lineWidth: side * 0.17, lineCap: .butt))
                    .frame(width: side, height: side)
                    .position(center)
                }

                VStack(spacing: 7) {
                    Text(isPrivacyEnabled ? hiddenMoney(currencyCode: snapshot.currencyCode) : PortfolioFormat.wholeMoney(snapshot.totalAssets, currencyCode: snapshot.currencyCode))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Text(performanceText)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.performanceColor(performanceAmount))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    if isForScreenshot {
                        PerformanceModeLabel(title: performanceMode.title, foregroundStyle: BitternTheme.ink)
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
                            PerformanceModeLabel(title: performanceMode.title, foregroundStyle: BitternTheme.ink)
                        }
                    }
                }
                .frame(width: side * 0.58)
                .position(center)

                ForEach(segments) { segment in
                    AllocationBubble(
                        symbol: segment.symbol,
                        percent: segment.percent,
                        color: segment.color
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
        if isPrivacyEnabled {
            let sign = performanceAmount.map { $0 < 0 ? "-" : $0 > 0 ? "+" : "" } ?? ""
            return "\(sign)\(hiddenMoney(currencyCode: snapshot.currencyCode))"
        }

        guard let performanceAmount, let performancePercent else { return "N/A" }
        return PortfolioFormat.change(performanceAmount, percent: performancePercent, currencyCode: snapshot.currencyCode)
    }
}

// MARK: - Holdings Section

private struct HoldingsSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    let isPrivacyEnabled: Bool
    let minPriceThreshold: Double

    private var filteredHoldings: [PortfolioHolding] {
        viewModel.sortedHoldings.filter { $0.marketValue >= minPriceThreshold }
    }

    private var accountProviderLookup: [String: String] {
        Dictionary(uniqueKeysWithValues: viewModel.visibleSnapshot.accounts.map { ($0.id, $0.providerName) })
    }

    private var holdingColorLookup: [String: Color] {
        makeHoldingColorLookup(from: viewModel.visibleSnapshot.holdings.filter { $0.marketValue >= minPriceThreshold })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Holdings")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(BitternTheme.ink)

                Text("Updated \(PortfolioFormat.timeWithSeconds(viewModel.visibleSnapshot.lastUpdated))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(BitternTheme.secondaryInk)

                Spacer()

                HoldingsSortMenu(
                    performanceMode: $viewModel.performanceMode,
                    sortOption: $viewModel.sortOption
                )
            }
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
                ForEach(filteredHoldings) { holding in
                    HoldingListRow(
                        holding: holding,
                        totalMarketValue: visibleSnapshot.totalMarketValue,
                        performanceMode: performanceMode,
                        isPrivacyEnabled: isPrivacyEnabled,
                        providerName: accountProviderLookup[holding.accountID] ?? "",
                        color: holdingColorLookup[holding.id] ?? fallbackAllocationColor
                    )
                }
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(filteredHoldings) { holding in
                    NavigationLink(value: holding) {
                        HoldingListRow(
                            holding: holding,
                            totalMarketValue: visibleSnapshot.totalMarketValue,
                            performanceMode: performanceMode,
                            isPrivacyEnabled: isPrivacyEnabled,
                            providerName: accountProviderLookup[holding.accountID] ?? "",
                            color: holdingColorLookup[holding.id] ?? fallbackAllocationColor
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
                .font(.system(size: 19, weight: isSelected ? .bold : .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
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
                    .font(.system(size: 19, weight: isSelected ? .bold : .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .bold))
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
                .font(.system(size: 16, weight: .bold, design: .rounded))

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
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

    private let circleSize: CGFloat = 24

    private var isOther: Bool { symbol == "OTHER" }

    var body: some View {
        HStack(spacing: 5) {
            if isOther {
                Text("⋯")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: circleSize, height: circleSize)
                    .background(color)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(BitternTheme.ink.opacity(0.85), lineWidth: 1))
            } else {
                HoldingSymbolIcon(
                    symbol: symbol,
                    color: color,
                    size: circleSize,
                    borderColor: BitternTheme.ink.opacity(0.85),
                    borderWidth: 1
                )
            }

            Text(PortfolioFormat.percent(percent, fractionDigits: 0))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(BitternTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.leading, 4)
        .padding(.trailing, 7)
        .frame(height: 34)
        .background(BitternTheme.surface)
        .clipShape(Capsule())
    }
}

private struct HoldingsSortLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(BitternTheme.secondaryInk)
    }
}

private struct HoldingListRow: View {
    let holding: PortfolioHolding
    let totalMarketValue: Double
    let performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let providerName: String
    let color: Color

    private var unitLabel: String {
        providerName.lowercased().contains("binance") ? "tokens" : "shares"
    }

    private var formattedQuantity: String {
        unitLabel == "tokens"
            ? PortfolioFormat.tokens(holding.quantity)
            : PortfolioFormat.shares(holding.quantity)
    }

    private var allocation: Double {
        totalMarketValue == 0 ? 0 : holding.marketValue / totalMarketValue
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

                VStack(alignment: .leading, spacing: 6) {
                    Text(holding.symbol)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.ink)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(isPrivacyEnabled ? PortfolioFormat.percent(allocation) : "\(formattedQuantity) \(unitLabel) | \(PortfolioFormat.percent(allocation))")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(BitternTheme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 7) {
                    Text(isPrivacyEnabled ? hiddenMoney(currencyCode: holding.currencyCode) : PortfolioFormat.wholeMoney(holding.marketValue, currencyCode: holding.currencyCode))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)

                    Text(performanceText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.performanceColor(performanceAmount))
                        .lineLimit(1)
                        .minimumScaleFactor(0.56)
                }
                .frame(width: 118, alignment: .trailing)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            Divider()
                .overlay(BitternTheme.softLine.opacity(0.7))
        }
    }

    private var performanceText: String {
        if isPrivacyEnabled {
            let sign = performanceAmount.map { $0 < 0 ? "-" : $0 > 0 ? "+" : "" } ?? ""
            return "\(sign)\(hiddenMoney(currencyCode: holding.currencyCode))"
        }

        guard let performanceAmount, let performancePercent else { return "N/A" }
        return "\(PortfolioFormat.money(performanceAmount, currencyCode: holding.currencyCode, signed: true)) (\(PortfolioFormat.percent(performancePercent, signed: true)))"
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

    private var symbolFontSize: CGFloat {
        let chars = CGFloat(max(label.count, 1))
        let base = size / chars * 1.15
        return min(size * 0.42, max(size * 0.25, base))
    }

    var body: some View {
        Text(label)
            .font(.system(size: symbolFontSize, weight: .bold, design: .rounded))
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

    let total = sortedHoldings.reduce(0) { $0 + $1.marketValue }
    guard total > 0 else { return [] }

    let minAllocation = total * 0.05
    let visibleHoldings = sortedHoldings.filter { $0.marketValue >= minAllocation }
    let otherValue = sortedHoldings.filter { $0.marketValue < minAllocation }.reduce(0) { $0 + $1.marketValue }

    var segments: [(symbol: String, value: Double, id: String)] = visibleHoldings.map {
        ($0.symbol, $0.marketValue, $0.id)
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
        .filter { $0.marketValue > 0 }
        .sorted { lhs, rhs in
            if lhs.marketValue != rhs.marketValue {
                return lhs.marketValue > rhs.marketValue
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
        let store = CredentialsStore()
        let viewModel = DashboardViewModel(credentialsStore: store)
        DashboardView(viewModel: viewModel, credentialsStore: store)
    }
}
#endif
