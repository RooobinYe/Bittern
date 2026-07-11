//
//  ContentView.swift
//  Bittern
//
//  Created by 叶桢荣 on 2026/6/6.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var credentialsStore: CredentialsStore
    @StateObject private var viewModel: DashboardViewModel
    @State private var wasInBackground = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettingKey.appearanceMode) private var appearanceModeRaw = AppAppearance.automatic.rawValue

    init() {
        let credentialsStore = CredentialsStore()
        #if DEBUG
        DebugSnapTradeCredentialsInjector.injectIfConfigured(into: credentialsStore)
        #endif
        _credentialsStore = StateObject(wrappedValue: credentialsStore)
        _viewModel = StateObject(wrappedValue: DashboardViewModel(credentialsStore: credentialsStore))
    }

    var body: some View {
        DashboardView(viewModel: viewModel, credentialsStore: credentialsStore)
            .fontDesign(.rounded)
            .preferredColorScheme(currentAppearance.colorScheme)
            .task {
                await viewModel.refresh()
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
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
