//
//  DashboardView.swift
//  Bittern
//

import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var credentialsStore: CredentialsStore
    @State private var isShowingSettings = false
    @State private var isShowingPortfolioAccounts = false
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false
    @AppStorage(AppSettingKey.minPriceThreshold) private var minPriceThreshold = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                BitternTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    PortfolioTopBar(
                        openSettings: { isShowingSettings = true },
                        openPortfolioAccounts: { isShowingPortfolioAccounts = true }
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                    .background(BitternTheme.background)

                    ScrollView {
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
                        .padding(.horizontal, 24)
                        .padding(.bottom, 34)
                    }
                    .refreshable {
                        // Use a detached task so that URLSession calls (especially
                        // the Yahoo Finance quote fetch) are not cancelled when
                        // SwiftUI's .refreshable decides to cancel its own task.
                        _ = await Task.detached {
                            await viewModel.refresh()
                        }.value
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .navigationDestination(isPresented: $isShowingPortfolioAccounts) {
                PortfolioAccountsView(credentialsStore: credentialsStore, viewModel: viewModel)
            }
        }
    }
}

private struct PortfolioTopBar: View {
    let openSettings: () -> Void
    let openPortfolioAccounts: () -> Void

    var body: some View {
        ZStack {
            HStack {
                Button(action: openSettings) {
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
                .buttonStyle(.plain)
                .accessibilityLabel("SnapTrade settings")

                Spacer()

                Button(action: openPortfolioAccounts) {
                    Image(systemName: "building.columns")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(BitternTheme.secondaryInk)
                }
                .accessibilityLabel("Edit portfolio accounts")
            }

            Text("Portfolio")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(BitternTheme.ink)
        }
    }
}

private struct AccountFilterBar: View {
    let accounts: [PortfolioAccount]
    @Binding var selectedProviderName: String?
    @Binding var isPrivacyEnabled: Bool

