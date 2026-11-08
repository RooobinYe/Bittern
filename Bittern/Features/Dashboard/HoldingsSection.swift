//
//  HoldingsSection.swift
//  Bittern
//

import SwiftUI

/// The holdings title and the menu that picks the return and the order.
/// It says nothing about when prices were updated: figures that aren't
/// current turn gray instead.
struct HoldingsHeader: View {
    let performanceMode: PerformanceMode
    let sortOption: HoldingSortOption
    /// Nil shows the menu's label without the menu, as in the exported image.
    let controls: DashboardControls?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titles
                    .frame(maxWidth: .infinity, alignment: .leading)
                optionsMenu
            }

            VStack(alignment: .leading, spacing: 8) {
                titles
                optionsMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private var titles: some View {
        Text("Holdings")
            .font(.title2.bold())
            .foregroundStyle(BitternTheme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var optionsMenu: some View {
        let label = HoldingsOptionsLabel(title: sortTitle)
        if let controls {
            // Closures rather than the function values themselves: Swift 6.2
            // crashes converting a main-actor function value to the setter's
            // `@isolated(any)` type.
            let selectPerformanceMode = controls.selectPerformanceMode
            let selectSortOption = controls.selectSortOption
            Menu {
                Picker("Return", selection: Binding(
                    get: { performanceMode },
                    set: { selectPerformanceMode($0) }
                )) {
                    ForEach(PerformanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.inline)

                Picker("Sort By", selection: Binding(
                    get: { sortOption },
                    set: { selectSortOption($0) }
                )) {
                    ForEach(HoldingSortOption.allCases) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                label
            }
            .accessibilityLabel("Holding options")
            .accessibilityValue(sortTitle)
        } else {
            label
        }
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

private struct HoldingsOptionsLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .accessibilityHidden(true)
        }
        .foregroundStyle(BitternTheme.secondaryInk)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct EmptyHoldingsView: View {
    /// Why there may be nothing to show, when holdings are hidden.
    let hiddenNote: String?

    var body: some View {
        ContentUnavailableView {
            Label("No Holdings", systemImage: "tray")
        } description: {
            if let hiddenNote {
                Text(hiddenNote)
            }
        }
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
