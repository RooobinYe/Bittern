//
//  HoldingsSection.swift
//  Bittern
//

import SwiftUI

/// The holdings title, when prices were updated, and the menu that picks
/// the return, the order and the minimum market value.
struct HoldingsHeader: View {
    let lastUpdated: Date?
    let performanceMode: PerformanceMode
    let sortOption: HoldingSortOption
    let minimumMarketValue: Double
    let hiddenHoldingCount: Int
    let currencyCode: String
    /// Nil shows the menu's label without the menu, as in the exported image.
    let controls: DashboardControls?
    let editMinimumValue: () -> Void

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
        VStack(alignment: .leading, spacing: 2) {
            Text("Holdings")
                .font(.title2.bold())
                .foregroundStyle(BitternTheme.ink)

            Text(lastUpdated.map { "Updated \(PortfolioFormat.lastUpdated($0))" } ?? "Prices incomplete")
                .font(.footnote)
                .foregroundStyle(BitternTheme.secondaryInk)
        }
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

                Section {
                    Button(action: editMinimumValue) {
                        Label("Minimum Value", systemImage: "line.3.horizontal.decrease")
                        Text(minimumValueSubtitle)
                    }
                }
            } label: {
                label
            }
            .accessibilityLabel("Holding options")
            .accessibilityValue(sortTitle)
        } else {
            label
        }
    }

    private var minimumValueSubtitle: String {
        let minimum = PortfolioFormat.price(minimumMarketValue, currencyCode: currencyCode)
        return "\(minimum)\(PortfolioFormat.separator)\(hiddenHoldingCount) hidden"
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

private struct MinimumMarketValueEditor: ViewModifier {
    @Binding var isPresented: Bool
    let value: Double
    let currencyCode: String
    let save: (Double) -> Void

    @State private var draft: Double?

    func body(content: Content) -> some View {
        content
            .alert("Minimum Value (\(currencyCode))", isPresented: $isPresented) {
                TextField(
                    "0.00",
                    value: $draft,
                    format: .number.precision(.fractionLength(0...2))
                )
                .keyboardType(.decimalPad)

                Button("Cancel", role: .cancel) {}

                Button("Save") {
                    save(draft ?? 0)
                }
            } message: {
                Text("Holdings worth less than this are hidden throughout the app. Enter 0 to show every holding.")
            }
            .onChange(of: isPresented) { _, isPresented in
                if isPresented {
                    draft = value
                }
            }
    }
}

extension View {
    func minimumMarketValueEditor(
        isPresented: Binding<Bool>,
        value: Double,
        currencyCode: String,
        save: @escaping (Double) -> Void
    ) -> some View {
        modifier(
            MinimumMarketValueEditor(
                isPresented: isPresented,
                value: value,
                currencyCode: currencyCode,
                save: save
            )
        )
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
