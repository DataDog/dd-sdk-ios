/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol FlagsRepositoryProtocol {
    var clientName: String { get }

    var context: FlagsEvaluationContext? { get }

    var state: FlagsStateObservable { get }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    )

    func flagAssignment(for key: String) -> FlagAssignment?

    func flagAssignments() -> [String: FlagAssignment]?

    func reset()
}

internal final class FlagsRepository {
    private enum Constants {
        static let readTimeout: TimeInterval = 0.1
    }

    let clientName: String
    private let stateManager = FlagsStateManager()

    private let flagAssignmentsFetcher: any FlagAssignmentsFetching
    private let dateProvider: any DateProvider
    private let featureScope: any FeatureScope

    @ReadWriteLock
    private var flagsData: FlagsData?

    /// Serializes request generations and the state changes that they protect.
    private let requestLock = NSLock()
    private var requestGeneration: UInt64 = 0
    /// The assignment request for the authoritative generation. Guarded by `requestLock`.
    private var inFlightRequest: FlagAssignmentsRequestHandle?
    /// The newest generation whose request already delivered a result. Guarded by `requestLock`.
    private var finishedGeneration: UInt64 = 0
    /// Callers waiting for a context update to settle. Guarded by `requestLock`.
    ///
    /// A newer context update supersedes the request before it, but not the caller that asked for
    /// it. Superseded callers stay here and receive the result of whichever request wins, so every
    /// `setEvaluationContext(_:completion:)` call is answered exactly once.
    private var pendingCompletions: [ContextCompletion] = []

    private typealias ContextCompletion = (Result<Void, FlagsError>) -> Void

    /// What to do with a request handle once its fetch has started.
    private enum HandleDisposition {
        /// The request is authoritative and still running.
        case stored
        /// A newer context update or `reset()` took over, so this request must stop.
        case superseded
        /// The fetch completed synchronously, so there is nothing left to cancel.
        case alreadyFinished
    }

    /// Tracks disk read state and pending callbacks for async operations.
    /// When `isComplete` is false, callbacks are queued and executed once disk read finishes.
    /// When `isComplete` is true, callbacks execute immediately.
    @ReadWriteLock
    private var diskReadState = DiskReadState()

    private struct DiskReadState {
        var isComplete = false
        var pendingCallbacks: [() -> Void] = []
    }

    /// Semaphore for blocking synchronous getters until disk read completes.
    /// Sync getters (context, flagAssignment, flagAssignments) block because callers
    /// explicitly request data synchronously and expect cached values if available.
    private let readSemaphore = DispatchSemaphore(value: 0)

    init(
        clientName: String,
        flagAssignmentsFetcher: any FlagAssignmentsFetching,
        dateProvider: any DateProvider,
        featureScope: any FeatureScope
    ) {
        self.clientName = clientName
        self.flagAssignmentsFetcher = flagAssignmentsFetcher
        self.dateProvider = dateProvider
        self.featureScope = featureScope
        readState()
    }

    deinit {
        // Nothing can answer these callers any more. Answer them here, so that an
        // `await setEvaluationContext(_:)` does not stay suspended for the life of the process.
        //
        // A caller waits in one of two places, depending on how far it got: in `diskReadState`
        // if the disk read had not finished, or in `pendingCompletions` once its request started.
        // Both are answered. Each deferred disk-read callback finds `self` already nil and
        // answers its own caller with `.clientNotInitialized`.
        let outcome = withRequestLock { () -> (pending: [ContextCompletion], request: FlagAssignmentsRequestHandle?) in
            let pending = pendingCompletions
            pendingCompletions = []
            let request = inFlightRequest
            inFlightRequest = nil
            return (pending, request)
        }
        // Nothing consumes this request's result any more, so stop it.
        outcome.request?.cancel()
        for completion in outcome.pending {
            completion(.failure(.clientNotInitialized))
        }

        var deferredCallbacks: [() -> Void] = []
        _diskReadState.mutate { state in
            deferredCallbacks = state.pendingCallbacks
            state.pendingCallbacks = []
        }
        for callback in deferredCallbacks {
            callback()
        }
    }

