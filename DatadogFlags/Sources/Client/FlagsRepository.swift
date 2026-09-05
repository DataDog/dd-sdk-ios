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

    func complete(_ action: (Completion?) -> () -> Void) {
        lock.lock()
        let pendingCompletion = completion
        if pendingCompletion != nil {
            completion = nil
        }
        let timeoutCancellation = pendingCompletion == nil ? nil : cancelTimeout
        if pendingCompletion != nil {
            cancelTimeout = nil
        }

        let callout = action(pendingCompletion)
        lock.unlock()
        timeoutCancellation?()
        callout()
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
    internal let initializationTimeout: TimeInterval?
    private let scheduleInitializationTimeout: FlagsInitializationTimeoutScheduler

    private let initializationLock = NSLock()
    private var didStartInitialization = false
    private var contextUpdateCount: UInt64 = 0
    private var latestRequestedContext: FlagsEvaluationContext?
    /// Identifies late work after the initialization timeout has completed the first request.
    private var timedOutInitializationContextUpdate: UInt64?

    @ReadWriteLock
    private var flagsData: FlagsData?

    /// Changes after each flags data write, so an older failure cannot clear newer data.
    @ReadWriteLock
    private var flagsDataVersion: UInt64 = 0

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
        initializationTimeout: TimeInterval? = Flags.Configuration.defaultInitializationTimeout,
        scheduleInitializationTimeout: FlagsInitializationTimeoutScheduler? = nil
    ) {
        self.clientName = clientName
        self.flagAssignmentsFetcher = flagAssignmentsFetcher
        self.dateProvider = dateProvider
        self.featureScope = featureScope
        self.initializationTimeout = initializationTimeout
        self.scheduleInitializationTimeout = scheduleInitializationTimeout ?? Self.scheduleInitializationTimeout
        readState()
    }

    internal static func scheduleInitializationTimeout(
        _ timeout: TimeInterval,
        _ action: @escaping () -> Void
    ) -> FlagsInitializationTimeoutCancellation {
        let workItem = DispatchWorkItem(block: action)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .milliseconds(initializationTimeoutMilliseconds(for: timeout)),
            execute: workItem
        )
        return { workItem.cancel() }
    }

    internal static func initializationTimeoutMilliseconds(for timeout: TimeInterval) -> Int {
        guard timeout.isFinite, timeout > 0 else {
            return 0
        }
        let requestedMilliseconds = (timeout * 1_000).rounded()
        guard requestedMilliseconds.isFinite, requestedMilliseconds < Double(Int.max) else {
            return .max
        }
        return Int(requestedMilliseconds)
    }

    private struct ContextUpdate {
        let generation: UInt64
        let ownsInitialization: Bool
        let notifyReconciling: () -> Void
    }

    private func beginContextUpdate(for context: FlagsEvaluationContext) -> ContextUpdate {
        initializationLock.lock()
        contextUpdateCount &+= 1
        latestRequestedContext = context
        let generation = contextUpdateCount
        let ownsInitialization = !didStartInitialization
        didStartInitialization = true
        let notifyReconciling = stateManager.updateStateDeferringNotification(.reconciling)
        initializationLock.unlock()
        return ContextUpdate(
            generation: generation,
            ownsInitialization: ownsInitialization,
            notifyReconciling: notifyReconciling
        )
    }

    private func makeInitializationCompletion(
        for context: FlagsEvaluationContext,
        contextUpdate: ContextUpdate,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) -> InitializationCompletion? {
        guard contextUpdate.ownsInitialization, let initializationTimeout else {
            return nil
        }

        let initializationCompletion = InitializationCompletion(completion: completion)
        let cancelTimeout = scheduleInitializationTimeout(initializationTimeout) { [weak self, initializationCompletion] in
            initializationCompletion.complete { completion in
                guard let completion else {
                    return {}
                }
                let notifyListeners = self?.publishInitializationTimeoutState(
                    for: context,
                    contextUpdate: contextUpdate.generation
                ) ?? {}
                return {
                    completion(.failure(.initializationTimedOut))
                    notifyListeners()
                }
            }
        }
        initializationCompletion.armTimeoutCancellation(cancelTimeout)
        return initializationCompletion
    }

    private func publishInitializationTimeoutState(
        for context: FlagsEvaluationContext,
        contextUpdate: UInt64
    ) -> () -> Void {
        initializationLock.lock()
        defer { initializationLock.unlock() }
        guard contextUpdateCount == contextUpdate else {
            return {}
        }
        timedOutInitializationContextUpdate = contextUpdate
        if flagsData?.context == context {
            return stateManager.updateStateDeferringNotification(.stale)
        } else {
            flagsData = nil
            _flagsDataVersion.mutate { $0 &+= 1 }
            return stateManager.updateStateDeferringNotification(.error)
        }
    }

    private func publishSuccess(
        _ flags: [String: FlagAssignment],
        for context: FlagsEvaluationContext,
        contextUpdate: UInt64,
        requireLatest: Bool
    ) -> () -> Void {
        initializationLock.lock()
        defer { initializationLock.unlock() }
        guard !requireLatest || contextUpdateCount == contextUpdate else {
            return {}
        }
        flagsData = .init(flags: flags, context: context, date: dateProvider.now)
        _flagsDataVersion.mutate { $0 &+= 1 }
        writeState()
        return stateManager.updateStateDeferringNotification(.ready)
    }

    private func publishFailure(
        hadFlags: Bool,
        cachedContext: FlagsEvaluationContext?,
        requestedContext: FlagsEvaluationContext,
        contextUpdate: UInt64,
        flagsDataVersionAtStart: UInt64,
        requireLatest: Bool
    ) -> () -> Void {
        initializationLock.lock()
        defer { initializationLock.unlock() }
        guard !requireLatest || contextUpdateCount == contextUpdate,
              flagsDataVersion == flagsDataVersionAtStart else {
            return {}
        }
        if hadFlags && cachedContext == requestedContext {
            return stateManager.updateStateDeferringNotification(.stale)
        } else {
            flagsData = nil
            _flagsDataVersion.mutate { $0 &+= 1 }
            return stateManager.updateStateDeferringNotification(.error)
        }
    }

    private func readState() {
        let contextUpdateAtStart = contextUpdateCount
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { [weak self, readSemaphore] data in
            guard let self else {
                // Signal even if self is nil to unblock any waiting getters
                DispatchQueue.global(qos: .userInitiated).async {
                    readSemaphore.signal()
                }
                return
            }
            var notifyListeners: () -> Void = {}
            self.initializationLock.lock()
            if self.contextUpdateCount == contextUpdateAtStart || data?.context == self.latestRequestedContext {
                self.flagsData = data
                self._flagsDataVersion.mutate { $0 &+= 1 }
                if data != nil,
                   data?.context == self.latestRequestedContext,
                   self.timedOutInitializationContextUpdate == self.contextUpdateCount {
                    notifyListeners = self.stateManager.updateStateDeferringNotification(.stale)
                }
            }
            self.initializationLock.unlock()
            notifyListeners()

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
        let contextUpdate = beginContextUpdate(for: context)
        let initializationCompletion = makeInitializationCompletion(
            for: context,
            contextUpdate: contextUpdate,
            completion: completion
        )
        contextUpdate.notifyReconciling()

        // Chain after disk read completes to ensure correct hadFlags determination
        whenFlagsDataRead { [weak self] in
            guard let self else {
                if let initializationCompletion {
                    initializationCompletion.complete {
                        let completion = $0
                        return { completion?(.failure(.clientNotInitialized)) }
                    }
                } else {
                    completion(.failure(.clientNotInitialized))
                }
                return
            }

            let hadFlags = self.flagsData != nil
            let cachedContext = self.flagsData?.context
            let flagsDataVersionAtStart = self.flagsDataVersion
            self.flagAssignmentsFetcher.flagAssignments(for: context) { [weak self] result in
                switch result {
                case .success(let flags):
                    guard let self else {
                        if let initializationCompletion {
                            initializationCompletion.complete {
                                let completion = $0
                                return { completion?(.failure(.clientNotInitialized)) }
                            }
                        } else {
                            completion(.failure(.clientNotInitialized))
                        }
                        return
                    }
                    if let initializationCompletion {
                        initializationCompletion.complete { pendingCompletion in
                            let notifyListeners = self.publishSuccess(
                                flags,
                                for: context,
                                contextUpdate: contextUpdate.generation,
                                requireLatest: pendingCompletion == nil
                            )
                            return {
                                pendingCompletion?(.success(()))
                                notifyListeners()
                            }
                        }
                    } else {
                        let notifyListeners = self.publishSuccess(
                            flags,
                            for: context,
                            contextUpdate: contextUpdate.generation,
                            requireLatest: false
                        )
                        notifyListeners()
                        completion(.success(()))
                    }
                case .failure(let error):
                    let finish: (((Result<Void, FlagsError>) -> Void)?) -> () -> Void = { pendingCompletion in
                        let notifyListeners = self?.publishFailure(
                            hadFlags: hadFlags,
                            cachedContext: cachedContext,
                            requestedContext: context,
                            contextUpdate: contextUpdate.generation,
                            flagsDataVersionAtStart: flagsDataVersionAtStart,
                            requireLatest: initializationCompletion != nil && pendingCompletion == nil
                        ) ?? {}
                        return {
                            pendingCompletion?(.failure(error))
                            notifyListeners()
                        }
                    }
                    if let initializationCompletion {
                        initializationCompletion.complete(finish)
                    } else {
                        finish(completion)()
                    }
                }
            }
        }
    }

    func reset() {
        // Clear disk first, then memory, then update state.
        // This prevents race conditions where a listener reacts to the state
        // change and queries the data store before disk is cleared.
        featureScope.flagsDataStore.removeFlagsData(forClientNamed: clientName)
        initializationLock.lock()
        contextUpdateCount &+= 1
        didStartInitialization = false
        latestRequestedContext = nil
        flagsData = nil
        _flagsDataVersion.mutate { $0 &+= 1 }
        timedOutInitializationContextUpdate = nil
        let notifyListeners = stateManager.updateStateDeferringNotification(.notReady)
        initializationLock.unlock()
        notifyListeners()
    }
}
