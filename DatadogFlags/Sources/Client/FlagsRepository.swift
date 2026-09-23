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

    func flush()
}

internal typealias FlagsInitializationTimeoutCancellation = () -> Void
internal typealias FlagsInitializationTimeoutScheduler = (
    TimeInterval,
    @escaping () -> Void
) -> FlagsInitializationTimeoutCancellation

private final class InitializationCompletion {
    typealias Completion = (Result<Void, FlagsError>) -> Void

    private let lock = NSLock()
    private var completion: Completion?
    private var cancelTimeout: FlagsInitializationTimeoutCancellation?

    init(completion: @escaping Completion) {
        self.completion = completion
    }

    func armTimeoutCancellation(_ cancellation: @escaping FlagsInitializationTimeoutCancellation) {
        lock.lock()
        if completion == nil {
            lock.unlock()
            cancellation()
        } else {
            cancelTimeout = cancellation
            lock.unlock()
        }
    }

    func take() -> Completion? {
        lock.lock()
        guard let completion else {
            lock.unlock()
            return nil
        }
        self.completion = nil
        let cancelTimeout = self.cancelTimeout
        self.cancelTimeout = nil
        lock.unlock()

        cancelTimeout?()
        return completion
    }
}

internal final class FlagsRepository {
    let clientName: String
    private let stateManager = FlagsStateManager()

    private let flagAssignmentsFetcher: any FlagAssignmentsFetching
    private let dateProvider: any DateProvider
    private let featureScope: any FeatureScope
    private let readTimeout: TimeInterval
    private let cachePersistenceQueue = DispatchQueue(
        label: "com.datadoghq.ios-sdk-flags-cache-persistence",
        autoreleaseFrequency: .workItem,
        target: .global(qos: .utility)
    )
    private let initializationTimeout: TimeInterval?
    private let scheduleInitializationTimeout: FlagsInitializationTimeoutScheduler

    private let initializationLock = NSLock()
    private var didStartInitialization = false

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
        var pendingDiskReadCallbacks: [() -> Void] = []
        var initialFlagsDataGroup: DispatchGroup? = {
            let group = DispatchGroup()
            group.enter()
            return group
        }()

        var shouldWaitForFlagsDataRead: Bool {
            initialFlagsDataGroup != nil
        }

        mutating func applyInitialFlagsData(_ data: FlagsData?) -> [() -> Void] {
            // A successful fetch or reset supersedes both active and fallback data from disk.
            if flagsDataVersion == 0 {
                cachedFlagsData = data

                let isInitialReadStillAuthoritative = !hasStartedEvaluationContextRequest
                let isReconcilingSameContext = data.map {
                    reconcilingContext == $0.context
                } ?? false

                if isInitialReadStillAuthoritative || isReconcilingSameContext {
                    flagsData = data
                }
            }

            return finishWaitingForInitialFlagsData()
        }

        mutating func finishWaitingForInitialFlagsData() -> [() -> Void] {
            // Leave only once, waking all getters even if a late disk read follows a fetch or reset.
            initialFlagsDataGroup?.leave()
            initialFlagsDataGroup = nil
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
    }

    init(
        clientName: String,
        flagAssignmentsFetcher: any FlagAssignmentsFetching,
        dateProvider: any DateProvider,
        featureScope: any FeatureScope,
        readTimeout: TimeInterval = 0.1,
        initializationTimeout: TimeInterval? = Flags.Configuration.defaultInitializationTimeout,
        scheduleInitializationTimeout: FlagsInitializationTimeoutScheduler? = nil
    ) {
        self.clientName = clientName
        self.flagAssignmentsFetcher = flagAssignmentsFetcher
        self.dateProvider = dateProvider
        self.featureScope = featureScope
        self.readTimeout = readTimeout
        self.initializationTimeout = initializationTimeout
        self.scheduleInitializationTimeout = scheduleInitializationTimeout ?? Self.scheduleInitializationTimeout
        readState()
    }