    private func readState() {
        let generationAtStart = withRequestLock { requestGeneration }
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { [weak self, readSemaphore] data in
            guard let self else {
                // Signal even if self is nil to unblock any waiting getters
                DispatchQueue.global(qos: .userInitiated).async {
                    readSemaphore.signal()
                }
                return
            }
            self.withRequestLock {
                guard self.requestGeneration == generationAtStart else {
                    return
                }
                self.flagsData = data
            }

            // Mark complete and grab pending callbacks atomically
            var callbacks: [() -> Void] = []
            self._diskReadState.mutate { state in
                state.isComplete = true
                callbacks = state.pendingCallbacks
                state.pendingCallbacks = []
            }

            // Signal semaphore for blocking getters (on elevated queue to avoid priority inversion)
            DispatchQueue.global(qos: .userInitiated).async {
                readSemaphore.signal()
            }

            // Execute async callbacks outside the lock
            for callback in callbacks {
                callback()
            }
        }
    }

    /// Blocks until disk read completes (up to timeout).
    /// Used by synchronous getters where callers expect cached data if available.
    private func waitForFlagsDataRead() {
        guard !diskReadState.isComplete else {
            return
        }
        _ = readSemaphore.wait(timeout: .now() + Constants.readTimeout)
    }

    /// Executes the callback after disk read completes without blocking.
    /// Used by setEvaluationContext to avoid blocking the caller's thread.
    private func whenFlagsDataRead(_ callback: @escaping () -> Void) {
        var shouldExecuteNow = false
        _diskReadState.mutate { state in
            if state.isComplete {
                shouldExecuteNow = true
            } else {
                state.pendingCallbacks.append(callback)
            }
        }

        if shouldExecuteNow {
            callback()
        }
    }

    private func writeState() {
        guard let flagsData else {
            return
        }
        featureScope.flagsDataStore.setFlagsData(flagsData, forClientNamed: clientName)
    }

    private func withRequestLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        requestLock.lock()
        defer { requestLock.unlock() }
        return try operation()
    }

    /// The work that an authoritative outcome defers until `requestLock` is free.
    private struct Settlement {
        let notifyListeners: () -> Void
        let pendingCompletions: [ContextCompletion]
    }

    /// Records the new state and takes the callers that it answers. Call with `requestLock` held.
    private func settle(with state: FlagsClientState) -> Settlement {
        let settlement = Settlement(
            notifyListeners: stateManager.updateStateDeferringNotification(state),
            pendingCompletions: pendingCompletions
        )
        pendingCompletions = []
        return settlement
    }

    /// Answers the given callers. Call with `requestLock` free: these are customer callbacks.
    private func resolve(_ completions: [ContextCompletion], with result: Result<Void, FlagsError>) {
        for completion in completions {
            completion(result)
        }
    }
}

extension FlagsRepository: FlagsRepositoryProtocol {
    var state: FlagsStateObservable { stateManager }

    var context: FlagsEvaluationContext? {
        waitForFlagsDataRead()
        return flagsData?.context
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        waitForFlagsDataRead()
        return flagsData?.flags[key]
    }

