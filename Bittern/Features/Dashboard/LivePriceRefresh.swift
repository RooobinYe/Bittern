//
//  LivePriceRefresh.swift
//  Bittern
//
//  How often prices refresh themselves, and how hard a failing load is
//  retried.
//

import Foundation

enum LivePriceRefresh {
    /// How often the prices of holdings in an active session are read
    /// while the app is in the foreground. TradingView pushes every trade to
    /// an open quote session as it happens, so a tick reads prices already
    /// on the device and costs no request; the interval only sets how soon
    /// a change shows.
    static let interval: Duration = .seconds(1)

    /// When no holding is in session: how long to wait before checking
    /// prices and sessions again, unless a known session opens sooner.
    static let idleCheckInterval: Duration = .seconds(15 * 60)

    /// How long launch shows nothing before the skeleton, so a load that
    /// answers at once never flashes it.
    static let skeletonDelay: Duration = .milliseconds(300)

    /// Failed attempts in a row before launch gives up retrying and before
    /// live prices count as no longer current.
    static let attemptsBeforeGivingUp = 3

    /// How long to wait after `failures` failed attempts in a row: doubling
    /// from 2 seconds, at most 30.
    static func backoff(afterFailures failures: Int) -> Duration {
        let seconds = min(30, 2 * (1 << min(max(failures - 1, 0), 4)))
        return .seconds(seconds)
    }
}
