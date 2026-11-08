//
//  LivePriceRefresh.swift
//  Bittern
//
//  How often prices refresh themselves, and how hard a failing load is
//  retried.
//

import Foundation

enum LivePriceRefresh {
    /// How often the prices of holdings in an active session are fetched
    /// while the app is in the foreground. Every tick asks Yahoo's chart
    /// endpoint once per symbol in session, twice in pre- and post-market.
    ///
    /// Measured on 2026-11-08 from one address: 10 symbols every second
    /// (about 10 requests a second) for 4 minutes, and about 9,800 requests
    /// over 35 minutes, drew no throttling. 2 seconds keeps a portfolio of a
    /// dozen holdings in extended hours, at two requests each, near that
    /// tested rate. Yahoo's CDN caches each quote for 10 seconds, so a price
    /// changes about that often however short the interval; a shorter one
    /// only shows the change sooner.
    static let interval: Duration = .seconds(2)

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
