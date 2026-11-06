//
//  PortfolioHistoryView.swift
//  Bittern
//

import Combine
import SwiftUI

struct PortfolioHistoryView: View {
    @ObservedObject var credentialsStore: CredentialsStore
    @ObservedObject var dashboardViewModel: DashboardViewModel
    @StateObject private var historyModel = PortfolioHistoryViewModel()
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PortfolioHistoryHeader(
                    series: historyModel.visibleSeries,
                    fallbackPoint: historyModel.latestPoint,
                    selectedPoint: historyModel.selectedPoint,
                    range: historyModel.selectedRange,
                    currencyCode: historyModel.currencyCode,
                    isPrivacyEnabled: isPrivacyEnabled
                )

                PortfolioHistoryChartSection(
                    series: historyModel.visibleSeries,
                    currencyCode: historyModel.currencyCode,
                    isPrivacyEnabled: isPrivacyEnabled,
                    range: $historyModel.selectedRange,
                    selectedPoint: $historyModel.selectedPoint,
                    isLoading: historyModel.isLoading
                )
                .frame(maxWidth: portfolioHistoryMaximumChartWidth)
            }
            .frame(maxWidth: portfolioHistoryMaximumContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
        }
        .background(BitternTheme.background.ignoresSafeArea())
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .errorToast(message: $historyModel.errorMessage)
        .refreshable {
            await historyModel.reload(
                credentials: credentialsStore.credentials,
                snapshot: dashboardViewModel.snapshot
            )
        }
        .task {
            await historyModel.loadIfNeeded(
                credentials: credentialsStore.credentials,
                snapshot: dashboardViewModel.snapshot
            )
        }
        .onChange(of: historyModel.selectedRange) { _, _ in
            historyModel.selectedPoint = nil
        }
    }
}

private let portfolioHistoryMaximumContentWidth: CGFloat = 900
private let portfolioHistoryMaximumChartWidth: CGFloat = 760

@MainActor
private final class PortfolioHistoryViewModel: ObservableObject {
    @Published var selectedRange: PortfolioHistoryRange = .fiveDays
    @Published var selectedPoint: PortfolioHistoryPoint?
    @Published private(set) var allPoints: [PortfolioHistoryPoint] = []
    @Published private(set) var currencyCode = ""
    @Published var errorMessage: String?

    private let reloadRunner = CancelableTaskRunner()

    /// `true` while balance history is being fetched.
    var isLoading: Bool { reloadRunner.isRunning }

    init() {
        reloadRunner.onStateChanged = { [weak self] in self?.objectWillChange.send() }
    }

    var latestPoint: PortfolioHistoryPoint? {
        allPoints.last
    }

    var visibleSeries: [PortfolioHistoryPoint] {
        filtered(points: allPoints, for: selectedRange)
    }

    func loadIfNeeded(credentials: SnapTradeCredentials?, snapshot: PortfolioSnapshot?) async {
        guard allPoints.isEmpty else { return }
        await reload(credentials: credentials, snapshot: snapshot)
    }

    func reload(credentials: SnapTradeCredentials?, snapshot: PortfolioSnapshot?) async {
        await reloadRunner.run { [weak self] gen in
            guard let self else { return }

            guard let credentials, credentials.isComplete else {
                allPoints = []
                errorMessage = "Connect your SnapTrade account before opening portfolio history."
                return
            }

            errorMessage = nil

            do {
                let client = SnapTradeClient(credentials: credentials)
                let accounts = try await historyAccounts(client: client, snapshot: snapshot)
                let histories = try await withThrowingTaskGroup(
                    of: SnapTradeAccountBalanceHistoryDTO.self,
                    returning: [SnapTradeAccountBalanceHistoryDTO].self
                ) { group in
                    for account in accounts {
                        group.addTask {
                            try await client.accountBalanceHistory(accountID: account.id)
                        }
                    }

                    var histories: [SnapTradeAccountBalanceHistoryDTO] = []
                    for try await history in group {
                        histories.append(history)
                    }
                    return histories
                }

                // Discard stale results.
                guard gen == reloadRunner.generation else { return }

                let result = try PortfolioHistoryAggregator.aggregate(histories: histories)
                currencyCode = result.currencyCode
                allPoints = result.points
            } catch {
                guard gen == reloadRunner.generation else { return }
                allPoints = []
                errorMessage = UserFacingError.message(
                    for: error,
                    fallback: "Account history couldn’t be loaded. Please try again."
                )
            }
        }
    }

    private func historyAccounts(
        client: SnapTradeClient,
        snapshot: PortfolioSnapshot?
    ) async throws -> [PortfolioHistoryAccount] {
        if let snapshot, !snapshot.accounts.isEmpty {
            return snapshot.accounts.map { PortfolioHistoryAccount(id: $0.id) }
        }

        return try await client.listAccounts().map { PortfolioHistoryAccount(id: $0.id) }
    }

    private func filtered(
        points: [PortfolioHistoryPoint],
        for range: PortfolioHistoryRange
    ) -> [PortfolioHistoryPoint] {
        guard !points.isEmpty else { return [] }

        switch range {
        case .fiveDays:
            return points.since(days: 5)
        case .threeMonths:
            return points.since(months: 3)
        case .oneYear:
            return points.since(years: 1)
        case .yearToDate:
            guard let latestDate = points.last?.date,
                  let startOfYear = Calendar.current.dateInterval(of: .year, for: latestDate)?.start
            else {
                return points
            }
            return points.filter { $0.date >= startOfYear }
        }
    }
}

private struct PortfolioHistoryAccount {
    let id: String
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

private extension Array where Element == PortfolioHistoryPoint {
    func since(days: Int) -> [PortfolioHistoryPoint] {
        guard let latestDate = last?.date,
              let startDate = Calendar.current.date(byAdding: .day, value: -days, to: latestDate)
        else {
            return self
        }

        return filter { $0.date >= startDate }
    }

    func since(months: Int) -> [PortfolioHistoryPoint] {
        guard let latestDate = last?.date,
              let startDate = Calendar.current.date(byAdding: .month, value: -months, to: latestDate)
        else {
            return self
        }

        return filter { $0.date >= startDate }
    }

    func since(years: Int) -> [PortfolioHistoryPoint] {
        guard let latestDate = last?.date,
              let startDate = Calendar.current.date(byAdding: .year, value: -years, to: latestDate)
        else {
            return self
        }

        return filter { $0.date >= startDate }
    }
}

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
