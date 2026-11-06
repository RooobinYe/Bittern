//
//  ContentView.swift
//  Bittern
//
//  Created by 叶桢荣 on 2026/6/6.
//

import SwiftUI

struct ContentView: View {
    @State private var credentialsStore: CredentialsStore
    @State private var viewModel: DashboardViewModel
    @State private var wasInBackground = false
    private let repository: any PortfolioRepository
    private let logoSource: LogoSource
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettingKey.appearanceMode) private var appearanceModeRaw = AppAppearance.automatic.rawValue

    init(dependencies: AppDependencies) {
        self.init(
            credentialsStore: dependencies.credentialsStore,
            viewModel: DashboardViewModel(
                credentialsStore: dependencies.credentialsStore,
                repository: dependencies.repository
            ),
            repository: dependencies.repository,
            logoSource: dependencies.logoSource
        )
    }

    init(
        credentialsStore: CredentialsStore,
        viewModel: DashboardViewModel,
        repository: any PortfolioRepository,
        logoSource: LogoSource
    ) {
        _credentialsStore = State(initialValue: credentialsStore)
        _viewModel = State(initialValue: viewModel)
        self.repository = repository
        self.logoSource = logoSource
    }

    var body: some View {
        DashboardView(viewModel: viewModel, credentialsStore: credentialsStore)
            .fontDesign(.rounded)
            .preferredColorScheme(currentAppearance.colorScheme)
            .environment(\.portfolioRepository, repository)
            .environment(\.logoSource, logoSource)
            .task {
                await viewModel.bootstrap()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    wasInBackground = true
                case .active where wasInBackground:
                    wasInBackground = false
                    Task {
                        await viewModel.refresh()
                    }
                default:
                    break
                }
            }
    }

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceModeRaw) ?? .automatic
    }
}

#if DEBUG
#Preview {
    let credentialsStore = PreviewSupport.credentialsStore()
    ContentView(
        credentialsStore: credentialsStore,
        viewModel: PreviewSupport.dashboardViewModel(credentialsStore: credentialsStore),
        repository: UnavailablePortfolioRepository(),
        logoSource: .none
    )
}
#endif
