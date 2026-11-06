//
//  SnapTradeSettingsPanel.swift
//  Bittern
//

import SwiftUI

struct SnapTradeSettingsPanel: View {
    let isConnected: Bool
    let hasAPIKey: Bool
    let isSaving: Bool
    let isConnecting: Bool
    @Binding var clientId: String
    @Binding var consumerKey: String
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
