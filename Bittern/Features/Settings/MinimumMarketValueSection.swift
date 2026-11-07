//
//  MinimumMarketValueSection.swift
//  Bittern
//
//  The minimum market value: holdings worth less are hidden throughout the
//  app. Set once and rarely changed, so it lives in Settings rather than on
//  the Portfolio page.
//

import SwiftUI

struct MinimumMarketValueSection: View {
    let viewModel: DashboardViewModel
    @State private var isEditing = false

    private var minimum: String {
        PortfolioFormat.price(viewModel.minPriceThreshold, currencyCode: viewModel.displayCurrencyCode)
    }

    private var footer: String {
        let rule = "Holdings worth less than this are hidden throughout the app."
        return switch viewModel.hiddenHoldingCount {
        case 0: rule
        case 1: "\(rule) 1 is hidden now."
        case let count: "\(rule) \(count) are hidden now."
        }
    }

    var body: some View {
        Section {
            Button {
                isEditing = true
            } label: {
                LabeledContent("Minimum Value", value: minimum)
            }
            .tint(BitternTheme.ink)
        } header: {
            Text("Holdings")
        } footer: {
            Text(footer)
        }
        .minimumMarketValueEditor(
            isPresented: $isEditing,
            value: viewModel.minPriceThreshold,
            currencyCode: viewModel.displayCurrencyCode,
            save: { viewModel.setMinimumMarketValue($0) }
        )
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
