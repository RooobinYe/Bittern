//
//  ContributionCalculatorView.swift
//  Bittern
//

import SwiftUI

private enum ContributionFocusField: Hashable {
    case amount
    case target(String)
}

struct ContributionCalculatorView: View {
    let viewModel: DashboardViewModel
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false
    @State private var plan = ContributionPlan.load()
    @State private var contributionAmount: Double?
    @FocusState private var focusedField: ContributionFocusField?

    var body: some View {
        // Built once per render: it runs the Optimal Share Search.
        let session = ContributionSession(
            holdings: viewModel.thresholdFilteredHoldings,
            plan: plan,
            contributionAmount: contributionAmount,
            providerName: providerName(for:)
        )
        // The Contribution Amount is in the elected holdings' currency.
        let currencyCode = session.electedHoldings.first?.currencyCode ?? viewModel.displayCurrencyCode

        Form {
            amountSection(currencyCode: currencyCode)
            holdingsSection(session)
            resultSection(session, currencyCode: currencyCode)
        }
        .fontDesign(.default)
        .softNavigationBarEdge()
        .navigationTitle("Contributions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear(perform: prunePlan)
        .onChange(of: plan) { _, newValue in
            newValue.save()
        }
    }

    private func amountSection(currencyCode: String) -> some View {
        Section {
            LabeledContent("Amount") {
                HStack(spacing: 8) {
                    Text(currencyCode)
                        .font(.subheadline)
                        .foregroundStyle(BitternTheme.secondaryInk)

                    TextField(
                        "0.00",
                        value: $contributionAmount,
                        format: .number.precision(.fractionLength(0...2))
                    )
                    .font(.body.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .amount)
                    .frame(minWidth: 72, maxWidth: 112)
                }
            }
        } header: {
            Text("Contribution")
        } footer: {
            Text("The full amount is spent across the holdings you elect below.")
        }
    }

    private func holdingsSection(_ session: ContributionSession) -> some View {
        Section {
            if session.holdings.isEmpty {
                Text("No holdings available.")
                    .foregroundStyle(BitternTheme.secondaryInk)
            } else {
                let colors = BitternTheme.holdingAllocationColors(for: session.holdings)

                ForEach(session.holdings) { holding in
                    ContributionHoldingRow(
                        holding: holding,
                        accountDisplayName: providerName(for: holding),
                        color: colors[holding.id] ?? BitternTheme.allocationColor(at: 0),
                        isPrivacyEnabled: isPrivacyEnabled,
                        isElectable: ContributionSession.isElectable(holding),
                        isElected: session.isElected(holding),
                        targetPercent: targetBinding(for: holding),
                        outcome: session.outcomesByHoldingID[holding.id],
                        focusedField: $focusedField
                    ) {
                        plan.toggleElection(
                            accountID: holding.accountID,
                            symbol: holding.symbol
                        )
                    }
                }
            }
        } header: {
            Text("Holdings")
        } footer: {
            Text("Target percentages describe each elected holding's share of the elected holdings plus this contribution, and must total exactly 100%.")
        }
    }

    private func resultSection(_ session: ContributionSession, currencyCode: String) -> some View {
        Section {
            if let outcome = session.outcome {
                ForEach(session.accountRequirements) { requirement in
                    LabeledContent(requirement.name) {
                        Text(formattedMoney(requirement.amount, currencyCode: currencyCode))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(BitternTheme.ink)
                    }
                }

                LabeledContent("Invested") {
                    Text(formattedMoney(outcome.investedAmount, currencyCode: currencyCode))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(BitternTheme.ink)
                }

                LabeledContent("Residual Cash") {
                    Text(formattedMoney(outcome.residualCash, currencyCode: currencyCode))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(BitternTheme.secondaryInk)
                }
            } else {
                LabeledContent("Allocated") {
                    Text(session.allocatedPercent / 100, format: .percent.precision(.fractionLength(0...2)))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(BitternTheme.secondaryInk)
                }
            }
        } header: {
            Text(session.outcome?.isEstimated == true ? "Result (Estimated)" : "Result")
        } footer: {
            if let reason = session.incompleteReason {
                Text(reason.message)
            }
        }
    }

    private func providerName(for holding: PortfolioHolding) -> String {
        viewModel.snapshot?.accounts
            .first { $0.id == holding.accountID }?
            .providerName ?? holding.accountName
    }

    private func formattedMoney(_ value: Double, currencyCode: String) -> String {
        isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: currencyCode)
            : PortfolioFormat.price(value, currencyCode: currencyCode)
    }

