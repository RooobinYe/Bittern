//
//  NetworkMonitor.swift
//  Bittern
//

import Foundation
import Network

/// Whether the device has a network path. Behind a protocol so tests can
/// take the network away and give it back.
protocol NetworkMonitor: Sendable {
    /// The current state first, then every change: true while a path to
    /// the internet is available.
    func paths() -> AsyncStream<Bool>
}

/// `NWPathMonitor`, one per stream.
nonisolated struct SystemNetworkMonitor: NetworkMonitor {
    func paths() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in
                monitor.cancel()
            }
            monitor.start(queue: DispatchQueue(label: "com.robinye.Bittern.network-path"))
        }
    }
}

/// A network that never changes, for previews, demos and tests that don't
/// care about it.
nonisolated struct FixedNetworkMonitor: NetworkMonitor {
    let isOnline: Bool

    func paths() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuation.yield(isOnline)
        }
    }
}
