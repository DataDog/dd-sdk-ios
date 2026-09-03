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
                return (
                    generation: requestGeneration,
                    hadFlags: hadFlags,
                    cachedContext: cachedContext
                )
            }
            self.stateManager.updateState(.reconciling)

            self.flagAssignmentsFetcher.flagAssignments(for: context) { [weak self] result in
                guard let self else {
                    completion(.failure(.clientNotInitialized))
                    return
                }

                switch result {
                case .success(let flags):
                    let isCurrentRequest = self.withRequestLock { () -> Bool in
                        guard self.requestGeneration == request.generation else {
                            return false
                        }
                        self.flagsData = .init(
                            flags: flags,
                            context: context,
                            date: self.dateProvider.now
                        )
                        return true
                    }
                    if isCurrentRequest {
                        self.writeState()
                        self.stateManager.updateState(.ready)
                    }
                    completion(.success(()))
                case .failure(let error):
                    let stateToPublish = self.withRequestLock { () -> FlagsClientState? in
                        guard self.requestGeneration == request.generation else {
                            return nil
                        }
                        // Only use cached flags if they match the requested context to avoid
                        // serving flags from a different user/context.
                        if request.hadFlags && request.cachedContext == context {
                            return .stale
                        } else {
                            // Clear cached data to prevent cross-context flag leakage.
                            // Without this, flagAssignment() could return the previous
                            // user's flags while in .error state.
                            self.flagsData = nil
                            return .error
                        }
                    }
                    // State must be updated before calling completion —
                    // dd-openfeature-provider-swift checks currentState in the callback.
                    if let stateToPublish {
                        self.stateManager.updateState(stateToPublish)
                    }
                    completion(.failure(error))
                }
            }
        }
    }

    func reset() {
        // Clear disk first, then memory, then update state.
        // This prevents race conditions where a listener reacts to the state
        // change and queries the data store before disk is cleared.
        featureScope.flagsDataStore.removeFlagsData(forClientNamed: clientName)
        withRequestLock {
            requestGeneration &+= 1
            flagsData = nil
        }
        stateManager.updateState(.notReady)
    }
}
