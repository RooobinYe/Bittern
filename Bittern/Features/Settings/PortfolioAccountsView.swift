//
//  PortfolioAccountsView.swift
//  Bittern
//

import SwiftUI

struct PortfolioAccountsView: View {
    let credentialsStore: CredentialsStore
    @Bindable var viewModel: DashboardViewModel
    @State private var connection: BrokerageConnectionModel
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.portfolioRepository) private var repository
    @AppStorage(AppSettingKey.privacyModeEnabled) private var isPrivacyEnabled = false

    init(credentialsStore: CredentialsStore, viewModel: DashboardViewModel) {
        self.credentialsStore = credentialsStore
        self.viewModel = viewModel
        _connection = State(initialValue: BrokerageConnectionModel(credentialsStore: credentialsStore))
    }

    var body: some View {
        let providerGroups = ProviderHoldings.groups(
            accounts: viewModel.snapshot?.accounts ?? [],
            holdings: viewModel.thresholdFilteredHoldings
        )
        let holdingColorLookup = BitternTheme.holdingAllocationColors(
            for: viewModel.snapshot?.holdings ?? []
        )

        ZStack {
            BitternTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SnapTradeSettingsPanel(
                        isConnected: credentialsStore.credentials?.isComplete == true,
                        hasAPIKey: credentialsStore.credentials?.hasAPIKey == true,
                        isSaving: connection.isSaving,
                        isConnecting: connection.isOpeningPortal,
                        clientId: $connection.clientId,
                        consumerKey: $connection.consumerKey,
                        successMessage: connection.successMessage,
                        save: {
                            Task { await connection.save(using: repository, dashboard: viewModel) }
                        },
                        connect: {
                            Task { await openConnectionPortal() }
                        }
                    )

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(providerGroups) { group in
                            ProviderHoldingsSection(
                                group: group,
                                holdingColorLookup: holdingColorLookup,
                                isPrivacyEnabled: isPrivacyEnabled
                            )
                        }

                        if providerGroups.isEmpty {
                            EmptyProvidersView()
                        }
                    }
                }
                .frame(maxWidth: Self.maximumContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 42)
            }
            .contentMargins(.horizontal, 24, for: .scrollContent)
            .softNavigationBarEdge()
            .refreshable {
                await viewModel.fullRefresh()
            }
        }
        .errorToast(message: presentedErrorMessage)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    connection.clear(dashboard: viewModel)
                } label: {
                    Image(systemName: "trash")
                        .fontWeight(.bold)
                }
                .accessibilityLabel("Clear credentials")
            }
        }
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

    private static let maximumContentWidth: CGFloat = 900
}
