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
                    range: $historyModel.selectedRange,
                    selectedPoint: $historyModel.selectedPoint,
                    isLoading: historyModel.isLoading
                )
                .frame(maxWidth: portfolioHistoryMaximumChartWidth)

                if let errorMessage = historyModel.errorMessage {
                    HistoryMessagePanel(
                        systemImage: "exclamationmark.triangle",
                        title: "History unavailable",
                        message: errorMessage
                    )
                } else if !historyModel.isLoading && historyModel.allPoints.isEmpty {
                    HistoryMessagePanel(
                        systemImage: "chart.xyaxis.line",
                        title: "No history yet",
                        message: "Connect your portfolio accounts to load daily total money history."
                    )
                }
            }
            .frame(maxWidth: portfolioHistoryMaximumContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
        }
        .background(BitternTheme.background.ignoresSafeArea())
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .toolbar(.visible, for: .navigationBar)
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
    @Published private(set) var currencyCode = "USD"
    @Published private(set) var errorMessage: String?

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

    func loadIfNeeded(credentials: SnapTradeCredentials?, snapshot: PortfolioSnapshot) async {
        guard allPoints.isEmpty else { return }
        await reload(credentials: credentials, snapshot: snapshot)
    }

    func reload(credentials: SnapTradeCredentials?, snapshot: PortfolioSnapshot) async {
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
                guard !accounts.isEmpty else {
                    throw PortfolioHistoryError.noAccounts
                }

                var histories: [SnapTradeAccountBalanceHistoryDTO] = []
                for account in accounts {
                    // Bail out early when a newer reload has started.
                    guard gen == reloadRunner.generation else { return }
                    histories.append(try await client.accountBalanceHistory(accountID: account.id))
                }

                // Discard stale results.
                guard gen == reloadRunner.generation else { return }

                let currencies = Set(
                    histories.compactMap { history in
                        history.currency?
                            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            .nilIfEmpty
                    }
                )
                currencyCode = currencies.count == 1
                    ? (currencies.first ?? snapshot.currencyCode)
                    : snapshot.currencyCode

                allPoints = aggregate(histories: histories)
                if allPoints.isEmpty {
                    throw PortfolioHistoryError.emptyHistory
                }
            } catch {
                guard gen == reloadRunner.generation else { return }
                allPoints = []
                errorMessage = error.localizedDescription
            }
        }
    }

    private func historyAccounts(
        client: SnapTradeClient,
        snapshot: PortfolioSnapshot
    ) async throws -> [PortfolioHistoryAccount] {
        if !snapshot.accounts.isEmpty {
            return snapshot.accounts.map {
                PortfolioHistoryAccount(id: $0.id, currencyCode: $0.currencyCode)
            }
        }

        return try await client.listAccounts().map {
            PortfolioHistoryAccount(id: $0.id, currencyCode: $0.balance?.total?.currency)
        }
    }

    private func aggregate(histories: [SnapTradeAccountBalanceHistoryDTO]) -> [PortfolioHistoryPoint] {
        let calendar = Calendar.current
        var totalsByDate: [Date: Double] = [:]

        for history in histories {
            for point in history.history {
                guard let date = point.date,
                      let totalValue = point.totalValue,
                      totalValue >= 0
                else {
                    continue
                }

                let day = calendar.startOfDay(for: date)
                totalsByDate[day, default: 0] += totalValue
            }
        }

        return totalsByDate
            .map { PortfolioHistoryPoint(date: $0.key, totalValue: $0.value) }
            .sorted { $0.date < $1.date }
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
    let currencyCode: String?
}

private enum PortfolioHistoryError: LocalizedError {
    case noAccounts
    case emptyHistory

    var errorDescription: String? {
        switch self {
        case .noAccounts:
            "No connected portfolio accounts were found."
        case .emptyHistory:
            "SnapTrade did not return balance history for these accounts."
        }
    }
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
            Text("Total Money")
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
        guard let displayPoint else {
            return isPrivacyEnabled ? hiddenHistoryMoney(currencyCode: currencyCode) : "N/A"
        }

        return isPrivacyEnabled
            ? hiddenHistoryMoney(currencyCode: currencyCode)
            : PortfolioFormat.wholeMoney(displayPoint.totalValue, currencyCode: currencyCode)
    }

    private var changeAmountText: String {
        if isPrivacyEnabled {
            let sign = valueDelta.map { $0 < 0 ? "-" : $0 > 0 ? "+" : "" } ?? ""
            return "\(sign)\(hiddenHistoryMoney(currencyCode: currencyCode))"
        }

        guard let valueDelta else { return "N/A" }
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
    @Binding var range: PortfolioHistoryRange
    @Binding var selectedPoint: PortfolioHistoryPoint?
    let isLoading: Bool

    var body: some View {
        let baseValue = series.first?.totalValue

        PerformanceLineChartSection(
            points: series,
            value: { $0.totalValue },
            baseValue: baseValue,
            baselineLabel: baseValue.map {
                PortfolioFormat.wholeMoney($0, currencyCode: currencyCode)
            },
            ranges: PortfolioHistoryRange.allCases,
            rangeTitle: { $0.title },
            selectedRange: $range,
            selectedPoint: $selectedPoint,
            isLoading: isLoading
        )
    }
}

private struct HistoryMessagePanel: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: systemImage)
                .font(.headline.bold())
                .foregroundStyle(BitternTheme.accent)
                .frame(width: 38, height: 38)
                .background(BitternTheme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(BitternTheme.ink)

                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .bitternPanel()
    }
}

private let portfolioHistorySelectionDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "d MMM, yyyy"
    return formatter
}()

private func hiddenHistoryMoney(currencyCode: String) -> String {
    currencyCode == "USD" ? "$••••" : "\(currencyCode) ••••"
}

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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#if DEBUG
struct PortfolioHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PortfolioHistoryView(
                credentialsStore: CredentialsStore(),
                dashboardViewModel: DashboardViewModel(credentialsStore: CredentialsStore())
            )
        }
    }
}
#endif