    private static func scheduleInitializationTimeout(
        _ timeout: TimeInterval,
        _ action: @escaping () -> Void
    ) -> FlagsInitializationTimeoutCancellation {
        let workItem = DispatchWorkItem(block: action)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: initializationTimeoutDeadline(after: timeout),
            execute: workItem
        )
        return { workItem.cancel() }
    }

    internal static func initializationTimeoutDeadline(
        after timeout: TimeInterval,
        from start: DispatchTime = .now()
    ) -> DispatchTime {
        guard timeout.isFinite, timeout > 0 else {
            return start
        }
        let maximumSeconds = TimeInterval(UInt64.max - start.uptimeNanoseconds) / TimeInterval(NSEC_PER_SEC)
        return timeout < maximumSeconds ? start + timeout : DispatchTime(uptimeNanoseconds: UInt64.max)
    }

    private func makeInitializationCompletion(
        _ completion: @escaping (Result<Void, FlagsError>) -> Void,
        context: FlagsEvaluationContext,
        beforeScheduling: () -> Void
    ) -> InitializationCompletion? {
        initializationLock.lock()
        guard !didStartInitialization else {
            initializationLock.unlock()
            return nil
        }
        didStartInitialization = true
        initializationLock.unlock()

        guard let initializationTimeout,
              initializationTimeout.isFinite,
              initializationTimeout > 0 else {
            return nil
        }

        beforeScheduling()
        let initializationCompletion = InitializationCompletion(completion: completion)
        let cancelTimeout = scheduleInitializationTimeout(initializationTimeout) { [weak self, initializationCompletion] in
            guard let completion = initializationCompletion.take() else {
                return
            }
            guard let self else {
                completion(.failure(.clientNotInitialized))
                return
            }
            let timeoutState: FlagsClientState = self.repositoryState.flagsData?.context == context ? .stale : .error
            let accepted = self.stateManager.updateState(
                timeoutState,
                unlessCurrentStateIs: [.ready, .stale]
            ) {
                completion(.failure(.initializationTimedOut))
            }
            if !accepted {
                completion(.failure(.initializationTimedOut))
            }
        }
        initializationCompletion.armTimeoutCancellation(cancelTimeout)
        return initializationCompletion
    }

    private func readState() {
        // Retain the read lifecycle, not the repository, so the group is balanced even after deallocation.
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { [weak self, _repositoryState] data in
            var callbacks: [() -> Void] = []
            _repositoryState.mutate { state in
                callbacks = state.applyInitialFlagsData(data)
            }

            self?.executePendingDiskReadCallbacks(callbacks)
        }
    }

    private func executePendingDiskReadCallbacks(_ callbacks: [() -> Void]) {
        guard !callbacks.isEmpty else {
            return
        }

        // Disk reads can release callbacks on DatadogCore's shared read/write queue.
        // Keep state listeners and public completions off that queue.
        DispatchQueue.global(qos: .utility).async {
            callbacks.forEach { $0() }
        }
    }

    /// Blocks until the initial disk read completes or is superseded (up to timeout).
    /// Used by synchronous getters where callers expect cached data if available.
    private func waitForFlagsDataRead() {
        guard let group = repositoryState.initialFlagsDataGroup else {
            return
        }
        _ = group.wait(timeout: .now() + readTimeout)
    }

    /// Executes the callback once the initial cache is available, or immediately if a fetch or reset superseded it.
    /// Used on fetch failure so cached flags can be used without delaying the network request.
    private func whenCacheReady(_ callback: @escaping () -> Void) {
        var shouldExecuteNow = false
        _repositoryState.mutate { state in
            if state.shouldWaitForFlagsDataRead {
                state.pendingDiskReadCallbacks.append(callback)
            } else {
                shouldExecuteNow = true
            }
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

    private func applyFailedContextUpdate(
        for context: FlagsEvaluationContext,
        versionAtStart: UInt64
    ) -> FlagsClientState? {
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

        return stateToUpdate
    }
}

extension FlagsRepository: FlagsRepositoryProtocol {
    var state: FlagsStateObservable { stateManager }

    var context: FlagsEvaluationContext? {
        waitForFlagsDataRead()
        guard stateManager.currentState != .error else {
            return nil
        }
        return repositoryState.flagsData?.context
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        waitForFlagsDataRead()
        guard stateManager.currentState != .error else {
            return nil
        }
        return repositoryState.flagsData?.flags[key]
    }

    func flagAssignments() -> [String: FlagAssignment]? {
        waitForFlagsDataRead()
        guard stateManager.currentState != .error else {
            return nil
        }
        return repositoryState.flagsData?.flags
    }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        let initializationCompletion = makeInitializationCompletion(completion, context: context) {
            stateManager.updateState(.reconciling)
        }
        let complete: (Result<Void, FlagsError>, FlagsClientState?) -> Void = { [stateManager] result, newState in
            // Claim initialization before notifying listeners so its timeout cannot replace the result.
            let operationCompletion = initializationCompletion?.take()
                ?? (initializationCompletion == nil ? completion : nil)

            guard let newState else {
                operationCompletion?(result)
                return
            }

            // The provider reads currentState in completion; initialization must also complete before listeners.
            if initializationCompletion != nil {
                stateManager.updateState(newState) {
                    operationCompletion?(result)
                }
            } else {
                stateManager.updateState(newState)
                operationCompletion?(result)
            }
        }

        var versionAtStart: UInt64 = 0
        _repositoryState.mutate { state in
            state.hasStartedEvaluationContextRequest = true
            state.reconcilingContext = context
            versionAtStart = state.flagsDataVersion
        }
        if initializationCompletion == nil {
            stateManager.updateState(.reconciling)
        }

        flagAssignmentsFetcher.flagAssignments(for: context) { [weak self] result in
            guard let self else {
                complete(.failure(.clientNotInitialized), nil)
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
                var callbacks: [() -> Void] = []
                self._repositoryState.mutate { state in
                    state.flagsData = flagsData
                    state.cachedFlagsData = flagsData
                    state.flagsDataVersion += 1
                    versionAfterSuccess = state.flagsDataVersion
                    state.reconcilingContext = nil
                    callbacks = state.finishWaitingForInitialFlagsData()
                }
                self.writeState(flagsData, version: versionAfterSuccess)
                complete(.success(()), .ready)
                self.executePendingDiskReadCallbacks(callbacks)
            case .failure(let error):
                self.whenCacheReady { [weak self] in
                    guard let self else {
                        complete(.failure(.clientNotInitialized), nil)
                        return
                    }

                    let newState = self.applyFailedContextUpdate(
                        for: context,
                        versionAtStart: versionAtStart
                    )
                    complete(.failure(error), newState)
                }
            }
        }
    }

    func reset() {
        let flagsDataStore = featureScope.flagsDataStore
        let clientName = clientName
        var callbacks: [() -> Void] = []

        _repositoryState.mutate { state in
            state.flagsData = nil
            state.cachedFlagsData = nil
            state.flagsDataVersion += 1
            state.reconcilingContext = nil
            callbacks = state.finishWaitingForInitialFlagsData()
        }
        // Enqueue removal after any already-started cache write to avoid
        // re-persisting stale flags after reset.
        cachePersistenceQueue.sync {
            flagsDataStore.removeFlagsData(forClientNamed: clientName)
        }
        stateManager.updateState(.notReady)
        executePendingDiskReadCallbacks(callbacks)
    }

    func flush() {
        cachePersistenceQueue.sync {}
    }
}
