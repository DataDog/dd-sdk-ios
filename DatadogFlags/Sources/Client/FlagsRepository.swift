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

        var shouldWaitForFlagsDataRead: Bool {
            !isDiskReadComplete && flagsData == nil
        }

        var shouldWaitBrieflyForFlagsDataRead: Bool {
            !isDiskReadComplete
        }

        mutating func applyInitialFlagsData(_ data: FlagsData?) {
            cachedFlagsData = data

            let isInitialReadStillAuthoritative = !hasStartedEvaluationContextRequest
            let isReconcilingSameContextBeforeFirstSuccess = data.map {
                flagsDataVersion == 0 && reconcilingContext == $0.context
            } ?? false

            if isInitialReadStillAuthoritative || isReconcilingSameContextBeforeFirstSuccess {
                flagsData = data
            }

            isDiskReadComplete = true
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
            self._repositoryState.mutate { state in
                state.applyInitialFlagsData(data)
            }

            // Signal semaphore for blocking getters (on elevated queue to avoid priority inversion)
            DispatchQueue.global(qos: .userInitiated).async {
                readSemaphore.signal()
            }
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

    /// Gives the initial disk read a short chance to complete for stale-cache fallback.
    private func waitBrieflyForFlagsDataRead() {
        guard repositoryState.shouldWaitBrieflyForFlagsDataRead else {
            return
        }
        _ = readSemaphore.wait(timeout: .now() + Constants.readTimeout)
    }

    private func writeState(_ flagsData: FlagsData) {
        featureScope.flagsDataStore.setFlagsData(flagsData, forClientNamed: clientName)
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
                self._repositoryState.mutate { state in
                    state.flagsData = flagsData
                    state.cachedFlagsData = flagsData
                    state.flagsDataVersion += 1
                    state.reconcilingContext = nil
                }
                self.writeState(flagsData)
                self.stateManager.updateState(.ready)
                completion(.success(()))
            case .failure(let error):
                self.waitBrieflyForFlagsDataRead()

                // Only update state if no newer request has succeeded.
                // This prevents an older failing request from clearing data
                // written by a newer successful request.
                var stateToUpdate: FlagsClientState?
                self._repositoryState.mutate { state in
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
                self.stateManager.updateState(stateToUpdate)
                completion(.failure(error))
            }
        }
    }

    func reset() {
        // Clear disk first, then memory, then update state.
        // This prevents race conditions where a listener reacts to the state
        // change and queries the data store before disk is cleared.
        featureScope.flagsDataStore.removeFlagsData(forClientNamed: clientName)
        _repositoryState.mutate { state in
            state.flagsData = nil
            state.cachedFlagsData = nil
            state.reconcilingContext = nil
        }
        stateManager.updateState(.notReady)
    }
}
