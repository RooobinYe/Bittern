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
            Section("Appearance") {
                Picker("Appearance", selection: $appearanceModeRaw) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title)
                            .tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Filters") {
                MinPriceRow(threshold: $minPriceThreshold)
            }

            Section("Portfolio") {
                NavigationLink {
                    PortfolioHistoryView(credentialsStore: credentialsStore, dashboardViewModel: viewModel)
                } label: {
                    SettingsNavigationLabel(
                        title: "History",
                        subtitle: "View total money over time",
                        systemImage: "chart.xyaxis.line"
                    )
                }

                NavigationLink {
                    PortfolioAccountsView(credentialsStore: credentialsStore, viewModel: viewModel)
                } label: {
                    SettingsNavigationLabel(
                        title: "Portfolio Accounts",
                        subtitle: "Manage connected institutions",
                        systemImage: "building.columns"
                    )
                }

                NavigationLink {
                    SnapTradeCredentialsView(credentialsStore: credentialsStore)
                } label: {
                    SettingsNavigationLabel(
                        title: "Credentials",
                        subtitle: "View SnapTrade keys",
                        systemImage: "key"
                    )
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct SnapTradeCredentialsView: View {
    @ObservedObject var credentialsStore: CredentialsStore

    private var credentials: SnapTradeCredentials? {
        credentialsStore.credentials?.sanitized
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let credentials {
                    CredentialsValueRow(title: "Client ID", value: credentials.clientId)
                    CredentialsValueRow(title: "Consumer Key", value: credentials.consumerKey)
                    CredentialsValueRow(title: "User ID", value: credentials.userId)
                    CredentialsValueRow(title: "User Key", value: credentials.userSecret)
                } else {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "key.slash")
                            .font(.headline.bold())
                            .foregroundStyle(BitternTheme.accent)
                            .frame(width: 38, height: 38)
                            .background(BitternTheme.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("No Credentials")
                                .font(.headline.bold())
                                .foregroundStyle(BitternTheme.ink)

                            Text("Connect SnapTrade to create saved credentials.")
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
            .frame(maxWidth: settingsMaximumContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
        }
        .background(BitternTheme.background.ignoresSafeArea())
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Credentials")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
    }
}

private let settingsMaximumContentWidth: CGFloat = 720

private struct CredentialsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(BitternTheme.secondaryInk)

            Text(value.isEmpty ? "N/A" : value)
                .font(.footnote.monospaced().weight(.semibold))
                .foregroundStyle(BitternTheme.ink)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .bitternPanel()
    }
}

private struct SettingsNavigationLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(BitternTheme.ink)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(BitternTheme.secondaryInk)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(BitternTheme.accent)
        }
    }
}

private struct MinPriceRow: View {
    @Binding var threshold: Double

    private var formattedThreshold: String {
        PortfolioFormat.price(threshold)
    }

    var body: some View {
        LabeledContent {
            TextField("1.00", value: $threshold, format: .number.precision(.fractionLength(0...2)))
                .font(.body.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 72)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Minimum Market Value")

                Text(threshold == 0 ? "Show all holdings" : "Hide holdings below \(formattedThreshold)")
                    .font(.footnote)
                    .foregroundStyle(BitternTheme.secondaryInk)
            }
        }
    }
}
