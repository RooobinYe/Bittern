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
    @State private var selectedTab = AppTab.portfolio
    @State private var isShowingSettings = false
    @State private var lensMotion = AllocationLensMotion()
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
                saveCachedSnapshot: dependencies.saveCachedSnapshot,
                deleteCachedSnapshot: dependencies.deleteCachedSnapshot,
                networkMonitor: dependencies.networkMonitor,
                warmCachedLogos: { snapshot in
                    await dependencies.logoSource.warmCachedLogos(for: snapshot)
                }
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
        // Scrolling down shrinks the bar to the current tab in the corner,
        // so the holdings get the full height; scrolling up brings it back.
        .tabBarMinimizeBehavior(.onScrollDown)
        // Above the tab bar and navigation bar, so the dragged lens floats over both.
        .overlay { LiftedAllocationLens(motion: lensMotion) }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .portfolio {
                lensMotion.reset()
            }
        }
        .onChange(of: isShowingSettings) { _, showing in
            if showing {
                lensMotion.reset()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(credentialsStore: credentialsStore, viewModel: viewModel)
        }
        .environment(\.portfolioRepository, repository)
        .environment(\.logoSource, logoSource)
        .environment(\.allocationLensMotion, lensMotion)
        .task {
            await viewModel.bootstrap()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                lensMotion.reset()
                viewModel.sceneDidEnterBackground()
            case .active:
                viewModel.sceneDidBecomeActive()
            case .inactive:
                lensMotion.reset()
            @unknown default:
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
