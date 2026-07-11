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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Appearance")
                        .font(.title.bold())
                        .foregroundStyle(BitternTheme.ink)
                }

                VStack(spacing: 10) {
                    ForEach(AppAppearance.allCases) { appearance in
                        AppearanceOptionRow(
                            appearance: appearance,
                            isSelected: currentAppearance == appearance
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                appearanceModeRaw = appearance.rawValue
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Filters")
                        .font(.title.bold())
                        .foregroundStyle(BitternTheme.ink)
                }

                MinPriceRow(threshold: $minPriceThreshold)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Portfolio")
                        .font(.title.bold())
                        .foregroundStyle(BitternTheme.ink)
                }

                NavigationLink {
                    PortfolioHistoryView(credentialsStore: credentialsStore, dashboardViewModel: viewModel)
                } label: {
                    SettingsNavigationRow(
                        title: "History",
                        subtitle: "View total money over time",
                        systemImage: "chart.xyaxis.line"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    PortfolioAccountsView(credentialsStore: credentialsStore, viewModel: viewModel)
                } label: {
                    SettingsNavigationRow(
                        title: "Portfolio Accounts",
                        subtitle: "Manage connected institutions",
                        systemImage: "building.columns"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SnapTradeCredentialsView(credentialsStore: credentialsStore)
                } label: {
                    SettingsNavigationRow(
                        title: "Credentials",
                        subtitle: "View SnapTrade keys",
                        systemImage: "key"
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: settingsMaximumContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
        }
        .background(BitternTheme.background.ignoresSafeArea())
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .toolbar(.visible, for: .navigationBar)
        .tint(BitternTheme.blue)
    }

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceModeRaw) ?? .automatic
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
                            .foregroundStyle(BitternTheme.blue)
                            .frame(width: 38, height: 38)
                            .background(BitternTheme.blue.opacity(0.12))
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
        .toolbar(.visible, for: .navigationBar)
        .tint(BitternTheme.blue)
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

private struct SettingsNavigationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.headline.bold())
                .foregroundStyle(BitternTheme.blue)
                .frame(width: 38, height: 38)
                .background(BitternTheme.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.bold())
                    .foregroundStyle(BitternTheme.ink)

                Text(subtitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BitternTheme.secondaryInk)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.bold())
                .foregroundStyle(BitternTheme.secondaryInk)
        }
        .padding(14)
        .bitternPanel()
    }
}

private struct AppearanceOptionRow: View {
    let appearance: AppAppearance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: appearance.systemImage)
                    .font(.headline.bold())
                    .foregroundStyle(isSelected ? .white : BitternTheme.blue)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? BitternTheme.blue : BitternTheme.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(appearance.title)
                    .font(.headline.bold())
                    .foregroundStyle(BitternTheme.ink)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.bold())
                        .foregroundStyle(BitternTheme.blue)
                }
            }
            .padding(14)
            .bitternPanel()
        }
        .buttonStyle(.plain)
    }
}

private struct MinPriceRow: View {
    @Binding var threshold: Double

    private var formattedThreshold: String {
        PortfolioFormat.price(threshold)
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "tag")
                .font(.headline.bold())
                .foregroundStyle(BitternTheme.blue)
                .frame(width: 38, height: 38)
                .background(BitternTheme.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Minimum Market Value")
                    .font(.headline.bold())
                    .foregroundStyle(BitternTheme.ink)

                Text(threshold == 0 ? "Show all holdings" : "Hide holdings below \(formattedThreshold)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BitternTheme.secondaryInk)
            }

            Spacer()

            TextField("1.00", value: $threshold, format: .number.precision(.fractionLength(0...2)))
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(BitternTheme.ink)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 72)
        }
        .padding(14)
        .bitternPanel()
    }
}

private extension AppAppearance {
    var systemImage: String {
        switch self {
        case .automatic:
            "circle.lefthalf.filled"
        case .light:
            "sun.max"
        case .dark:
            "moon"
        }
    }

}