    private func targetBinding(for holding: PortfolioHolding) -> Binding<Double?> {
        Binding(
            get: { plan.targetPercent(accountID: holding.accountID, symbol: holding.symbol) },
            set: { newValue in
                plan.setTargetPercent(
                    newValue,
                    accountID: holding.accountID,
                    symbol: holding.symbol
                )
            }
        )
    }

    private func prunePlan() {
        guard let snapshot = viewModel.snapshot,
              !snapshot.holdings.isEmpty
        else {
            return
        }

        var pruned = plan
        pruned.prune(keeping: snapshot.holdings)
        if pruned != plan {
            plan = pruned
        }
    }
}

private extension ContributionSession.IncompleteReason {
    var message: String {
        switch self {
        case .noElectedHoldings:
            "Elect at least one holding."
        case .mixedCurrencies:
            "Elected holdings must share one currency."
        case .missingAmount:
            "Enter a contribution amount."
        case .missingTargets:
            "Enter a target for every elected holding."
        case .targetsNotWhole:
            "Targets must total exactly 100%."
        }
    }
}

private struct ContributionHoldingRow: View {
    let holding: PortfolioHolding
    let accountDisplayName: String
    let color: Color
    let isPrivacyEnabled: Bool
    let isElectable: Bool
    let isElected: Bool
    @Binding var targetPercent: Double?
    let outcome: ContributionCalculator.HoldingOutcome?
    let focusedField: FocusState<ContributionFocusField?>.Binding
    let onToggleElection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onToggleElection) {
                    Image(systemName: isElected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isElected ? BitternTheme.accent : BitternTheme.secondaryInk)
                }
                .buttonStyle(.plain)
                .disabled(!isElectable)
                .accessibilityLabel(isElected ? "Remove \(holding.symbol) from contribution" : "Include \(holding.symbol) in contribution")

                HoldingSymbolIcon(
                    symbol: holding.symbol,
                    logoURL: holding.logoURL,
                    color: color,
                    size: 32
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(holding.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BitternTheme.ink)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(BitternTheme.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isElected {
                    HStack(spacing: 3) {
                        TextField(
                            "0",
                            value: $targetPercent,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .font(.body.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .focused(focusedField, equals: .target(holding.id))
                        .frame(width: 56)

                        Text("%")
                            .font(.subheadline)
                            .foregroundStyle(BitternTheme.secondaryInk)
                    }
                }
            }

            if let outcome {
                HStack(alignment: .firstTextBaseline) {
                    Text(orderDescription(for: outcome))

                    Spacer(minLength: 8)

                    Text(PortfolioFormat.percent(outcome.postContributionPercent, fractionDigits: 1))
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(BitternTheme.secondaryInk)
                .padding(.leading, 44)
            }
        }
        .opacity(isElectable ? 1 : 0.4)
    }

    private var currencyCode: String {
        holding.currencyCode
    }

    private var subtitle: String {
        guard let marketValue = holding.marketValue else {
            return "\(accountDisplayName) · No price"
        }
        let value = isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: currencyCode)
            : PortfolioFormat.price(marketValue, currencyCode: currencyCode)
        return "\(accountDisplayName) · \(value)"
    }

    private func orderDescription(for outcome: ContributionCalculator.HoldingOutcome) -> String {
        guard let shareOrder = outcome.shareOrder else {
            let amount = isPrivacyEnabled
                ? PortfolioFormat.hiddenMoney(currencyCode: currencyCode)
                : PortfolioFormat.price(outcome.actualSpend, currencyCode: currencyCode)
            return "Buy \(amount)"
        }

        guard shareOrder > 0 else {
            return "Buy 0 shares"
        }

        if isPrivacyEnabled {
            return "Buy •••• shares · \(PortfolioFormat.hiddenMoney(currencyCode: currencyCode))"
        }

        let unit = shareOrder == 1 ? "share" : "shares"
        return "Buy \(shareOrder) \(unit) · \(PortfolioFormat.price(outcome.actualSpend, currencyCode: currencyCode))"
    }
}
