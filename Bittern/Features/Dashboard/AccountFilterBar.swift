//
//  AccountFilterBar.swift
//  Bittern
//

import SwiftUI

/// Provider tabs and the privacy toggle. Interactive when given controls;
/// otherwise the same labels laid out for the exported image.
struct AccountFilterBar: View {
    let providerNames: [String]
    let selectedProviderName: String?
    let isPrivacyEnabled: Bool
    let controls: DashboardControls?

    /// Nil is the "All" tab.
    private var tabs: [String?] {
        [nil] + providerNames.map(Optional.some)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let controls {
                    ScrollView(.horizontal, showsIndicators: false) {
                        tabRow { providerName in
                            Button {
                                controls.selectProvider(providerName)
                            } label: {
                                tabLabel(for: providerName)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button(action: controls.togglePrivacy) {
                        PrivacyToggleLabel(isPrivacyEnabled: isPrivacyEnabled)
                    }
                    .accessibilityLabel(isPrivacyEnabled ? "Show values" : "Hide values")
                } else {
                    tabRow { tabLabel(for: $0) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()

                    PrivacyToggleLabel(isPrivacyEnabled: isPrivacyEnabled)
                }
            }

            Divider()
                .frame(height: 1)
                .overlay(BitternTheme.softLine)
        }
    }

    private func tabRow<Tab: View>(
        @ViewBuilder tab: @escaping (String?) -> Tab
    ) -> some View {
        HStack(spacing: 20) {
            ForEach(tabs, id: \.self) { providerName in
                tab(providerName)
            }
        }
        .padding(.trailing, 4)
    }

    private func tabLabel(for providerName: String?) -> AccountTabLabel {
        AccountTabLabel(
            title: providerName ?? "All",
            isSelected: selectedProviderName == providerName
        )
    }
}

struct AccountTabLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.title3.weight(isSelected ? .bold : .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .foregroundStyle(isSelected ? BitternTheme.ink : BitternTheme.secondaryInk)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(BitternTheme.accent)
                        .frame(height: 2)
                        .offset(y: 1)
                }
            }
    }
}

struct PrivacyToggleLabel: View {
    let isPrivacyEnabled: Bool

    var body: some View {
        Image(systemName: isPrivacyEnabled ? "eye.slash" : "eye")
            .font(.headline.weight(.semibold))
            .foregroundStyle(BitternTheme.secondaryInk)
            .frame(width: 30, height: 38)
    }
}
