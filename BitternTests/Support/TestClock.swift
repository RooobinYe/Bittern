import Foundation
@testable import Bittern

/// Time that passes only when a test says so. `sleep` waits until the
/// test advances past its deadline; `now` reads the same time as a date.
nonisolated final class TestClock: @unchecked Sendable {
    private struct Sleeper {
        let id: Int
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var elapsed: Duration = .zero
    private var sleepers: [Sleeper] = []
    /// Sleeps cancelled before they began waiting.
    private var cancelledIDs: Set<Int> = []
    private var nextID = 0
    private let start: Date

    init(start: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.start = start
    }

    var now: Date {
        lock.withLock { start.addingTimeInterval(Self.seconds(elapsed)) }
    }

    /// The durations of the sleeps waiting now, shortest first.
    var pendingSleeps: [Duration] {
        lock.withLock { sleepers.map { $0.deadline - elapsed }.sorted() }
    }

    func sleep(for duration: Duration) async throws {
        let id = lock.withLock {
            nextID += 1
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let outcome = lock.withLock { () -> Result<Bool, any Error> in
                    if cancelledIDs.remove(id) != nil { return .failure(CancellationError()) }
                    if duration <= .zero { return .success(true) }
                    sleepers.append(Sleeper(id: id, deadline: elapsed + duration, continuation: continuation))
                    return .success(false)
                }
                switch outcome {
                case .success(true): continuation.resume()
                case .success(false): break
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            let cancelled = lock.withLock { () -> Sleeper? in
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
                    cancelledIDs.insert(id)
                    return nil
                }
                return sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time on by `duration`, waking every sleep that ends by then.
    func advance(by duration: Duration) {
        let due = lock.withLock { () -> [Sleeper] in
            elapsed += duration
            let due = sleepers.filter { $0.deadline <= elapsed }
            sleepers.removeAll { $0.deadline <= elapsed }
            return due
        }
        due.forEach { $0.continuation.resume() }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

/// A network path a test takes away and gives back.
nonisolated final class TestNetworkMonitor: NetworkMonitor, @unchecked Sendable {
    private let lock = NSLock()
    private var isOnline: Bool
    private var continuations: [AsyncStream<Bool>.Continuation] = []

    init(isOnline: Bool = true) {
        self.isOnline = isOnline
    }

    func paths() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let current = lock.withLock {
                continuations.append(continuation)
                return isOnline
            }
            continuation.yield(current)
        }
    }

    func set(online: Bool) {
        let continuations = lock.withLock {
            isOnline = online
            return self.continuations
        }
        continuations.forEach { $0.yield(online) }
    }
}
