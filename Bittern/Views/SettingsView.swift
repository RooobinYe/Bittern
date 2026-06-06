//
//  SettingsView.swift
//  Bittern
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingKey.appearanceMode) private var appearanceModeRaw = AppAppearance.automatic.rawValue
    @AppStorage(AppSettingKey.minPriceThreshold) private var minPriceThreshold = 1.0

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

                VStack(alignment: .leading, spacing: 14) {
                    Text("Filters")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(BitternTheme.ink)
                }

                MinPriceRow(threshold: $minPriceThreshold)
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

private struct MinPriceRow: View {
    @Binding var threshold: Double

    private var formattedThreshold: String {
        PortfolioFormat.price(threshold)
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "tag")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(BitternTheme.blue)
                .frame(width: 38, height: 38)
                .background(BitternTheme.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Minimum Market Value")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(BitternTheme.ink)

                Text(threshold == 0 ? "Show all holdings" : "Hide holdings below \(formattedThreshold)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(BitternTheme.secondaryInk)
            }

            Spacer()

            TextField("1.00", value: $threshold, format: .number.precision(.fractionLength(0...2)))
                .font(.system(size: 17, weight: .bold, design: .rounded))
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
