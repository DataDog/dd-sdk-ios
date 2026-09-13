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

    func assignmentAuthorizationDidChange()
}

extension FlagsRepositoryProtocol {
    func assignmentAuthorizationDidChange() {}
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
    private enum Constants {
        static let readTimeout: TimeInterval = 0.1
    }

    let clientName: String
    private let stateManager = FlagsStateManager()

    private let flagAssignmentsFetcher: any FlagAssignmentsFetching
    private let dateProvider: any DateProvider
    private let featureScope: any FeatureScope
    private let initializationTimeout: TimeInterval?
    private let scheduleInitializationTimeout: FlagsInitializationTimeoutScheduler
    private let authorizationStore: AssignmentAuthorizationStore

    private let initializationLock = NSLock()
    private let requestCommitLock = NSRecursiveLock()
    private var didStartInitialization = false

    private struct ProtectedState {
        var generation: UInt64 = 0
        var desiredContext: FlagsEvaluationContext?
        var flagsData: FlagsData?
    }

    @ReadWriteLock
    private var protectedState = ProtectedState()

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
        featureScope: any FeatureScope,
        authorizationStore: AssignmentAuthorizationStore = AssignmentAuthorizationStore(initialAuthorization: nil),
        initializationTimeout: TimeInterval? = Flags.Configuration.defaultInitializationTimeout,
        scheduleInitializationTimeout: FlagsInitializationTimeoutScheduler? = nil
    ) {
        self.clientName = clientName
        self.flagAssignmentsFetcher = flagAssignmentsFetcher
        self.dateProvider = dateProvider
        self.featureScope = featureScope
        self.authorizationStore = authorizationStore
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
        generation: UInt64,
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
            self.requestCommitLock.lock()
            guard self.isCurrent(generation: generation, context: context) else {
                self.requestCommitLock.unlock()
                completion(.failure(.networkError(URLError(.cancelled))))
                return
            }
            let timeoutState: FlagsClientState = self.currentFlagsData?.context == context ? .stale : .error
            let accepted = self.stateManager.updateState(
                timeoutState,
                unlessCurrentStateIs: [.ready, .stale]
            ) {
                completion(.failure(.initializationTimedOut))
            }
            self.requestCommitLock.unlock()
            if !accepted {
                completion(.failure(.initializationTimedOut))
            }
        }
        initializationCompletion.armTimeoutCancellation(cancelTimeout)
        return initializationCompletion
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
            self.requestCommitLock.lock()
            let snapshot = self.authorizationStore.snapshot()
            let expectedDigest = snapshot.authorization.map {
                AssignmentAuthorizationStore.digest(of: $0.bearerToken)
            }
            self._protectedState.mutate { state in
                if let desiredContext = state.desiredContext,
                   data?.context != desiredContext {
                    return
                }
                let bindingMatches = !snapshot.isEnabled
                    || data?.authorizationBinding?.compactJWTSHA256 == expectedDigest
                state.flagsData = bindingMatches ? data : nil
                if state.desiredContext == nil {
                    state.desiredContext = state.flagsData?.context
                }
            }
            self.requestCommitLock.unlock()

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

    private func writeState(_ flagsData: FlagsData) {
        featureScope.flagsDataStore.setFlagsData(flagsData, forClientNamed: clientName)
    }

    private var currentFlagsData: FlagsData? {
        protectedState.flagsData
    }

    private func beginRequest(for context: FlagsEvaluationContext) -> UInt64 {
        requestCommitLock.lock()
        defer { requestCommitLock.unlock() }
        var generation: UInt64 = 0
        _protectedState.mutate { state in
            state.generation &+= 1
            state.desiredContext = context
            generation = state.generation
        }
        stateManager.updateState(.reconciling)
        return generation
    }

    private func isCurrent(generation: UInt64, context: FlagsEvaluationContext) -> Bool {
        requestCommitLock.lock()
        defer { requestCommitLock.unlock() }
        let state = protectedState
        return state.generation == generation && state.desiredContext == context
    }
}

extension FlagsRepository: FlagsRepositoryProtocol {
    var state: FlagsStateObservable { stateManager }

    var context: FlagsEvaluationContext? {
        waitForFlagsDataRead()
        guard stateManager.currentState != .error else {
            return nil
        }
        let state = protectedState
        guard state.flagsData?.context == state.desiredContext else {
            return nil
        }
        return state.flagsData?.context
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        waitForFlagsDataRead()
        guard stateManager.currentState != .error else {
            return nil
        }
        let state = protectedState
        guard state.flagsData?.context == state.desiredContext else {
            return nil
        }
        return state.flagsData?.flags[key]
    }

