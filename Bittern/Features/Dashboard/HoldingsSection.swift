//
//  HoldingsSection.swift
//  Bittern
//

import SwiftUI

struct HoldingsSection: View {
    let sortedHoldings: [PortfolioHolding]
    let snapshot: PortfolioSnapshot
    let holdingColorLookup: [String: Color]
    let performanceMode: PerformanceMode
    let sortOption: HoldingSortOption
    let isPrivacyEnabled: Bool
    let controls: DashboardControls?
    @State private var marketTime = Date()

    private var nextExtendedHoursBoundary: Date? {
        sortedHoldings.flatMap { holding in
            [
                holding.activePreMarketChange(at: marketTime)?.sessionEnd,
                holding.activePostMarketChange(at: marketTime)?.sessionEnd
            ].compactMap { $0 }
        }.min()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 8)

            if sortedHoldings.isEmpty {
                EmptyHoldingsView()
                    .padding(.top, 24)
            } else {
                holdingsList
            }
        }
        .onChange(of: snapshot.lastUpdated) { _, _ in
            marketTime = Date()
        }
        .task(id: nextExtendedHoursBoundary) {
            guard let boundary = nextExtendedHoursBoundary else { return }
            do {
                try await Task.sleep(for: .seconds(max(boundary.timeIntervalSinceNow, 0)))
            } catch {
                return
            }
            marketTime = Date()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Holdings")
                    .font(.title2.bold())
                    .foregroundStyle(BitternTheme.ink)

                Text(
                    snapshot.lastUpdated.map { "Updated \(PortfolioFormat.lastUpdated($0))" }
                        ?? "Prices incomplete"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(BitternTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            sortControl
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, 3)
        }
    }

    @ViewBuilder
    private var sortControl: some View {
        let label = HoldingsSortLabel(title: sortTitle)
        if let controls {
            Menu {
                Section("Return") {
                    ForEach(PerformanceMode.allCases) { mode in
                        Button {
                            controls.selectPerformanceMode(mode)
                        } label: {
                            Label(mode.title, systemImage: mode.systemImage)
                        }
                    }
                }

                Section("Sort") {
                    ForEach(HoldingSortOption.allCases) { option in
                        Button {
                            controls.selectSortOption(option)
                        } label: {
                            Label(option.title, systemImage: option.systemImage)
                        }
                    }
                }
            } label: {
                label
            }
            .accessibilityLabel("Holding return and sort options")
        } else {
            label
        }
    }

    /// The live list loads rows lazily and opens each holding; the export
    /// renders every row.
    @ViewBuilder
    private var holdingsList: some View {
        if controls != nil {
            LazyVStack(spacing: 0) {
                ForEach(sortedHoldings) { holding in
                    NavigationLink(value: HoldingRoute(holdingID: holding.id)) {
                        row(for: holding)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(sortedHoldings) { holding in
                    row(for: holding)
                }
            }
        }
    }

    private func row(for holding: PortfolioHolding) -> HoldingListRow {
        HoldingListRow(
            holding: holding,
            allocation: snapshot.allocation(of: holding),
            performanceMode: performanceMode,
            isPrivacyEnabled: isPrivacyEnabled,
            color: holdingColorLookup[holding.id] ?? BitternTheme.allocationColor(at: 0),
            showsDivider: holding.id != sortedHoldings.last?.id,
            marketTime: marketTime
        )
    }

    private var sortTitle: String {
        let prefix = switch performanceMode {
        case .today: "Today's"
        case .allTime: "All-time"
        }

        return switch sortOption {
        case .gainAmount: "\(prefix) gain"
        case .lossAmount: "\(prefix) loss"
        case .percent: "\(prefix) return (%)"
        case .marketValue: "Market value"
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

extension HoldingSortOption {
    var systemImage: String {
        switch self {
        case .gainAmount:
            "arrow.up.right"
        case .lossAmount:
            "arrow.down.right"
        case .percent:
            "percent"
        case .marketValue:
            "chart.pie"
        }
    }
}
