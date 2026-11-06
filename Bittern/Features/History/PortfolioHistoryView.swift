//
//  PortfolioHistoryView.swift
//  Bittern
//

import SwiftUI

struct PortfolioHistoryView: View {
    let credentialsStore: CredentialsStore
    let dashboardViewModel: DashboardViewModel
    @State private var model = PortfolioHistoryModel()
    @Environment(\.portfolioRepository) private var repository
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PortfolioHistoryHeader(
                    series: model.visibleSeries,
                    fallbackPoint: model.history?.points.last,
                    selectedPoint: model.selectedPoint,
                    range: model.selectedRange,
                    currencyCode: model.history?.currencyCode ?? "",
                    isPrivacyEnabled: isPrivacyEnabled
                )

                PortfolioHistoryChartSection(
                    series: model.visibleSeries,
                    currencyCode: model.history?.currencyCode ?? "",
                    isPrivacyEnabled: isPrivacyEnabled,
                    range: $model.selectedRange,
                    selectedPoint: $model.selectedPoint,
                    isLoading: model.isLoading
                )
                .frame(maxWidth: Self.maximumChartWidth)
            }
            .frame(maxWidth: Self.maximumContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
        }
        .background(BitternTheme.background.ignoresSafeArea())
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .softNavigationBarEdge()
        .errorToast(message: $model.errorMessage)
        .refreshable {
            await load()
        }
        // Loads on appear and again whenever the credentials change.
        .task(id: credentialsStore.credentials) {
            await load()
        }
        .onChange(of: model.selectedRange) { _, _ in
            model.selectedPoint = nil
        }
    }

    private func load() async {
        await model.load(
            credentials: credentialsStore.credentials,
            accountIDs: dashboardViewModel.snapshot?.accounts.map(\.id) ?? [],
            using: repository
        )
    }

    private static let maximumContentWidth: CGFloat = 900
    private static let maximumChartWidth: CGFloat = 760
}

private struct PortfolioHistoryHeader: View {
    let series: [PortfolioHistoryPoint]
    let fallbackPoint: PortfolioHistoryPoint?
    let selectedPoint: PortfolioHistoryPoint?
    let range: PortfolioHistoryRange
    let currencyCode: String
    let isPrivacyEnabled: Bool

    private var displayPoint: PortfolioHistoryPoint? {
        selectedPoint ?? series.last ?? fallbackPoint
    }

    private var baseValue: Double? {
        series.first?.totalValue
    }

    private var valueDelta: Double? {
        guard let displayPoint, let baseValue else { return nil }
        return displayPoint.totalValue - baseValue
    }

    private var valueDeltaPercent: Double? {
        guard let baseValue, baseValue != 0, let valueDelta else { return nil }
        return valueDelta / abs(baseValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Portfolio Value")
                .font(.title.bold())
                .foregroundStyle(BitternTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(totalValueText)
                    .font(.largeTitle.bold().monospacedDigit())
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)

                Text(currencyCode)
                    .font(.title3.bold())
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)
            }

            HStack(spacing: 9) {
                Text(changeAmountText)
                    .font(.headline.bold().monospacedDigit())
                    .foregroundStyle(BitternTheme.performanceColor(valueDelta))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(changePercentText)
                    .font(.headline.bold().monospacedDigit())
                    .foregroundStyle(BitternTheme.performanceColor(valueDelta))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(BitternTheme.performanceColor(valueDelta).opacity(0.18))
                    .clipShape(Capsule())

                Text("· \(dateText)")
                    .font(.headline.bold())
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalValueText: String {
        guard let displayPoint else { return "N/A" }

        return isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: currencyCode)
            : PortfolioFormat.wholeMoney(displayPoint.totalValue, currencyCode: currencyCode)
    }

    private var changeAmountText: String {
        guard let valueDelta else { return "N/A" }

        if isPrivacyEnabled {
            let sign = valueDelta < 0 ? "-" : valueDelta > 0 ? "+" : ""
            return "\(sign)\(PortfolioFormat.hiddenMoney(currencyCode: currencyCode))"
        }

        return PortfolioFormat.wholeMoney(valueDelta, currencyCode: currencyCode, signed: true)
    }

    private var changePercentText: String {
        guard let valueDeltaPercent else { return "N/A" }
        return PortfolioFormat.percent(valueDeltaPercent, signed: true)
    }

    private var dateText: String {
        guard let displayPoint else { return range.title }
        return selectedPoint == nil
            ? range.title
            : portfolioHistorySelectionDateFormatter.string(from: displayPoint.date)
    }
}

private struct PortfolioHistoryChartSection: View {
    let series: [PortfolioHistoryPoint]
    let currencyCode: String
    let isPrivacyEnabled: Bool
    @Binding var range: PortfolioHistoryRange
    @Binding var selectedPoint: PortfolioHistoryPoint?
    let isLoading: Bool

    var body: some View {
        let baseValue = series.first?.totalValue

        PerformanceLineChartSection(
            points: series,
            value: { $0.totalValue },
            xScale: .indexed,
            baseValue: baseValue,
            baselineLabel: baseValue.map {
                isPrivacyEnabled
                    ? PortfolioFormat.hiddenMoney(currencyCode: currencyCode)
                    : PortfolioFormat.wholeMoney($0, currencyCode: currencyCode)
            },
            primaryLineValue: series.last?.totalValue,
            lineStyle: { _ in .primary },
            ranges: PortfolioHistoryRange.allCases,
            rangeTitle: { $0.title },
            selectedRange: $range,
            selectedPoint: $selectedPoint,
            isLoading: isLoading
        )
    }
}

private let portfolioHistorySelectionDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "d MMM, yyyy"
    return formatter
}()

#if DEBUG
#Preview {
    let credentialsStore = PreviewSupport.credentialsStore()
    NavigationStack {
        PortfolioHistoryView(
            credentialsStore: credentialsStore,
            dashboardViewModel: PreviewSupport.dashboardViewModel(credentialsStore: credentialsStore)
        )
    }
}
#endif