    private var providerNames: [String] {
        accounts.reduce(into: []) { result, account in
            let name = account.providerName
            if !result.contains(name) {
                result.append(name)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
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

                Menu {
                    Button {
                        selectedProviderName = nil
                    } label: {
                        Label("All", systemImage: selectedProviderName == nil ? "checkmark" : "tray.full")
                    }

                    ForEach(providerNames, id: \.self) { providerName in
                        Button {
                            selectedProviderName = providerName
                        } label: {
                            Label(
                                providerName,
                                systemImage: selectedProviderName == providerName ? "checkmark" : "building.columns"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(BitternTheme.secondaryInk)
                        .frame(width: 30, height: 38)
                }
                .accessibilityLabel("Filter provider")

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

            Divider()
                .frame(height: 1)
                .overlay(BitternTheme.softLine)
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
            .frame(minHeight: 300)
            .padding(.vertical, 22)
        }
    }
}

private struct DonutPortfolioChart: View {
    let snapshot: PortfolioSnapshot
    @Binding var performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let minPriceThreshold: Double

    private var filteredHoldings: [PortfolioHolding] {
        snapshot.holdings.filter { $0.marketValue >= minPriceThreshold }
    }

    private var performanceAmount: Double {
        snapshot.performanceAmount(for: performanceMode)
    }

    private var performancePercent: Double {
        snapshot.performancePercent(for: performanceMode)
    }

    private var segments: [DonutSegmentInfo] {
        makeSegments(from: filteredHoldings)
    }

    var body: some View {
        GeometryReader { proxy in
            let totalStr = isPrivacyEnabled
                ? hiddenMoney(currencyCode: snapshot.currencyCode)
                : PortfolioFormat.wholeMoney(snapshot.totalAssets, currencyCode: snapshot.currencyCode)
            let charCount = CGFloat(max(totalStr.count, 4))
            let side = min(charCount * 15 + 140, proxy.size.width - 64)
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

                    Menu {
                        ForEach(PerformanceMode.allCases) { mode in
                            Button {
                                performanceMode = mode
                            } label: {
                                Label(mode.title, systemImage: mode.systemImage)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(performanceMode.title)
                                .font(.system(size: 16, weight: .bold, design: .rounded))

                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(BitternTheme.ink)
                    }
                }
                .frame(width: side * 0.58)
                .position(center)

                ForEach(segments.prefix(5)) { segment in
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
            return "\(performanceAmount < 0 ? "-" : performanceAmount > 0 ? "+" : "")\(hiddenMoney(currencyCode: snapshot.currencyCode))"
        }

        return PortfolioFormat.change(performanceAmount, percent: performancePercent, currencyCode: snapshot.currencyCode)
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

    private var symbolFontSize: CGFloat {
        let chars = CGFloat(min(symbol.count, 4))
        // Adaptive: longer symbols get proportionally smaller font
        // 3 chars → ~9pt, 4 chars → ~7pt
        let base = circleSize / chars * 1.15
        return min(10, max(6, base))
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(String(symbol.prefix(4)))
                .font(.system(size: symbolFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: circleSize, height: circleSize)
                .background(color)
                .clipShape(Circle())
                .overlay(Circle().stroke(BitternTheme.ink.opacity(0.85), lineWidth: 1))

            Text(PortfolioFormat.percent(percent))
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
            .padding(.bottom, 14)

            Divider()
                .frame(height: 1)
                .overlay(BitternTheme.softLine)

            if filteredHoldings.isEmpty {
                EmptyHoldingsView()
                    .padding(.top, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredHoldings) { holding in
                        HoldingListRow(
                            holding: holding,
                            totalMarketValue: viewModel.visibleSnapshot.totalMarketValue,
                            performanceMode: viewModel.performanceMode,
                            isPrivacyEnabled: isPrivacyEnabled,
                            providerName: accountProviderLookup[holding.accountID] ?? ""
                        )
                    }
                }
            }
        }
    }
}

private struct HoldingsSortMenu: View {
    @Binding var performanceMode: PerformanceMode
    @Binding var sortOption: HoldingSortOption

    var body: some View {
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
            HStack(spacing: 8) {
                Text(headerTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(BitternTheme.secondaryInk)
        }
        .accessibilityLabel("Holding return and sort options")
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

private struct HoldingListRow: View {
    let holding: PortfolioHolding
    let totalMarketValue: Double
    let performanceMode: PerformanceMode
    let isPrivacyEnabled: Bool
    let providerName: String

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

    private var performanceAmount: Double {
        holding.performanceAmount(for: performanceMode)
    }

    private var performancePercent: Double {
        holding.performancePercent(for: performanceMode)
    }

    var body: some View {
        HStack(spacing: 14) {
            SymbolAvatar(symbol: holding.symbol)

            VStack(alignment: .leading, spacing: 6) {
                Text(holding.symbol)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)

                Text(isPrivacyEnabled ? PortfolioFormat.percent(allocation) : "\(formattedQuantity) \(unitLabel) | \(PortfolioFormat.percent(allocation))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 10)

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
                    .minimumScaleFactor(0.58)
            }
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            Divider()
                .frame(height: 1)
                .overlay(BitternTheme.softLine)
        }
    }

    private var performanceText: String {
        if isPrivacyEnabled {
            return "\(performanceAmount < 0 ? "-" : performanceAmount > 0 ? "+" : "")\(hiddenMoney(currencyCode: holding.currencyCode))"
        }

        return "\(PortfolioFormat.money(performanceAmount, currencyCode: holding.currencyCode, signed: true)) (\(PortfolioFormat.percent(performancePercent, signed: true)))"
    }
}

private struct SymbolAvatar: View {
    let symbol: String

    var body: some View {
        Text(String(symbol.prefix(4)))
            .font(.system(size: symbol.count > 3 ? 11 : 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(avatarColor)
            .clipShape(Circle())
    }

    private var avatarColor: Color {
        let palette = BitternTheme.allocationColors
        let sum = symbol.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
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

private func makeSegments(from holdings: [PortfolioHolding]) -> [DonutSegmentInfo] {
    let sortedHoldings = holdings
        .filter { $0.marketValue > 0 }
        .sorted { $0.marketValue > $1.marketValue }

    let visibleHoldings = sortedHoldings.prefix(5)
    let total = sortedHoldings.reduce(0) { $0 + $1.marketValue }
    guard total > 0 else { return [] }

    var cursor = -90.0
    let gap = 2.2

    return visibleHoldings.enumerated().map { index, holding in
        let span = holding.marketValue / total * 360
        let startAngle = cursor + min(gap / 2, span * 0.18)
        let endAngle = cursor + span - min(gap / 2, span * 0.18)
        let segment = DonutSegmentInfo(
            id: holding.id,
            symbol: holding.symbol,
            value: holding.marketValue,
            total: total,
            startAngle: startAngle,
            endAngle: max(startAngle, endAngle),
            color: BitternTheme.allocationColors[index % BitternTheme.allocationColors.count]
        )
        cursor += span
        return segment
    }
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
