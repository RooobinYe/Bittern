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
    @ObservedObject var viewModel: DashboardViewModel
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false
    @State private var plan = ContributionPlan.load()
    @State private var contributionAmount: Double?
    @FocusState private var focusedField: ContributionFocusField?

    /// The Contribution Amount is in the elected holdings' currency.
    private var currencyCode: String {
        electedHoldings.first?.currencyCode ?? viewModel.displayCurrencyCode
    }

    private var providerNamesByAccountID: [String: String] {
        Dictionary(uniqueKeysWithValues: (viewModel.snapshot?.accounts ?? []).map { ($0.id, $0.providerName) })
    }

    private func providerName(for holding: PortfolioHolding) -> String {
        providerNamesByAccountID[holding.accountID] ?? holding.accountName
    }

    private var holdings: [PortfolioHolding] {
        viewModel.thresholdFilteredHoldings.sorted {
            ($0.marketValue ?? 0) > ($1.marketValue ?? 0)
        }
    }

    /// Elected holdings that can actually participate: an unpriced holding is
    /// never electable, and a stale election of one is void (see CONTEXT.md).
    private var electedHoldings: [PortfolioHolding] {
        holdings.filter { isElectable($0) && isElected($0) }
    }

    private var allocatedPercent: Double {
        electedHoldings.reduce(0) { total, holding in
            total + (targetPercent(for: holding) ?? 0)
        }
    }

    private var outcome: ContributionCalculator.Outcome? {
        guard let contributionAmount else { return nil }

        let elected = electedHoldings
        guard !elected.isEmpty else { return nil }

        var inputs: [ContributionCalculator.ElectedHoldingInput] = []
        for holding in elected {
            guard let price = holding.currentPrice,
                  let marketValue = holding.marketValue,
                  let target = targetPercent(for: holding)
            else {
                return nil
            }

            inputs.append(
                ContributionCalculator.ElectedHoldingInput(
                    id: holding.id,
                    marketValue: marketValue,
                    price: price,
                    usesWholeShares: holding.quantityUnit == .shares,
                    targetPercent: target,
                    currencyCode: holding.currencyCode
                )
            )
        }

        return ContributionCalculator.calculate(
            elected: inputs,
            contributionAmount: contributionAmount
        )
    }

    private var outcomesByHoldingID: [String: ContributionCalculator.HoldingOutcome] {
        guard let outcome else { return [:] }
        return Dictionary(uniqueKeysWithValues: outcome.holdings.map { ($0.id, $0) })
    }

    private struct AccountRequirement: Identifiable {
        let name: String
        let amount: Double

        var id: String { name }
    }

    /// The cash to prepare at each provider this session — the sum of its
    /// elected holdings' actual purchases. Providers with nothing to buy
    /// are omitted.
    private var accountRequirements: [AccountRequirement] {
        let spends = outcomesByHoldingID
        var amounts: [String: Double] = [:]

        for holding in electedHoldings {
            guard let spend = spends[holding.id]?.actualSpend, spend > 0 else { continue }
            amounts[providerName(for: holding), default: 0] += spend
        }

        return amounts
            .map { AccountRequirement(name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        Form {
            amountSection
            holdingsSection
            resultSection
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

    private var amountSection: some View {
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

    private var holdingsSection: some View {
        Section {
            if holdings.isEmpty {
                Text("No holdings available.")
                    .foregroundStyle(BitternTheme.secondaryInk)
            } else {
                let colors = BitternTheme.holdingAllocationColors(for: holdings)

                ForEach(holdings) { holding in
                    ContributionHoldingRow(
                        holding: holding,
                        accountDisplayName: providerName(for: holding),
                        color: colors[holding.id] ?? BitternTheme.allocationColor(at: 0),
                        isPrivacyEnabled: isPrivacyEnabled,
                        isElectable: isElectable(holding),
                        isElected: isElectable(holding) && isElected(holding),
                        targetPercent: targetBinding(for: holding),
                        outcome: outcomesByHoldingID[holding.id],
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

    private var resultSection: some View {
        Section {
            if let outcome {
                ForEach(accountRequirements) { requirement in
                    LabeledContent(requirement.name) {
                        Text(formattedMoney(requirement.amount))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(BitternTheme.ink)
                    }
                }

                LabeledContent("Invested") {
                    Text(formattedMoney(outcome.investedAmount))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(BitternTheme.ink)
                }

                LabeledContent("Residual Cash") {
                    Text(formattedMoney(outcome.residualCash))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(BitternTheme.secondaryInk)
                }
            } else {
                LabeledContent("Allocated") {
                    Text(allocatedPercent / 100, format: .percent.precision(.fractionLength(0...2)))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(BitternTheme.secondaryInk)
                }
            }
        } header: {
            Text(outcome?.isEstimated == true ? "Result (Estimated)" : "Result")
        } footer: {
            if outcome == nil {
                Text(incompleteReason)
            }
        }
    }

    private var incompleteReason: String {
        if electedHoldings.isEmpty {
            return "Elect at least one holding."
        }

        if Set(electedHoldings.map(\.currencyCode)).count > 1 {
            return "Elected holdings must share one currency."
        }

        if contributionAmount == nil || (contributionAmount ?? 0) <= 0 {
            return "Enter a contribution amount."
        }

        if electedHoldings.contains(where: { targetPercent(for: $0) == nil }) {
            return "Enter a target for every elected holding."
        }

        return "Targets must total exactly 100%."
    }

    private func formattedMoney(_ value: Double) -> String {
        isPrivacyEnabled
            ? PortfolioFormat.hiddenMoney(currencyCode: currencyCode)
            : PortfolioFormat.price(value, currencyCode: currencyCode)
    }

    private func isElectable(_ holding: PortfolioHolding) -> Bool {
        holding.currentPrice != nil
    }

    private func isElected(_ holding: PortfolioHolding) -> Bool {
        plan.isElected(accountID: holding.accountID, symbol: holding.symbol)
    }

    private func targetPercent(for holding: PortfolioHolding) -> Double? {
        plan.targetPercent(accountID: holding.accountID, symbol: holding.symbol)
    }

    private func targetBinding(for holding: PortfolioHolding) -> Binding<Double?> {
        Binding(
            get: { targetPercent(for: holding) },
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
        let allHoldings = snapshot.holdings

        var pruned = plan
        pruned.prune(keeping: allHoldings)
        if pruned != plan {
            plan = pruned
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
