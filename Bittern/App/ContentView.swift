//
//  ContentView.swift
//  Bittern
//
//  Created by 叶桢荣 on 2026/6/6.
//

import SwiftUI

struct ContentView: View {
    private enum AppTab: Hashable {
        case portfolio
        case history
        case contribute
    }

    @State private var credentialsStore: CredentialsStore
    @State private var viewModel: DashboardViewModel
    @State private var wasInBackground = false
    @State private var selectedTab = AppTab.portfolio
    @State private var isShowingSettings = false
    private let repository: any PortfolioRepository
    private let logoSource: LogoSource
    @Environment(\.scenePhase) private var scenePhase

    init(dependencies: AppDependencies) {
        self.init(
            credentialsStore: dependencies.credentialsStore,
            viewModel: DashboardViewModel(
                credentialsStore: dependencies.credentialsStore,
                repository: dependencies.repository,
                loadCachedSnapshot: dependencies.loadCachedSnapshot,
                saveCachedSnapshot: dependencies.saveCachedSnapshot
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
        TabView(selection: $selectedTab) {
            Tab("Portfolio", systemImage: "chart.pie", value: AppTab.portfolio) {
                DashboardView(viewModel: viewModel, showSettings: showSettings)
            }

            Tab("History", systemImage: "chart.xyaxis.line", value: AppTab.history) {
                NavigationStack {
                    PortfolioHistoryView(
                        credentialsStore: credentialsStore,
                        dashboardViewModel: viewModel,
                        connectBrokerage: showSettings
                    )
                }
            }

            Tab("Contribute", systemImage: "dollarsign.arrow.circlepath", value: AppTab.contribute) {
                NavigationStack {
                    ContributionCalculatorView(viewModel: viewModel, connectBrokerage: showSettings)
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(credentialsStore: credentialsStore, viewModel: viewModel)
        }
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

    private func showSettings() {
        isShowingSettings = true
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
