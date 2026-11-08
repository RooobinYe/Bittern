//
//  SettingsView.swift
//  Bittern
//
//  The minimum market value, the market data server, the SnapTrade
//  connection, its saved credentials and the accounts it brings in, as one
//  form in a sheet.
//

import SwiftUI

struct SettingsView: View {
    let credentialsStore: CredentialsStore
    let viewModel: DashboardViewModel
    @State private var connection: BrokerageConnectionModel
    @State private var isConfirmingClear = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.portfolioRepository) private var repository
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false

    init(credentialsStore: CredentialsStore, viewModel: DashboardViewModel) {
        self.credentialsStore = credentialsStore
        self.viewModel = viewModel
        _connection = State(initialValue: BrokerageConnectionModel(credentialsStore: credentialsStore))
    }

    private var savedCredentials: SnapTradeCredentials? {
        credentialsStore.credentials?.sanitized
    }

    var body: some View {
        NavigationStack {
            Form {
                MinimumMarketValueSection(viewModel: viewModel)
                MarketDataServerSection()

                apiKeySection
                connectSection

                if let savedCredentials, savedCredentials.hasSnapTradeUser {
                    userSection(savedCredentials)
                }

                accountSections

                if savedCredentials != nil {
                    Section {
                        Button("Clear Credentials", role: .destructive) {
                            isConfirmingClear = true
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
            .refreshable {
                await viewModel.fullRefresh()
            }
            .errorToast(message: presentedErrorMessage)
            .confirmationDialog(
                "Clear SnapTrade credentials?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Clear Credentials", role: .destructive) {
                    connection.clear(dashboard: viewModel)
                }
            } message: {
                Text("SnapTrade shows a User Secret only once. After it's cleared, Bittern can't get it back, and saving the API key again creates a new SnapTrade user.")
            }
        }
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        Section {
            LabeledContent("Status", value: statusTitle)

            TitledField(title: "Client ID") {
                TextField("Required", text: $connection.clientId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.none)
                    .accessibilityLabel("Client ID")
            }

            TitledField(title: "Consumer Key") {
                RevealableSecretField(title: "Consumer Key", text: $connection.consumerKey)
            }

            Button {
                Task { await connection.save(using: repository, dashboard: viewModel) }
            } label: {
                ProgressButtonLabel(title: "Save", isInProgress: connection.isSaving)
            }
            .disabled(connection.isSaving)

            if let successMessage = connection.successMessage {
                Label {
                    Text(successMessage)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BitternTheme.positivePerformance)
                }
            }
        } header: {
            Text("SnapTrade API Key")
        } footer: {
            Text(statusFooter)
        }
    }

    private var connectSection: some View {
        Section {
            Button {
                Task { await openConnectionPortal() }
            } label: {
                ProgressButtonLabel(title: "Connect Brokerage", isInProgress: connection.isOpeningPortal)
            }
            .disabled(connection.isOpeningPortal)
        } footer: {
            Text("Opens SnapTrade, where you sign in to your brokerage.")
        }
    }

    private func userSection(_ credentials: SnapTradeCredentials) -> some View {
        Section {
            CredentialValueRow(title: "User ID", value: credentials.userId, isSecret: false)
            CredentialValueRow(title: "User Secret", value: credentials.userSecret, isSecret: true)
        } header: {
            Text("SnapTrade User")
        } footer: {
            Text("Created when you saved the API key. Touch and hold a shown value to copy it.")
        }
    }

    @ViewBuilder
    private var accountSections: some View {
        let providerGroups = ProviderHoldings.groups(
            accounts: viewModel.snapshot?.accounts ?? [],
            holdings: viewModel.thresholdFilteredHoldings
        )
        let holdingColorLookup = BitternTheme.holdingAllocationColors(
            for: viewModel.thresholdFilteredHoldings
        )

        if providerGroups.isEmpty {
            Section("Accounts") {
                ContentUnavailableView(
                    "No Accounts",
                    systemImage: "building.columns",
                    description: Text("Brokerages you connect through SnapTrade appear here.")
                )
            }
        } else {
            ForEach(providerGroups) { group in
                ProviderHoldingsSection(
                    group: group,
                    holdingColorLookup: holdingColorLookup,
                    isPrivacyEnabled: isPrivacyEnabled
                )
            }
        }
    }

    // MARK: - Status

    private var statusTitle: String {
        if savedCredentials?.isComplete == true {
            return "Connected"
        }
        if savedCredentials?.hasAPIKey == true {
            return "Incomplete"
        }
        return "Not Set Up"
    }

    private var statusFooter: String {
        if savedCredentials?.isComplete == true {
            return "Your API key is saved, and Bittern created a SnapTrade user for this device."
        }
        if savedCredentials?.hasAPIKey == true {
            return "Save again to finish creating your SnapTrade user."
        }
        return "Enter the API key from your SnapTrade dashboard. Bittern creates the SnapTrade user for you."
    }

    /// This screen's own errors first, then the dashboard's.
    private var presentedErrorMessage: Binding<String?> {
        Binding(
            get: { connection.errorMessage ?? viewModel.errorMessage },
            set: { newValue in
                connection.errorMessage = newValue
                if newValue == nil {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private func openConnectionPortal() async {
        guard let url = await connection.connectionPortalURL(
            darkMode: colorScheme == .dark,
            using: repository
        ) else {
            return
        }
        openURL(url)
    }
}

/// A button title with a spinner beside it while its work runs.
private struct ProgressButtonLabel: View {
    let title: String
    let isInProgress: Bool

    var body: some View {
        HStack {
            Text(title)
            if isInProgress {
                Spacer()
                ProgressView()
            }
        }
    }
}

/// A field with its title above it, so the title stays once it's filled in.
private struct TitledField<Field: View>: View {
    let title: String
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(BitternTheme.secondaryInk)
                .accessibilityHidden(true)

            field()
        }
    }
}

/// A secret entered as dots, with an eye button that shows it. While it
/// isn't being edited it shows the same fixed-length dots as a saved secret,
/// so neither gives away the secret's length.
private struct RevealableSecretField: View {
    let title: String
    @Binding var text: String
    @State private var isRevealed = false
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField("Required", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    let isMasked = !isEditing && !text.isEmpty
                    // The field stays under the dots with its own dots made
                    // clear, so a tap still starts editing. Hiding it with
                    // opacity would stop it from taking taps.
                    SecureField("Required", text: $text)
                        .foregroundStyle(isMasked ? Color.clear : BitternTheme.ink)
                        .overlay(alignment: .leading) {
                            if isMasked {
                                MaskedSecretText()
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                }
            }
            .focused($isEditing)
            .textContentType(.none)
            .accessibilityLabel(title)

            RevealButton(title: title, isRevealed: $isRevealed)
        }
    }
}

/// A saved credential. Secrets stay masked until the eye button shows them,
/// so they don't end up in a screenshot or screen recording by accident.
private struct CredentialValueRow: View {
    let title: String
    let value: String
    let isSecret: Bool
    @State private var isRevealed = false

    private var isShowingValue: Bool {
        !isSecret || isRevealed
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(BitternTheme.secondaryInk)

                if value.isEmpty {
                    Text(PortfolioFormat.missing)
                        .foregroundStyle(BitternTheme.secondaryInk)
                } else if isShowingValue {
                    // The same font as the Client ID field above it.
                    Text(value)
                        .textSelection(.enabled)
                } else {
                    MaskedSecretText()
                        .accessibilityLabel("Hidden")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if isSecret, !value.isEmpty {
                RevealButton(title: title, isRevealed: $isRevealed)
            }
        }
    }
}

/// A hidden secret: always the same number of dots, whatever its length.
private struct MaskedSecretText: View {
    var body: some View {
        Text(String(repeating: "•", count: 12))
            .lineLimit(1)
    }
}

private struct RevealButton: View {
    let title: String
    @Binding var isRevealed: Bool

    var body: some View {
        Button {
            isRevealed.toggle()
        } label: {
            Image(systemName: isRevealed ? "eye.slash" : "eye")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(BitternTheme.secondaryInk)
        .accessibilityLabel(isRevealed ? "Hide \(title)" : "Show \(title)")
    }
}
