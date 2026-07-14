//
//  PortfolioAccountsView.swift
//  Bittern
//

import SwiftUI
import OSLog

struct PortfolioAccountsView: View {
    @ObservedObject var credentialsStore: CredentialsStore
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    @State private var clientId: String
    @State private var consumerKey: String
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isSavingCredentials = false
    @State private var isOpeningPortal = false
    @AppStorage(AppSettingKey.minPriceThreshold) private var minPriceThreshold = 1.0

    init(credentialsStore: CredentialsStore, viewModel: DashboardViewModel) {
        self.credentialsStore = credentialsStore
        self.viewModel = viewModel

        let credentials = credentialsStore.credentials ?? .empty
        _clientId = State(initialValue: credentials.clientId)
        _consumerKey = State(initialValue: credentials.consumerKey)
    }

    var body: some View {
        ZStack {
            BitternTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SnapTradeSettingsPanel(
                        isConnected: credentialsStore.credentials?.isComplete == true,
                        hasAPIKey: credentialsStore.credentials?.hasAPIKey == true,
                        isSaving: isSavingCredentials,
                        isConnecting: isOpeningPortal,
                        clientId: $clientId,
                        consumerKey: $consumerKey,
                        errorMessage: errorMessage ?? viewModel.errorMessage,
                        successMessage: successMessage,
                        save: save,
                        connect: { Task { await openConnectionPortal() } }
                    )

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(providerGroups) { group in
                            ProviderHoldingsSection(group: group)
                        }

                        if providerGroups.isEmpty {
                            EmptyProvidersView()
                        }
                    }
                }
                .frame(maxWidth: portfolioAccountsMaximumContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 42)
            }
            .contentMargins(.horizontal, 24, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable {
                await refresh()
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    clear()
                } label: {
                    Image(systemName: "trash")
                        .fontWeight(.bold)
                }
                .accessibilityLabel("Clear credentials")
            }
        }
    }

    private var providerGroups: [PortfolioProviderGroup] {
        let accounts = viewModel.snapshot.accounts
        let holdings = viewModel.snapshot.holdings.filter {
            $0.marketValue.map { $0 >= minPriceThreshold } ?? true
        }
        let holdingColorLookup = BitternTheme.holdingAllocationColors(for: holdings)

        let groupedAccounts = Dictionary(grouping: accounts, by: \.providerName)

        return groupedAccounts.map { (name, providerAccounts) in
            let accountIDs = Set(providerAccounts.map(\.id))
            let providerHoldings = holdings
                .filter { accountIDs.contains($0.accountID) }
                .sorted { ($0.marketValue ?? -Double.infinity) > ($1.marketValue ?? -Double.infinity) }
            let hasCompleteMarketValue = providerHoldings.allSatisfy { $0.marketValue != nil }
            let totalMarketValue = hasCompleteMarketValue
                ? providerHoldings.reduce(0) { $0 + ($1.marketValue ?? 0) }
                : nil

            return PortfolioProviderGroup(
                id: name,
                name: name,
                logoURL: providerAccounts.compactMap(\.providerLogoURL).first,
                isDisabled: providerAccounts.contains(where: \.isConnectionDisabled),
                accountCount: providerAccounts.count,
                totalMarketValue: totalMarketValue,
                holdings: providerHoldings,
                holdingColorLookup: holdingColorLookup
            )
        }
        .sorted { ($0.totalMarketValue ?? -Double.infinity) > ($1.totalMarketValue ?? -Double.infinity) }
    }

    private func save() {
        AppLog.credentials.debug("Save credentials tapped")
        Task { await saveCredentials() }
    }

    private func clear() {
        do {
            try credentialsStore.clear()
            clientId = ""
            consumerKey = ""
            errorMessage = nil
            Task { await viewModel.fullRefresh() }
        } catch {
            errorMessage = error.localizedDescription
            AppLog.credentials.error(
                "Clearing credentials failed: \(AppLog.describe(error))"
            )
        }
    }

    private func refresh() async {
        await viewModel.fullRefresh()
    }

    private func openConnectionPortal() async {
        guard !isOpeningPortal else { return }

        isOpeningPortal = true
        defer { isOpeningPortal = false }

        do {
            let credentials = try await ensureRegisteredCredentials()
            let client = SnapTradeClient(credentials: credentials)
            let url = try await client.connectionPortalURL(darkMode: colorScheme == .dark)
            openURL(url)
        } catch {
            errorMessage = error.localizedDescription
            AppLog.credentials.error(
                "Opening connection portal failed: \(AppLog.describe(error))"
            )
        }
    }

    private func saveCredentials() async {
        AppLog.credentials.debug(
            "Save credentials requested isSaving=\(isSavingCredentials, privacy: .public) viewModelIsLoading=\(viewModel.isLoading, privacy: .public) taskCancelled=\(Task.isCancelled, privacy: .public)"
        )

        guard !isSavingCredentials else {
            AppLog.credentials.debug(
                "Save credentials skipped because a save is already running"
            )
            return
        }

        isSavingCredentials = true

        do {
            _ = try await ensureRegisteredCredentials()
            AppLog.credentials.debug(
                "Credentials registered; starting portfolio refresh"
            )
            await refresh()
            isSavingCredentials = false
            errorMessage = nil
            AppLog.credentials.debug(
                "Save credentials completed portfolio refresh"
            )
            successMessage = "Credentials saved successfully."
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            successMessage = nil
        } catch {
            isSavingCredentials = false
            errorMessage = error.localizedDescription
            AppLog.credentials.error(
                "Save credentials failed: \(AppLog.describe(error))"
            )
        }
    }

    private func ensureRegisteredCredentials() async throws -> SnapTradeCredentials {
        errorMessage = nil

        let apiCredentials = currentAPICredentials
        guard apiCredentials.hasAPIKey else {
            throw SnapTradeSetupError.missingAPIKey
        }

        if let stored = credentialsStore.credentials?.sanitized,
           stored.clientId == apiCredentials.clientId,
           stored.consumerKey == apiCredentials.consumerKey,
           stored.hasSnapTradeUser {
            return stored
        }

        let userId = makeUserID(clientId: apiCredentials.clientId)
        let registeredUser = try await SnapTradeClient(credentials: apiCredentials)
            .registerUser(userId: userId)
        let credentials = SnapTradeCredentials(
            clientId: apiCredentials.clientId,
            consumerKey: apiCredentials.consumerKey,
            userId: registeredUser.userId,
            userSecret: registeredUser.userSecret
        )
        try credentialsStore.save(credentials)
        return credentials
    }

    private var currentAPICredentials: SnapTradeCredentials {
        SnapTradeCredentials(
            clientId: clientId,
            consumerKey: consumerKey,
            userId: "",
            userSecret: ""
        )
    }

    private func makeUserID(clientId: String) -> String {
        let normalized = clientId.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return "bittern-personal-\(String(normalized))"
    }

}

