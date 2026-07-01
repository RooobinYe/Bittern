//
//  CancelableTaskRunner.swift
//  Bittern
//

import Foundation

/// Ensures only the latest task runs to completion.
///
/// Each call to `run` cancels the previous task (if any), increments a generation
/// counter, and passes the generation value into the work closure. Callers should
/// guard on the received generation before applying results or side effects so
/// that stale completions are silently discarded.
///
/// `isRunning` is `true` while a task is in flight. Connect `onStateChanged` to
/// `objectWillChange.send()` so SwiftUI views observe it correctly.
///
/// ```swift
/// // In an ObservableObject:
/// private let loader = CancelableTaskRunner()
///
/// var isLoading: Bool { loader.isRunning }
///
/// init() {
///     loader.onStateChanged = { [weak self] in self?.objectWillChange.send() }
/// }
///
/// func refresh() async {
///     await loader.run { [weak self] gen in
///         guard let self else { return }
///         errorMessage = nil
///         let data = try await fetch()
///         guard gen == loader.generation else { return }
///         self.data = data
///     }
/// }
/// ```
@MainActor
final class CancelableTaskRunner {
    private var task: Task<Void, Never>?

    /// Monotonically increasing generation counter. Only the latest generation
    /// should apply results.
    private(set) var generation = 0

    /// `true` while a task is in flight.
    var isRunning: Bool { task != nil }

    /// Called on `@MainActor` whenever `isRunning` changes. Connect this to
    /// `objectWillChange.send()` so SwiftUI views observe a computed
    /// `isLoading` property correctly.
    var onStateChanged: (() -> Void)?

    /// Cancels any in-flight task and spawns a new one to execute `work`.
    ///
    /// - Parameter work: An `async` closure that receives the generation number
    ///   for this invocation. Guard on `generation == runner.generation` before
    ///   applying results, so that stale completions are silently discarded.
    func run(_ work: @MainActor @escaping (_ generation: Int) async -> Void) async {
        task?.cancel()
        generation += 1
        let gen = generation

        let newTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await work(gen)
            if gen == self.generation {
                self.task = nil
                self.onStateChanged?()
            }
        }
        task = newTask
        onStateChanged?()
        await newTask.value
    }

    /// Cancels the current task without starting a new one.
    func cancel() {
        task?.cancel()
        task = nil
        onStateChanged?()
    }
}