    func flagAssignments() -> [String: FlagAssignment]? {
        waitForFlagsDataRead()
        return flagsData?.flags
    }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        // Chain after disk read completes to ensure correct hadFlags determination
        whenFlagsDataRead { [weak self] in
            guard let self else {
                completion(.failure(.clientNotInitialized))
                return
            }

            let request = self.withRequestLock {
                self.requestGeneration &+= 1
                let requestGeneration = self.requestGeneration
                let hadFlags = self.flagsData != nil
                let cachedContext = self.flagsData?.context
                // The newest context update is authoritative, so the request it supersedes stops.
                // Its caller keeps waiting below, and the authoritative request answers it.
                let supersededRequest = self.inFlightRequest
                self.inFlightRequest = nil
                self.pendingCompletions.append(completion)
                let notifyListeners = self.stateManager
                    .updateStateDeferringNotification(.reconciling)
                return (
                    generation: requestGeneration,
                    hadFlags: hadFlags,
                    cachedContext: cachedContext,
                    supersededRequest: supersededRequest,
                    notifyListeners: notifyListeners
                )
            }
            request.supersededRequest?.cancel()
            request.notifyListeners()

            let handle = self.flagAssignmentsFetcher.flagAssignments(for: context) { [weak self] result in
                // `deinit` answers every pending caller, so this one is answered already.
                guard let self else {
                    return
                }

                switch result {
                case .success(let flags):
                    let settled = self.withRequestLock { () -> Settlement? in
                        guard self.requestGeneration == request.generation else {
                            return nil
                        }
                        self.flagsData = .init(
                            flags: flags,
                            context: context,
                            date: self.dateProvider.now
                        )
                        self.writeState()
                        self.inFlightRequest = nil
                        self.finishedGeneration = request.generation
                        return self.settle(with: .ready)
                    }
                    // A superseded request answers no one. Its caller waits for the winner.
                    guard let settled else {
                        return
                    }
                    settled.notifyListeners()
                    self.resolve(settled.pendingCompletions, with: .success(()))
                case .failure(let error):
                    let settled = self.withRequestLock { () -> Settlement? in
                        guard self.requestGeneration == request.generation else {
                            return nil
                        }
                        self.inFlightRequest = nil
                        self.finishedGeneration = request.generation
                        // Only use cached flags if they match the requested context to avoid
                        // serving flags from a different user/context.
                        guard request.hadFlags && request.cachedContext == context else {
                            // Clear cached data to prevent cross-context flag leakage.
                            // Without this, flagAssignment() could return the previous
                            // user's flags while in .error state.
                            self.flagsData = nil
                            return self.settle(with: .error)
                        }
                        return self.settle(with: .stale)
                    }
                    // A superseded request answers no one. Its caller waits for the winner.
                    guard let settled else {
                        return
                    }
                    // State must be updated before calling completion —
                    // dd-openfeature-provider-swift checks currentState in the callback.
                    settled.notifyListeners()
                    self.resolve(settled.pendingCompletions, with: .failure(error))
                }
            }

            // The fetch can finish or be superseded before `flagAssignments` returns, so decide
            // what to do with the handle only after the generation and the result are both known.
            let disposition = self.withRequestLock { () -> HandleDisposition in
                guard self.requestGeneration == request.generation else {
                    return .superseded
                }
                guard self.finishedGeneration != request.generation else {
                    return .alreadyFinished
                }
                self.inFlightRequest = handle
                return .stored
            }
            if disposition == .superseded {
                handle.cancel()
            }
        }
    }

    func reset() {
        // The data store is asynchronous, so its operations must be queued in the same order as
        // the generation change. Queuing the removal outside this lock lets a superseded request
        // queue a write after it, which restores invalidated assignments on the next launch.
        //
        // Disk is still cleared before listeners are notified, so a listener cannot observe
        // `.notReady` and then read stale data.
        let outcome = withRequestLock { () -> (supersededRequest: FlagAssignmentsRequestHandle?, settled: Settlement) in
            requestGeneration &+= 1
            flagsData = nil
            let supersededRequest = inFlightRequest
            inFlightRequest = nil
            featureScope.flagsDataStore.removeFlagsData(forClientNamed: clientName)
            return (supersededRequest, settle(with: .notReady))
        }
        outcome.supersededRequest?.cancel()
        outcome.settled.notifyListeners()
        // `reset()` cancels the request that would have answered these callers, so it answers
        // them itself. It reports success, because `reset()` is the operation that won and it
        // succeeded. This matches the result they received before requests became cancellable.
        resolve(outcome.settled.pendingCompletions, with: .success(()))
    }
}
