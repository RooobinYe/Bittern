//
//  RefreshFailure.swift
//  Bittern
//
//  What a failed load means for what the app does next: wait for the
//  network, try again, ask the user to fix something, or give up.
//

import Foundation

/// A problem only the user can fix, shown as a banner over the data that is
/// still there, or as the error page when there is none.
struct PortfolioAttention: Equatable {
    enum Reason: Equatable {
        /// SnapTrade refused the saved credentials.
        case credentialsRejected
        /// A brokerage connection is disabled, so SnapTrade holds its
        /// accounts as they were when it last synced.
        case connectionDisabled(providerNames: [String])
    }

    let reason: Reason

    var title: String {
        switch reason {
        case .credentialsRejected:
            "Holdings couldn’t be refreshed"
        case .connectionDisabled(let providerNames):
            providerNames.count == 1
                ? "\(providerNames[0]) holdings couldn’t be refreshed"
                : "Holdings couldn’t be refreshed"
        }
    }

    var message: String {
        switch reason {
        case .credentialsRejected:
            "SnapTrade didn’t accept the saved credentials."
        case .connectionDisabled(let providerNames):
            providerNames.count == 1
                ? "The brokerage connection is disabled."
                : "Brokerage connections for \(providerNames.joined(separator: ", ")) are disabled."
        }
    }

    /// The disabled connections among `snapshot`'s accounts, if any.
    static func disabledConnections(in snapshot: PortfolioSnapshot) -> PortfolioAttention? {
        let names = snapshot.accounts
            .filter(\.isConnectionDisabled)
            .map(\.providerName)
        var seen: Set<String> = []
        let unique = names.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { return nil }
        return PortfolioAttention(reason: .connectionDisabled(providerNames: unique))
    }
}

enum RefreshFailure: Equatable {
    /// There is no network path. Nothing is retried until one returns.
    case offline
    /// Likely to pass on its own: a timeout, a dropped connection, a busy
    /// or throttling server. Retried with backoff.
    case transient
    /// The user has to change something; retrying won't help.
    case needsAction(PortfolioAttention)
    /// Anything else, such as a response that can't be read. Not retried.
    case permanent

    init(_ error: any Error) {
        switch error {
        case let urlError as URLError:
            self = Self.classify(urlError)
        case let snapTradeError as SnapTradeError:
            self = Self.classify(snapTradeError)
        case let marketDataError as TradingViewError:
            self = Self.classify(marketDataError)
        default:
            self = .permanent
        }
    }

    var isNetworkFailure: Bool {
        self == .offline || self == .transient
    }

    private static func classify(_ error: URLError) -> RefreshFailure {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .callIsActive:
            .offline
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .secureConnectionFailed, .resourceUnavailable, .badServerResponse,
             .cannotLoadFromNetwork, .backgroundSessionWasDisconnected:
            .transient
        default:
            .permanent
        }
    }

    /// 401 and 403 are SnapTrade turning the credentials down, as are its
    /// error codes 1076 (signature not verified) and 1083 (user ID or
    /// secret not valid) under any status.
    private static func classify(_ error: SnapTradeError) -> RefreshFailure {
        guard case .httpStatus(let status, let body) = error else { return .permanent }
        if status == 401 || status == 403 || body.contains("1076") || body.contains("1083") {
            return .needsAction(PortfolioAttention(reason: .credentialsRejected))
        }
        return isTransient(status: status) ? .transient : .permanent
    }

    private static func classify(_ error: TradingViewError) -> RefreshFailure {
        switch error {
        // A dropped or silent socket, or every quote failing at once: the
        // network or TradingView is having a moment.
        case .connectionClosed, .connectionStalled, .timedOut, .noMarketData,
             .providerError, .malformedFrame:
            .transient
        case .emptySymbols, .invalidSymbol, .notEnoughPoints, .invalidChartData,
             .currencyMismatch:
            .permanent
        }
    }

    private static func isTransient(status: Int) -> Bool {
        status == 408 || status == 429 || (500..<600).contains(status)
    }
}
