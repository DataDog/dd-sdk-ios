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
    private let cachePersistenceQueue = DispatchQueue(
        label: "com.datadoghq.ios-sdk-flags-cache-persistence",
        autoreleaseFrequency: .workItem,
        target: .global(qos: .utility)
    )

    @ReadWriteLock
    private var repositoryState = RepositoryState()

    /// Groups cached flags and disk-read lifecycle under one lock so a delayed initial read
    /// cannot race with a network reconciliation that has already produced fresher flags.
    private struct RepositoryState {
        var flagsData: FlagsData?
        var cachedFlagsData: FlagsData?
        var flagsDataVersion: UInt64 = 0
        var hasStartedEvaluationContextRequest = false
        var reconcilingContext: FlagsEvaluationContext?
        var isDiskReadComplete = false
        var pendingDiskReadCallbacks: [() -> Void] = []

        var shouldWaitForFlagsDataRead: Bool {
            !isDiskReadComplete && flagsData == nil
        }

        mutating func applyInitialFlagsData(_ data: FlagsData?) -> [() -> Void] {
            cachedFlagsData = data

            let isInitialReadStillAuthoritative = !hasStartedEvaluationContextRequest
            let isReconcilingSameContextBeforeFirstSuccess = data.map {
                flagsDataVersion == 0 && reconcilingContext == $0.context
            } ?? false

            if isInitialReadStillAuthoritative || isReconcilingSameContextBeforeFirstSuccess {
                flagsData = data
            }

            isDiskReadComplete = true
            let callbacks = pendingDiskReadCallbacks
            pendingDiskReadCallbacks = []
            return callbacks
        }

        func flagsData(matching context: FlagsEvaluationContext) -> FlagsData? {
            if flagsData?.context == context {
                return flagsData
            }
            if cachedFlagsData?.context == context {
                return cachedFlagsData
            }
            return nil
        }

        mutating func executeAfterDiskReadCompletes(_ callback: @escaping () -> Void) -> Bool {
            if isDiskReadComplete {
                return true
            } else {
                pendingDiskReadCallbacks.append(callback)
                return false
            }
        }
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
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { [weak self, readSemaphore] data in
            guard let self else {
                // Signal even if self is nil to unblock any waiting getters
                DispatchQueue.global(qos: .userInitiated).async {
                    readSemaphore.signal()
                }
                return
            }
            var callbacks: [() -> Void] = []
            self._repositoryState.mutate { state in
                callbacks = state.applyInitialFlagsData(data)
            }

            // Signal semaphore for blocking getters (on elevated queue to avoid priority inversion)
            DispatchQueue.global(qos: .userInitiated).async {
                readSemaphore.signal()
            }

            self.executePendingDiskReadCallbacks(callbacks)
        }
    }

    private func executePendingDiskReadCallbacks(_ callbacks: [() -> Void]) {
        guard !callbacks.isEmpty else {
            return
        }

        // The initial disk-read callback runs on DatadogCore's shared read/write queue.
        // Hop off that queue before notifying state listeners or invoking public completions.
        DispatchQueue.global(qos: .utility).async {
            callbacks.forEach { $0() }
        }
    }

    /// Blocks until disk read completes (up to timeout).
    /// Used by synchronous getters where callers expect cached data if available.
    private func waitForFlagsDataRead() {
        guard repositoryState.shouldWaitForFlagsDataRead else {
            return
        }
        _ = readSemaphore.wait(timeout: .now() + Constants.readTimeout)
    }

    /// Executes the callback after the initial disk read completes.
    /// Used on fetch failure so cached flags can be used without delaying the network request.
    private func whenFlagsDataRead(_ callback: @escaping () -> Void) {
        var shouldExecuteNow = false
        _repositoryState.mutate { state in
            shouldExecuteNow = state.executeAfterDiskReadCompletes(callback)
        }

        if shouldExecuteNow {
            callback()
        }
    }

    private func writeState(_ flagsData: FlagsData, version: UInt64) {
        let flagsDataStore = featureScope.flagsDataStore
        let clientName = clientName

        cachePersistenceQueue.async { [weak self] in
            guard self?.repositoryState.flagsDataVersion == version else {
                return
            }

            guard let encodedFlagsData = flagsDataStore.encodeFlagsData(flagsData) else {
                return
            }

            guard self?.repositoryState.flagsDataVersion == version else {
                return
            }

            flagsDataStore.setEncodedFlagsData(encodedFlagsData, forClientNamed: clientName)
        }
    }

    private func handleFailedContextUpdate(
        error: FlagsError,
        context: FlagsEvaluationContext,
        versionAtStart: UInt64,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        // Only update state if no newer request has succeeded.
        // This prevents an older failing request from clearing data
        // written by a newer successful request.
        var stateToUpdate: FlagsClientState?
        _repositoryState.mutate { state in
            guard state.flagsDataVersion == versionAtStart else {
                return
            }

            state.reconcilingContext = nil

            // Only use cached flags if they match the requested context to avoid
            // serving flags from a different user/context.
            if let matchingFlagsData = state.flagsData(matching: context) {
                state.flagsData = matchingFlagsData
                stateToUpdate = .stale
            } else {
                // Clear cached data to prevent cross-context flag leakage.
                // Without this, flagAssignment() could return the previous
                // user's flags while in .error state.
                state.flagsData = nil
                stateToUpdate = .error
            }
        }

        guard let stateToUpdate else {
            completion(.failure(error))
            return
        }

        // State must be updated before calling completion —
        // dd-openfeature-provider-swift checks currentState in the callback.
        stateManager.updateState(stateToUpdate)
        completion(.failure(error))
    }
}

