//
//  SettingsView.swift
//  Bittern
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingKey.appearanceMode) private var appearanceModeRaw = AppAppearance.automatic.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Appearance")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
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
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 34)
        }
        .background(BitternTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tint(BitternTheme.blue)
    }

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceModeRaw) ?? .automatic
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
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isSelected ? .white : BitternTheme.blue)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? BitternTheme.blue : BitternTheme.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(appearance.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(BitternTheme.ink)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BitternTheme.blue)
                }
            }
            .padding(14)
            .bitternPanel()
        }
        .buttonStyle(.plain)
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