    func flagAssignments() -> [String: FlagAssignment]? {
        waitForFlagsDataRead()
        guard stateManager.currentState != .error else {
            return nil
        }
        let state = protectedState
        guard state.flagsData?.context == state.desiredContext else {
            return nil
        }
        return state.flagsData?.flags
    }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        let generation = beginRequest(for: context)
        let initializationCompletion = makeInitializationCompletion(
            completion,
            context: context,
            generation: generation
        ) {}
        let takeCompletion: () -> ((Result<Void, FlagsError>) -> Void)? = {
            initializationCompletion?.take()
                ?? (initializationCompletion == nil ? completion : nil)
        }

        // Chain after disk read completes to ensure correct hadFlags determination
        whenFlagsDataRead { [weak self] in
            guard let self else {
                takeCompletion()?(.failure(.clientNotInitialized))
                return
            }

            guard self.isCurrent(generation: generation, context: context) else {
                takeCompletion()?(.failure(.networkError(URLError(.cancelled))))
                return
            }
            let cachedFlagsData = self.currentFlagsData
            let hadFlags = cachedFlagsData != nil
            let cachedContext = cachedFlagsData?.context
            self.flagAssignmentsFetcher.verifiedFlagAssignments(for: context) { [weak self] result in
                switch result {
                case .success(let verifiedAssignments):
                    guard let self else {
                        takeCompletion()?(.failure(.clientNotInitialized))
                        return
                    }
                    let flagsData = FlagsData(
                        flags: verifiedAssignments.flags,
                        context: context,
                        date: self.dateProvider.now,
                        authorizationBinding: verifiedAssignments.authorizationBinding
                    )
                    self.requestCommitLock.lock()
                    var committed = false
                    self._protectedState.mutate { state in
                        guard state.generation == generation,
                              state.desiredContext == context else {
                            return
                        }
                        state.flagsData = flagsData
                        committed = true
                    }
                    guard committed else {
                        self.requestCommitLock.unlock()
                        takeCompletion()?(.failure(.networkError(URLError(.cancelled))))
                        return
                    }
                    self.writeState(flagsData)
                    let operationCompletion = takeCompletion()
                    if initializationCompletion != nil {
                        self.stateManager.updateState(.ready) {
                            operationCompletion?(.success(()))
                        }
                    } else {
                        self.stateManager.updateState(.ready)
                        operationCompletion?(.success(()))
                    }
                    self.requestCommitLock.unlock()
                case .failure(let error):
                    guard let self else {
                        takeCompletion()?(.failure(.clientNotInitialized))
                        return
                    }
                    self.requestCommitLock.lock()
                    guard self.isCurrent(generation: generation, context: context) else {
                        self.requestCommitLock.unlock()
                        takeCompletion()?(.failure(.networkError(URLError(.cancelled))))
                        return
                    }
                    // State must be updated before calling completion —
                    // dd-openfeature-provider-swift checks currentState in the callback.
                    // Only use cached flags if they match the requested context to avoid
                    // serving flags from a different user/context.
                    let operationCompletion = takeCompletion()
                    let newState: FlagsClientState
                    if hadFlags && cachedContext == context {
                        newState = .stale
                    } else {
                        // Clear cached data to prevent cross-context flag leakage.
                        // Without this, flagAssignment() could return the previous
                        // user's flags while in .error state.
                        self._protectedState.mutate { state in
                            guard state.generation == generation else {
                                return
                            }
                            state.flagsData = nil
                        }
                        newState = .error
                    }
                    if initializationCompletion != nil {
                        self.stateManager.updateState(newState) {
                            operationCompletion?(.failure(error))
                        }
                    } else {
                        self.stateManager.updateState(newState)
                        operationCompletion?(.failure(error))
                    }
                    self.requestCommitLock.unlock()
                }
            }
        }
    }

    func reset() {
        requestCommitLock.lock()
        defer { requestCommitLock.unlock() }
        // Clear disk first, then memory, then update state.
        // This prevents race conditions where a listener reacts to the state
        // change and queries the data store before disk is cleared.
        featureScope.flagsDataStore.removeFlagsData(forClientNamed: clientName)
        _protectedState.mutate { state in
            state.generation &+= 1
            state.desiredContext = nil
            state.flagsData = nil
        }
        stateManager.updateState(.notReady)
    }

    func assignmentAuthorizationDidChange() {
        requestCommitLock.lock()
        defer { requestCommitLock.unlock() }
        let context = protectedState.desiredContext ?? currentFlagsData?.context
        featureScope.flagsDataStore.removeFlagsData(forClientNamed: clientName)
        _protectedState.mutate { state in
            state.generation &+= 1
            state.flagsData = nil
        }
        guard let context, authorizationStore.snapshot().authorization != nil else {
            stateManager.updateState(.notReady)
            return
        }
        setEvaluationContext(context) { _ in }
    }
}
