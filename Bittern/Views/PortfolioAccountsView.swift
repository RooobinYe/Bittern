//
//  PortfolioAccountsView.swift
//  Bittern
//

import SwiftUI

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
                        clientId: $clientId,
                        consumerKey: $consumerKey,
                        errorMessage: errorMessage ?? viewModel.errorMessage,
                        successMessage: successMessage,
                        save: save,
                        connect: { Task { await openConnectionPortal() } },
                        clear: clear
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
            .refreshable {
                await refresh()
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await openConnectionPortal() }
                } label: {
                    Image(systemName: isOpeningPortal ? "clock.arrow.circlepath" : "link")
                        .fontWeight(.bold)
                        .foregroundStyle(BitternTheme.loss)
                }
                .disabled(isOpeningPortal)
                .accessibilityLabel("Open SnapTrade connection portal")
            }
        }
        .tint(BitternTheme.blue)
    }

    private var providerGroups: [PortfolioProviderGroup] {
        let accounts = viewModel.snapshot.accounts
        let holdings = viewModel.snapshot.holdings

        let groupedAccounts = Dictionary(grouping: accounts, by: \.providerName)

        return groupedAccounts.map { (name, providerAccounts) in
            let accountIDs = Set(providerAccounts.map(\.id))
            let providerHoldings = holdings
                .filter { accountIDs.contains($0.accountID) && ($0.marketValue.map { $0 >= minPriceThreshold } ?? true) }
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
                holdings: providerHoldings
            )
        }
        .sorted { ($0.totalMarketValue ?? -Double.infinity) > ($1.totalMarketValue ?? -Double.infinity) }
    }

    private func save() {
        debugLog("save tapped")
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
        }
    }

    private func saveCredentials() async {
        debugLog(
            "saveCredentials requested isSaving=\(isSavingCredentials) viewModel.isLoading=\(viewModel.isLoading) taskCancelled=\(Task.isCancelled)"
        )

        guard !isSavingCredentials else {
            debugLog("saveCredentials skipped because isSavingCredentials is already true")
            return
        }

        isSavingCredentials = true

        do {
            _ = try await ensureRegisteredCredentials()
            debugLog("saveCredentials registered credentials; starting refresh")
            await refresh()
            isSavingCredentials = false
            errorMessage = nil
            debugLog("saveCredentials completed refresh successfully")
            successMessage = "Credentials saved successfully."
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            successMessage = nil
        } catch {
            isSavingCredentials = false
            errorMessage = error.localizedDescription
            debugLog("saveCredentials failed \(debugDescription(for: error))")
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

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[PortfolioAccountsView] \(message)")
        #endif
    }

    private func debugDescription(for error: Error) -> String {
        let nsError = error as NSError
        return "type=\(type(of: error)) domain=\(nsError.domain) code=\(nsError.code) taskCancelled=\(Task.isCancelled) message=\"\(error.localizedDescription)\""
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
}

private struct SnapTradeSettingsPanel: View {
    let isConnected: Bool
    let hasAPIKey: Bool
    let isSaving: Bool
    @Binding var clientId: String
    @Binding var consumerKey: String
    let errorMessage: String?
    let successMessage: String?
    let save: () -> Void
    let connect: () -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: isConnected ? "checkmark.seal.fill" : "link.badge.plus")
                    .font(.headline.bold())
                    .foregroundStyle(isConnected ? BitternTheme.gain : BitternTheme.gold)
                    .frame(width: 38, height: 38)
                    .background((isConnected ? BitternTheme.gain : BitternTheme.gold).opacity(0.12))
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
                    .foregroundStyle(BitternTheme.loss)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let successMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BitternTheme.gain)

                    Text(successMessage)
                        .font(.footnote)
                        .foregroundStyle(BitternTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(BitternTheme.gain.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 12) {
                Button(action: save) {
                    Label(isSaving ? "Saving" : "Save", systemImage: isSaving ? "clock.arrow.circlepath" : "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PortfolioPrimaryButtonStyle())
                .disabled(isSaving)

                Button(action: connect) {
                    Image(systemName: "plus")
                        .frame(width: 48)
                }
                .buttonStyle(PortfolioConnectButtonStyle())
                .accessibilityLabel("Connect brokerage")

                Button(action: clear) {
                    Image(systemName: "trash")
                        .frame(width: 48)
                }
                .buttonStyle(PortfolioDeleteButtonStyle())
                .accessibilityLabel("Clear credentials")
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
                        .foregroundStyle(BitternTheme.loss)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BitternTheme.loss.opacity(0.12))
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
                    ProviderHoldingRow(holding: holding, providerName: group.name)
                }
            }
        }
    }
}

private struct ProviderHoldingRow: View {
    let holding: PortfolioHolding
    let providerName: String

    private var unitLabel: String {
        providerName.lowercased().contains("binance") ? "tokens" : "shares"
    }

    private var formattedQuantity: String {
        unitLabel == "tokens"
            ? PortfolioFormat.tokens(holding.quantity)
            : PortfolioFormat.shares(holding.quantity)
    }

    var body: some View {
        HStack(spacing: 14) {
            ProviderSymbolAvatar(symbol: holding.symbol)

            VStack(alignment: .leading, spacing: 4) {
                Text(holding.symbol)
                    .font(.title3.bold())
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
                    .font(.headline.bold().monospacedDigit())
                    .foregroundStyle(BitternTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(formattedQuantity) \(unitLabel)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(BitternTheme.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(BitternTheme.softLine)
        }
    }
}

private struct ProviderSymbolAvatar: View {
    let symbol: String

    var body: some View {
        Text(String(symbol.prefix(4)))
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(avatarColor)
            .clipShape(Circle())
    }

    private var avatarColor: Color {
        let palette = BitternTheme.allocationColors
        let sum = symbol.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
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

private struct PortfolioPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(height: 48)
            .background(BitternTheme.blue.opacity(configuration.isPressed ? 0.80 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PortfolioDeleteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(BitternTheme.loss)
            .frame(height: 48)
            .background(BitternTheme.loss.opacity(configuration.isPressed ? 0.16 : 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PortfolioConnectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(height: 48)
            .background(Color(uiColor: .systemPurple).opacity(configuration.isPressed ? 0.80 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
