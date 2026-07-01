#if DEBUG
import Foundation

enum DebugSnapTradeCredentialsInjector {
    private enum EnvironmentKey {
        static let clientId = "BITTERN_SNAPTRADE_CLIENT_ID"
        static let consumerKey = "BITTERN_SNAPTRADE_CONSUMER_KEY"
        static let userId = "BITTERN_SNAPTRADE_USER_ID"
        static let userSecret = "BITTERN_SNAPTRADE_USER_SECRET"
    }

    static func injectIfConfigured(
        into credentialsStore: CredentialsStore,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let credentials = credentials(from: environment) else {
            logMissingConfiguration(environment: environment)
            return
        }

        guard credentialsStore.credentials?.sanitized != credentials else {
            debugLog("environment credentials already saved")
            return
        }

        do {
            try credentialsStore.save(credentials)
            debugLog("saved complete credentials from environment")
        } catch {
            let nsError = error as NSError
            debugLog("failed to save environment credentials domain=\(nsError.domain) code=\(nsError.code) message=\"\(error.localizedDescription)\"")
        }
    }

    static func credentials(from environment: [String: String]) -> SnapTradeCredentials? {
        let credentials = SnapTradeCredentials(
            clientId: environment[EnvironmentKey.clientId] ?? "",
            consumerKey: environment[EnvironmentKey.consumerKey] ?? "",
            userId: environment[EnvironmentKey.userId] ?? "",
            userSecret: environment[EnvironmentKey.userSecret] ?? ""
        )
        .sanitized

        return credentials.isComplete ? credentials : nil
    }

    private static func logMissingConfiguration(environment: [String: String]) {
        let keys = [
            EnvironmentKey.clientId,
            EnvironmentKey.consumerKey,
            EnvironmentKey.userId,
            EnvironmentKey.userSecret
        ]

        guard keys.contains(where: { environment[$0]?.isTrimmedNonEmpty == true }) else {
            return
        }

        let missingKeys = keys.filter { environment[$0]?.isTrimmedNonEmpty != true }
        debugLog("environment credentials ignored because missing keys=\(missingKeys.joined(separator: ","))")
    }

    private static func debugLog(_ message: String) {
        print("[DebugSnapTradeCredentialsInjector] \(message)")
    }
}

private extension String {
    var isTrimmedNonEmpty: Bool {
        !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
#endif