extension FlagsRepository: FlagsRepositoryProtocol {
    var state: FlagsStateObservable { stateManager }

    var context: FlagsEvaluationContext? {
        waitForFlagsDataRead()
        return repositoryState.flagsData?.context
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        waitForFlagsDataRead()
        return repositoryState.flagsData?.flags[key]
    }

    func flagAssignments() -> [String: FlagAssignment]? {
        waitForFlagsDataRead()
        return repositoryState.flagsData?.flags
    }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        var versionAtStart: UInt64 = 0
        _repositoryState.mutate { state in
            state.hasStartedEvaluationContextRequest = true
            state.reconcilingContext = context
            versionAtStart = state.flagsDataVersion
        }
        stateManager.updateState(.reconciling)

        flagAssignmentsFetcher.flagAssignments(for: context) { [weak self] result in
            guard let self else {
                completion(.failure(.clientNotInitialized))
                return
            }

            switch result {
            case .success(let flags):
                let flagsData = FlagsData(
                    flags: flags,
                    context: context,
                    date: self.dateProvider.now
                )
                var versionAfterSuccess: UInt64 = 0
                self._repositoryState.mutate { state in
                    state.flagsData = flagsData
                    state.cachedFlagsData = flagsData
                    state.flagsDataVersion += 1
                    versionAfterSuccess = state.flagsDataVersion
                    state.reconcilingContext = nil
                }
                self.writeState(flagsData, version: versionAfterSuccess)
                self.stateManager.updateState(.ready)
                completion(.success(()))
            case .failure(let error):
                self.whenFlagsDataRead { [weak self] in
                    guard let self else {
                        completion(.failure(.clientNotInitialized))
                        return
                    }

                    self.handleFailedContextUpdate(
                        error: error,
                        context: context,
                        versionAtStart: versionAtStart,
                        completion: completion
                    )
                }
            }
        }
    }

    func reset() {
        let flagsDataStore = featureScope.flagsDataStore
        let clientName = clientName

        _repositoryState.mutate { state in
            state.flagsData = nil
            state.cachedFlagsData = nil
            state.flagsDataVersion += 1
            state.reconcilingContext = nil
        }
        // Enqueue removal after any already-started cache write to avoid
        // re-persisting stale flags after reset.
        cachePersistenceQueue.sync {
            flagsDataStore.removeFlagsData(forClientNamed: clientName)
        }
        stateManager.updateState(.notReady)
    }
}
