//
//  SettingsView.swift
//  Bittern
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var credentialsStore: CredentialsStore
    @ObservedObject var viewModel: DashboardViewModel
    @AppStorage(AppSettingKey.appearanceMode) private var appearanceModeRaw = AppAppearance.automatic.rawValue
    @AppStorage(AppSettingKey.minPriceThreshold) private var minPriceThreshold = 1.0

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceModeRaw) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title)
                            .tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowInsets(.vertical, 0)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows the appearance selected for your iPhone.")
            }

            Section {
                NavigationLink {
                    MinimumMarketValueView(
                        threshold: $minPriceThreshold,
                        currencyCode: viewModel.visibleSnapshot.currencyCode
                    )
                } label: {
                    SettingsValueLabel(
                        title: "Minimum Market Value",
                        value: formattedMinimumMarketValue
                    )
                }
            } header: {
                Text("Filters")
            } footer: {
                Text("Holdings below this value are hidden from your portfolio.")
            }

            Section {
                NavigationLink {
                    PortfolioHistoryView(credentialsStore: credentialsStore, dashboardViewModel: viewModel)
                        .navigationTitle("History")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    SettingsNavigationLabel(
                        title: "History",
                        systemImage: "chart.xyaxis.line"
                    )
                }

                NavigationLink {
                    PortfolioAccountsView(credentialsStore: credentialsStore, viewModel: viewModel)
                        .navigationTitle("Portfolio Accounts")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    SettingsNavigationLabel(
                        title: "Portfolio Accounts",
                        systemImage: "building.columns",
                        value: connectedAccountsValue
                    )
                }

                NavigationLink {
                    SnapTradeCredentialsView(credentialsStore: credentialsStore)
                } label: {
                    SettingsNavigationLabel(
                        title: "Credentials",
                        systemImage: "key"
                    )
                }
            } header: {
                Text("Portfolio")
            }
        }
        .fontDesign(.default)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
    }

    private var formattedMinimumMarketValue: String {
        PortfolioFormat.price(
            max(minPriceThreshold, 0),
            currencyCode: viewModel.visibleSnapshot.currencyCode
        )
    }

    private var connectedAccountsValue: String {
        let count = viewModel.snapshot.accounts.count
        return count == 0 ? "None" : "\(count)"
    }
}

private struct SnapTradeCredentialsView: View {
    @ObservedObject var credentialsStore: CredentialsStore

    private var credentials: SnapTradeCredentials? {
        credentialsStore.credentials?.sanitized
    }

    var body: some View {
        Form {
            if let credentials {
                Section {
                    CredentialsValueRow(title: "Client ID", value: credentials.clientId)
                    CredentialsValueRow(title: "Consumer Key", value: credentials.consumerKey)
                    CredentialsValueRow(title: "User ID", value: credentials.userId)
                    CredentialsValueRow(title: "User Key", value: credentials.userSecret)
                } header: {
                    Text("SnapTrade")
                } footer: {
                    Text("Touch and hold a value to select or copy it.")
                }
            } else {
                Section {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "key.slash")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(BitternTheme.accent)
                            .frame(width: 24)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("No Credentials")

                            Text("Connect SnapTrade to create saved credentials.")
                                .font(.footnote)
                                .foregroundStyle(BitternTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .fontDesign(.default)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Credentials")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct CredentialsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(BitternTheme.secondaryInk)

            Text(value.isEmpty ? "N/A" : value)
                .font(.footnote.monospaced())
                .foregroundStyle(BitternTheme.ink)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

private struct SettingsNavigationLabel: View {
    let title: String
    let systemImage: String
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(BitternTheme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(title)
                .foregroundStyle(BitternTheme.ink)

            Spacer(minLength: 12)

            if let value {
                Text(value)
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
            }
        }
    }
}

private struct SettingsValueLabel: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(BitternTheme.secondaryInk)
        }
    }
}

private struct MinimumMarketValueView: View {
    @Binding var threshold: Double
    let currencyCode: String
    @FocusState private var isValueFocused: Bool

    var body: some View {
        Form {
            Section {
                LabeledContent("Minimum Value") {
                    HStack(spacing: 8) {
                        Text(currencyCode)
                            .font(.subheadline)
                            .foregroundStyle(BitternTheme.secondaryInk)

                        TextField(
                            "0.00",
                            value: $threshold,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .font(.body.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .focused($isValueFocused)
                        .frame(minWidth: 72, maxWidth: 112)
                    }
                }
            } footer: {
                Text("Holdings with a market value below this amount are hidden throughout the app. Enter 0 to show every holding.")
            }
        }
        .fontDesign(.default)
        .navigationTitle("Minimum Value")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done") {
                    normalizeThreshold()
                    isValueFocused = false
                }
            }
        }
        .onDisappear(perform: normalizeThreshold)
    }

    private func normalizeThreshold() {
        if threshold.isFinite {
            threshold = max(threshold, 0)
        } else {
            threshold = 0
        }
    }
}
