//
//  PortfolioHistoryView.swift
//  Bittern
//

import SwiftUI

struct PortfolioHistoryView: View {
    let credentialsStore: CredentialsStore
    let dashboardViewModel: DashboardViewModel
    let connectBrokerage: () -> Void
    @State private var model = PortfolioHistoryModel()
    @Environment(\.portfolioRepository) private var repository
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false

    private var isConnected: Bool {
        credentialsStore.credentials?.sanitized.isComplete == true
    }

    var body: some View {
        Group {
            if isConnected {
                history
            } else {
                ContentUnavailableView {
                    Label("No Portfolio Connected", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Connect a brokerage to see how your portfolio's value has changed.")
                } actions: {
                    Button("Connect Brokerage", action: connectBrokerage)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        // Loads on appear and again whenever the credentials change.
        .task(id: credentialsStore.credentials) {
            guard isConnected else { return }
            await load()
        }
    }

    private var history: some View {
        PaneGeometryReader { size, fold in
            let arrangement = Self.panes.arrangement(in: size, fold: fold)

            ScrollView {
                switch arrangement {
                case .single:
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        chart(plotHeight: .standard, showsRangeSelector: true)
                            .frame(maxWidth: Self.maximumChartWidth)
                    }
                    .frame(maxWidth: Self.maximumContentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // The figures beside the chart, so the chart has the
                // height; above a fold, the chart with its figures and the
                // ranges below, where they are easier to reach.
                case .columns, .rows:
                    PaneSplit(arrangement: arrangement, margins: Self.paneMargins) {
                        if arrangement.isRows {
                            VStack(alignment: .leading, spacing: 16) {
                                header
                                chart(plotHeight: .fill, showsRangeSelector: false)
                            }
                        } else {
                            header
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } second: {
                        if arrangement.isRows {
                            ChartRangeSelector(
                                ranges: PortfolioHistoryRange.allCases,
                                title: { $0.title },
                                selectedRange: $model.selectedRange
                            ) {
                                model.selectedPoint = nil
                            }
                        } else {
                            chart(plotHeight: .fill, showsRangeSelector: true)
                        }
                    }
                    // Exactly the screen, so pulling still refreshes.
                    .frame(height: size.height)
                }
            }
            .softNavigationBarEdge()
        }
        // The grouped background of a holding's page, so the two chart
        // screens look alike.
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .errorToast(message: $model.errorMessage)
        .refreshable {
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

    private var header: some View {
        PortfolioHistoryHeader(
            series: model.visibleSeries,
            fallbackPoint: model.history?.points.last,
            selectedPoint: model.selectedPoint,
            range: model.selectedRange,
            currencyCode: model.history?.currencyCode ?? "",
            isPrivacyEnabled: isPrivacyEnabled
        )
    }

    private func chart(
        plotHeight: PerformanceChartPlotHeight,
        showsRangeSelector: Bool
    ) -> some View {
        PortfolioHistoryChartSection(
            series: model.visibleSeries,
            currencyCode: model.history?.currencyCode ?? "",
            isPrivacyEnabled: isPrivacyEnabled,
            range: $model.selectedRange,
            selectedPoint: $model.selectedPoint,
            isLoading: model.isLoading,
            plotHeight: plotHeight,
            showsRangeSelector: showsRangeSelector
        )
    }

    private static let maximumContentWidth: CGFloat = 900
    private static let maximumChartWidth: CGFloat = 760
    private static let paneMargins = EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20)

    /// The figures need room for a seven-figure total at the large title
    /// size; the chart, about an iPhone's width. Side by side only when
    /// wider than tall: a tall view already gives the chart its height.
    static let panes = PaneRequirements(
        minimumLeadingWidth: 200,
        minimumTrailingWidth: 360,
        preferredWidth: .leading(260),
        columnSpacing: 24,
        minimumColumnsHeight: 360,
        columnsOnlyWhenWide: true,
        minimumRowHeight: 240
    )
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Portfolio Value")
                .font(.title3)
                .foregroundStyle(BitternTheme.secondaryInk)

            Text(totalValueText)
                .font(.keyFigure(.largeTitle, weight: .bold))
                .foregroundStyle(BitternTheme.ink)
                .lineLimit(1)
                // The total is the one figure that must stay whole on a
                // single line, so it shrinks before it would wrap.
                .minimumScaleFactor(0.6)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    changeAmountLabel
                    changePercentLabel
                }

                VStack(alignment: .leading, spacing: 4) {
                    changeAmountLabel
                    changePercentLabel
                }
            }

            Text(dateText)
                .font(.subheadline)
                .foregroundStyle(BitternTheme.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var changeAmountLabel: some View {
        Text(changeAmountText)
            .font(.keyFigure(.body))
            .foregroundStyle(BitternTheme.performanceColor(valueDelta))
            .lineLimit(1)
    }

    private var changePercentLabel: some View {
        Text(changePercentText)
            .font(.keyFigure(.body))
            .foregroundStyle(BitternTheme.performanceColor(valueDelta))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(BitternTheme.performanceColor(valueDelta).opacity(0.15), in: .capsule)
    }

    private var totalValueText: String {
        guard let displayPoint else { return PortfolioFormat.missing }

        return isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: currencyCode)
            : PortfolioFormat.wholeMoney(displayPoint.totalValue, currencyCode: currencyCode)
    }

    private var changeAmountText: String {
        guard let valueDelta else { return PortfolioFormat.missing }

        if isPrivacyEnabled {
            return PortfolioFormat.hiddenSignedMoney(valueDelta, currencyCode: currencyCode)
        }

        return PortfolioFormat.wholeMoney(valueDelta, currencyCode: currencyCode, signed: true)
    }

    private var changePercentText: String {
        guard let valueDeltaPercent else { return PortfolioFormat.missing }
        return PortfolioFormat.percent(valueDeltaPercent, signed: true)
    }

    private var dateText: String {
        guard let displayPoint else { return range.title }
        return selectedPoint == nil
            ? range.title
            : PortfolioFormat.dayWithYear(displayPoint.date)
    }
}

private struct PortfolioHistoryChartSection: View {
    let series: [PortfolioHistoryPoint]
    let currencyCode: String
    let isPrivacyEnabled: Bool
    @Binding var range: PortfolioHistoryRange
    @Binding var selectedPoint: PortfolioHistoryPoint?
    let isLoading: Bool
    var plotHeight = PerformanceChartPlotHeight.standard
    var showsRangeSelector = true

    var body: some View {
        let baseValue = series.first?.totalValue

        PerformanceLineChartSection(
            points: series,
            value: { $0.totalValue },
            xScale: .indexed,
            date: { $0.date },
            axisUnit: range.axisUnit(for: series.map(\.date)),
            selectionLabel: { PortfolioFormat.dayWithYear($0.date) },
            valueLabel: isPrivacyEnabled
                ? nil
                : { [currencyCode] in PortfolioFormat.wholeMoney($0, currencyCode: currencyCode) },
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
            isLoading: isLoading,
            background: Color(uiColor: .systemGroupedBackground),
            plotHeight: plotHeight,
            showsRangeSelector: showsRangeSelector
        )
    }
}

extension PortfolioHistoryRange {
    /// The calendar unit the horizontal axis is labelled in. The longer
    /// ranges follow what the account's history actually spans, which can
    /// be less than the range when the account is new or it is January.
    func axisUnit(for dates: [Date]) -> PerformanceChartAxisUnit {
        switch self {
        case .fiveDays:
            .days
        case .threeMonths, .oneYear, .yearToDate:
            .fitting(dates)
        }
    }
}

#if DEBUG
#Preview {
    let credentialsStore = PreviewSupport.credentialsStore()
    NavigationStack {
        PortfolioHistoryView(
            credentialsStore: credentialsStore,
            dashboardViewModel: PreviewSupport.dashboardViewModel(credentialsStore: credentialsStore),
            connectBrokerage: {}
        )
    }
}
#endif
