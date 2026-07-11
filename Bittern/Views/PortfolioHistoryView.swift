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
        .tint(BitternTheme.blue)
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
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(BitternTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(totalValueText)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)

                Text(currencyCode)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)
            }

            HStack(spacing: 9) {
                Text(changeAmountText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(BitternTheme.performanceColor(valueDelta))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(changePercentText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(BitternTheme.performanceColor(valueDelta))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(BitternTheme.performanceColor(valueDelta).opacity(0.18))
                    .clipShape(Capsule())

                Text("· \(dateText)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
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

    private var lineColor: Color {
        guard let first = series.first?.totalValue,
              let last = series.last?.totalValue
        else {
            return BitternTheme.secondaryInk
        }

        return BitternTheme.performanceColor(last - first)
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(BitternTheme.secondaryInk)
                        .scaleEffect(1.2)
                        .frame(height: 318)
                        .frame(maxWidth: .infinity)
                } else if series.count < 2 {
                    Text("N/A")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.secondaryInk)
                        .frame(height: 318)
                        .frame(maxWidth: .infinity)
                } else {
                    PortfolioHistoryChart(
                        points: series,
                        baseValue: series.first?.totalValue,
                        currencyCode: currencyCode,
                        lineColor: lineColor,
                        selectedPoint: $selectedPoint
                    )
                    .frame(height: 318)
                    .padding(.horizontal, -portfolioHistoryChartSideInset)
                }
            }

            HStack(spacing: 0) {
                ForEach(PortfolioHistoryRange.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            range = option
                            selectedPoint = nil
                        }
                    } label: {
                        Text(option.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(range == option ? BitternTheme.gain : BitternTheme.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background {
                                if range == option {
                                    Capsule()
                                        .fill(BitternTheme.gain.opacity(0.17))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.title) history range")
                }
            }
        }
    }
}

private struct PortfolioHistoryChart: View {
    let points: [PortfolioHistoryPoint]
    let baseValue: Double?
    let currencyCode: String
    let lineColor: Color
    @Binding var selectedPoint: PortfolioHistoryPoint?

    private var precomputedMinMax: (min: Double, max: Double) {
        let values = points.map(\.totalValue)
        guard let minValue = values.min(),
              let maxValue = values.max()
        else {
            return (0, 1)
        }

        let span = maxValue - minValue
        let padding = max(span * 0.08, max(abs(maxValue) * 0.002, 1))
        return (max(0, minValue - padding), maxValue + padding)
    }

    var body: some View {
        let minMax = precomputedMinMax
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, canvasSize in
                let metrics = PortfolioHistoryChartMetrics(
                    points: points,
                    size: canvasSize,
                    minValue: minMax.min,
                    maxValue: minMax.max
                )
                guard metrics.isDrawable else { return }

                if let baseValue,
                   let baseY = metrics.y(for: baseValue) {
                    var baseline = Path()
                    baseline.move(to: CGPoint(x: metrics.sideInset, y: baseY))
                    baseline.addLine(to: CGPoint(x: canvasSize.width - metrics.sideInset, y: baseY))
                    context.stroke(
                        baseline,
                        with: .color(BitternTheme.softLine.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [7, 7])
                    )

                    let label = Text(PortfolioFormat.wholeMoney(baseValue, currencyCode: currencyCode))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(BitternTheme.secondaryInk.opacity(0.62))
                    context.draw(label, at: CGPoint(x: canvasSize.width - metrics.sideInset - 32, y: max(12, baseY - 16)))
                }

                let activeIndex = selectedPoint.flatMap { metrics.index(of: $0) }
                let fullPath = metrics.path(through: points.indices)

                if let activeIndex {
                    context.stroke(
                        fullPath,
                        with: .color(lineColor.opacity(0.13)),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
                    )

                    let selectedPath = metrics.path(through: 0...activeIndex)
                    context.stroke(
                        selectedPath,
                        with: .color(lineColor),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
                    )
                } else {
                    context.stroke(
                        fullPath,
                        with: .color(lineColor),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
                    )
                }

                let markerIndex = activeIndex ?? points.indices.last
                if let markerIndex,
                   let marker = metrics.location(for: markerIndex) {
                    let outerRect = CGRect(
                        x: marker.x - 19,
                        y: marker.y - 19,
                        width: 38,
                        height: 38
                    )
                    let innerRect = CGRect(
                        x: marker.x - 6.5,
                        y: marker.y - 6.5,
                        width: 13,
                        height: 13
                    )
                    context.fill(Path(ellipseIn: outerRect), with: .color(lineColor.opacity(0.16)))
                    context.fill(Path(ellipseIn: innerRect), with: .color(lineColor))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectedPoint = nearestPoint(to: value.location.x, in: size.width)
                    }
                    .onEnded { _ in
                        selectedPoint = nil
                    }
            )
        }
    }

    private func nearestPoint(to xPosition: CGFloat, in width: CGFloat) -> PortfolioHistoryPoint? {
        guard points.count > 1, width > portfolioHistoryChartSideInset * 2 else { return points.last }
        let clamped = min(max(xPosition, portfolioHistoryChartSideInset), width - portfolioHistoryChartSideInset)
        let progress = (clamped - portfolioHistoryChartSideInset) / (width - portfolioHistoryChartSideInset * 2)
        let index = Int((progress * CGFloat(points.count - 1)).rounded())
        return points[min(max(index, 0), points.count - 1)]
    }
}

private let portfolioHistoryChartSideInset: CGFloat = 19

private struct PortfolioHistoryChartMetrics {
    let points: [PortfolioHistoryPoint]
    let size: CGSize
    let minValue: Double
    let maxValue: Double
    let topInset: CGFloat = 12
    let bottomInset: CGFloat = 28
    let sideInset: CGFloat = portfolioHistoryChartSideInset

    var isDrawable: Bool {
        points.count >= 2 && size.width > sideInset * 2 && size.height > topInset + bottomInset
    }

    func index(of point: PortfolioHistoryPoint) -> Int? {
        points.firstIndex(of: point)
    }

    func location(for index: Int) -> CGPoint? {
        guard points.indices.contains(index) else { return nil }
        let plotWidth = size.width - sideInset * 2
        let x = points.count == 1 ? size.width / 2 : sideInset + CGFloat(index) / CGFloat(points.count - 1) * plotWidth
        guard let y = y(for: points[index].totalValue) else { return nil }
        return CGPoint(x: x, y: y)
    }

    func y(for value: Double) -> CGFloat? {
        guard maxValue > minValue else { return nil }
        let height = size.height - topInset - bottomInset
        let progress = (value - minValue) / (maxValue - minValue)
        return topInset + (1 - CGFloat(progress)) * height
    }

    func path<R: Sequence>(through indices: R) -> Path where R.Element == Int {
        var path = Path()
        var didMove = false

        for index in indices {
            guard let location = location(for: index) else { continue }
            if didMove {
                path.addLine(to: location)
            } else {
                path.move(to: location)
                didMove = true
            }
        }

        return path
    }
}

private struct HistoryMessagePanel: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(BitternTheme.blue)
                .frame(width: 38, height: 38)
                .background(BitternTheme.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(BitternTheme.ink)

                Text(message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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