private let portfolioAccountsMaximumContentWidth: CGFloat = 900

private enum SnapTradeSetupError: LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your SnapTrade Client ID and Consumer Key first."
        }
    }
}

private struct PortfolioProviderGroup: Identifiable {
    let id: String
    let name: String
    let logoURL: URL?
    let isDisabled: Bool
    let accountCount: Int
    let totalMarketValue: Double?
    let holdings: [PortfolioHolding]
    let holdingColorLookup: [String: Color]
}

private struct SnapTradeSettingsPanel: View {
    let isConnected: Bool
    let hasAPIKey: Bool
    let isSaving: Bool
    let isConnecting: Bool
    @Binding var clientId: String
    @Binding var consumerKey: String
    let errorMessage: String?
    let successMessage: String?
    let save: () -> Void
    let connect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: isConnected ? "checkmark.seal.fill" : "link.badge.plus")
                    .font(.headline.bold())
                    .foregroundStyle(statusColor)
                    .frame(width: 38, height: 38)
                    .background(statusColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("SnapTrade")
                        .font(.headline.bold())
                        .foregroundStyle(BitternTheme.ink)

                    Text(statusText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BitternTheme.secondaryInk)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                PortfolioCredentialField(title: "Client ID", text: $clientId, isSecure: false)
                PortfolioCredentialField(title: "Consumer Key", text: $consumerKey, isSecure: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let successMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(uiColor: .systemGreen))

                    Text(successMessage)
                        .font(.footnote)
                        .foregroundStyle(BitternTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color(uiColor: .systemGreen).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 12) {
                Button(action: save) {
                    Label(isSaving ? "Saving" : "Save", systemImage: isSaving ? "clock.arrow.circlepath" : "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving)

                Button(action: connect) {
                    Label(isConnecting ? "Connecting" : "Connect", systemImage: isConnecting ? "clock.arrow.circlepath" : "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isConnecting)
                .accessibilityLabel("Connect brokerage")
            }
        }
        .padding(15)
        .bitternPanel()
    }

    private var statusText: String {
        if isConnected {
            return "API key saved. SnapTrade user was created automatically."
        }

        if hasAPIKey {
            return "Save again to finish creating the SnapTrade user."
        }

        return "Add API credentials. User ID and User Secret are created automatically."
    }

    private var statusColor: Color {
        isConnected ? Color(uiColor: .systemGreen) : BitternTheme.warning
    }
}

private struct ProviderHoldingsSection: View {
    let group: PortfolioProviderGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(BitternTheme.secondaryInk)

                Text(group.name)
                    .font(.title2.bold())
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if group.isDisabled {
                    Text("Disabled")
                        .font(.caption2.bold())
                        .foregroundStyle(BitternTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BitternTheme.warning.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.bottom, 15)

            if group.holdings.isEmpty {
                Text("\(group.accountCount) account\(group.accountCount == 1 ? "" : "s") connected")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .padding(.bottom, 15)
            } else {
                ForEach(group.holdings) { holding in
                    ProviderHoldingRow(
                        holding: holding,
                        providerName: group.name,
                        color: group.holdingColorLookup[holding.id] ?? BitternTheme.allocationColor(at: 0)
                    )
                }
            }
        }
    }
}

private struct ProviderHoldingRow: View {
    let holding: PortfolioHolding
    let providerName: String
    let color: Color

    private var unitLabel: String {
        providerName.lowercased().contains("binance") ? "tokens" : "shares"
    }

    private var formattedQuantity: String {
        unitLabel == "tokens"
            ? PortfolioFormat.tokens(holding.quantity)
            : PortfolioFormat.shares(holding.quantity)
    }

    var body: some View {
        HStack(spacing: 12) {
            HoldingSymbolIcon(
                symbol: holding.symbol,
                logoURL: holding.logoURL,
                color: color,
                size: 40
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(holding.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)

                Text(holding.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(holding.marketValue.map { PortfolioFormat.wholeMoney($0, currencyCode: holding.currencyCode) } ?? "N/A")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(formattedQuantity) \(unitLabel)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(BitternTheme.softLine.opacity(0.7))
        }
    }
}

private struct EmptyProvidersView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "building.columns")
                .font(.title2.bold())
                .foregroundStyle(BitternTheme.secondaryInk)

            Text("No providers yet")
                .font(.headline.bold())
                .foregroundStyle(BitternTheme.ink)

            Text("Connect a brokerage through SnapTrade to see providers here.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BitternTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(16)
        .bitternPanel()
    }
}

private struct PortfolioCredentialField: View {
    let title: String
    @Binding var text: String
    let isSecure: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BitternTheme.secondaryInk)

            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.body)
            .textContentType(.none)
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(BitternTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BitternTheme.softLine, lineWidth: 1)
            }
        }
    }
}
