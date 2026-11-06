//
//  BrokerageConnectionModel.swift
//  Bittern
//

import Foundation
import Observation
import OSLog

/// Saving the SnapTrade API key, registering this device's SnapTrade user
/// and opening the brokerage connection portal.
@MainActor
@Observable
final class BrokerageConnectionModel {
    var clientId: String
    var consumerKey: String
    var errorMessage: String?
    private(set) var successMessage: String?
    private(set) var isSaving = false
    private(set) var isOpeningPortal = false

    private let credentialsStore: CredentialsStore

    init(credentialsStore: CredentialsStore) {
        self.credentialsStore = credentialsStore
        let credentials = credentialsStore.credentials ?? .empty
        clientId = credentials.clientId
        consumerKey = credentials.consumerKey
    }

    /// Registers the user if needed, then reloads the portfolio with it.
    func save(using repository: any PortfolioRepository, dashboard: DashboardViewModel) async {
        guard !isSaving else {
            AppLog.credentials.debug("Save credentials skipped because a save is already running")
            return
        }

        isSaving = true
        do {
            _ = try await registeredCredentials(using: repository)
            await dashboard.fullRefresh()
            isSaving = false
            errorMessage = nil
            successMessage = "Credentials saved successfully."
            try? await Task.sleep(for: .seconds(3))
            successMessage = nil
        } catch {
            isSaving = false
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "SnapTrade credentials couldn’t be saved. Please try again."
            )
            AppLog.credentials.error("Save credentials failed: \(AppLog.describe(error))")
        }
    }

    /// The SnapTrade page where a brokerage is connected, or nil after
    /// reporting why it couldn't be opened.
    func connectionPortalURL(
        darkMode: Bool,
        using repository: any PortfolioRepository
    ) async -> URL? {
        guard !isOpeningPortal else { return nil }

        isOpeningPortal = true
        defer { isOpeningPortal = false }

        do {
            let credentials = try await registeredCredentials(using: repository)
            return try await repository.connectionPortalURL(credentials: credentials, darkMode: darkMode)
        } catch {
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "The brokerage connection portal couldn’t be opened. Please try again."
            )
            AppLog.credentials.error("Opening connection portal failed: \(AppLog.describe(error))")
            return nil
        }
    }

    /// Deletes the credentials and the cached portfolio. SnapTrade creates the
    /// user secret only once, so this can't be undone from the app.
    func clear(dashboard: DashboardViewModel) {
        do {
            try PortfolioCache.clear()
            try credentialsStore.clear()
            clientId = ""
            consumerKey = ""
            errorMessage = nil
            Task { await dashboard.fullRefresh() }
        } catch {
            errorMessage = UserFacingError.message(
                for: error,
                fallback: "SnapTrade credentials couldn’t be cleared. Please try again."
            )
            AppLog.credentials.error("Clearing credentials failed: \(AppLog.describe(error))")
        }
    }

    /// The saved credentials when they belong to the entered API key;
    /// otherwise a newly registered user, saved before it is returned.
    private func registeredCredentials(
        using repository: any PortfolioRepository
    ) async throws -> SnapTradeCredentials {
        errorMessage = nil

        let apiKey = SnapTradeCredentials.apiKey(clientId: clientId, consumerKey: consumerKey)
        guard apiKey.hasAPIKey else {
            throw BrokerageConnectionError.missingAPIKey
        }

        if let stored = credentialsStore.credentials?.sanitized,
           stored.hasSameAPIKey(as: apiKey),
           stored.hasSnapTradeUser {
            return stored
        }

        let credentials = try await repository.registerUser(apiKey: apiKey)
        try credentialsStore.save(credentials)
        return credentials
    }
}

enum BrokerageConnectionError: LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your SnapTrade Client ID and Consumer Key first."
        }
    }
}
