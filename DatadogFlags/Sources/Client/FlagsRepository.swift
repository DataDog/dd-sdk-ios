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

internal final class FlagsRepository {
    private typealias ContextCompletion = (Result<Void, FlagsError>) -> Void

    private enum Constants {
        static let readTimeout: TimeInterval = 0.1
    }

    private enum InitializationTimeoutPhase {
        case pending
        case claimed
        case published
        case completed
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
    private var pendingContextCompletions: [UInt64: ContextCompletion] = [:]
    private var initializationTimeoutGeneration: UInt64?
    private var initializationTimeoutPhase: InitializationTimeoutPhase?
    private var initializationTimeoutCancellation: FlagsInitializationTimeoutCancellation?
    private var deferredInitializationNetworkCompletion: (() -> Void)?
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

    private func beginContextUpdate(
        for context: FlagsEvaluationContext,
        completion: @escaping ContextCompletion
    ) -> ContextUpdate {
        initializationLock.lock()
        contextUpdateCount &+= 1
        latestRequestedContext = context
        let generation = contextUpdateCount
        let ownsInitialization = !didStartInitialization
        didStartInitialization = true
        pendingContextCompletions[generation] = completion
        if ownsInitialization, initializationTimeout != nil {
            initializationTimeoutGeneration = generation
            initializationTimeoutPhase = .pending
        }
        let notifyReconciling = stateManager.updateStateDeferringNotification(.reconciling)
        initializationLock.unlock()
        return ContextUpdate(
            generation: generation,
            ownsInitialization: ownsInitialization,
            notifyReconciling: notifyReconciling
        )
    }

    private func startInitializationTimeout(
        for context: FlagsEvaluationContext,
        contextUpdate: ContextUpdate
    ) {
        guard contextUpdate.ownsInitialization, let initializationTimeout else {
            return
        }

        let cancelTimeout = scheduleInitializationTimeout(initializationTimeout) { [weak self] in
            self?.initializationDidTimeOut(
                for: context,
                contextUpdate: contextUpdate.generation
            )
        }

        var cancelNow = false
        initializationLock.lock()
        if initializationTimeoutGeneration == contextUpdate.generation,
           initializationTimeoutPhase == .pending {
            initializationTimeoutCancellation = cancelTimeout
        } else {
            cancelNow = true
        }
        initializationLock.unlock()

        if cancelNow {
            cancelTimeout()
        }
    }

    private func initializationDidTimeOut(
        for context: FlagsEvaluationContext,
        contextUpdate: UInt64
    ) {
        var completion: ContextCompletion?
        initializationLock.lock()
        guard initializationTimeoutGeneration == contextUpdate,
              initializationTimeoutPhase == .pending else {
            initializationLock.unlock()
            return
        }
        initializationTimeoutPhase = .claimed
        initializationTimeoutCancellation = nil
        completion = pendingContextCompletions.removeValue(forKey: contextUpdate)
        initializationLock.unlock()

        var notifyListeners: () -> Void = {}
        var deferredNetworkCompletion: (() -> Void)?
        initializationLock.lock()
        if initializationTimeoutGeneration == contextUpdate,
           initializationTimeoutPhase == .claimed {
            initializationTimeoutPhase = .published
            notifyListeners = publishInitializationTimeoutStateLocked(
                for: context,
                contextUpdate: contextUpdate
            )
            deferredNetworkCompletion = deferredInitializationNetworkCompletion
            deferredInitializationNetworkCompletion = nil
        }
        initializationLock.unlock()

        deferredNetworkCompletion?()
        completion?(.failure(.initializationTimedOut))
        notifyListeners()
    }

    private func publishInitializationTimeoutStateLocked(
        for context: FlagsEvaluationContext,
        contextUpdate: UInt64
    ) -> () -> Void {
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

    private func publishSuccessLocked(
        _ flags: [String: FlagAssignment],
        for context: FlagsEvaluationContext
    ) -> () -> Void {
        flagsData = .init(flags: flags, context: context, date: dateProvider.now)
        _flagsDataVersion.mutate { $0 &+= 1 }
        writeState()
        return stateManager.updateStateDeferringNotification(.ready)
    }

    private func publishFailureLocked(
        hadFlags: Bool,
        cachedContext: FlagsEvaluationContext?,
        requestedContext: FlagsEvaluationContext,
        flagsDataVersionAtStart: UInt64
    ) -> () -> Void {
        guard flagsDataVersion == flagsDataVersionAtStart else {
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

    private func finishContextUpdate(
        generation: UInt64,
        result: Result<Void, FlagsError>,
        publishStateLocked: @escaping () -> () -> Void
    ) {
        var timeoutCancellation: FlagsInitializationTimeoutCancellation?
        var completions: [ContextCompletion] = []
        var notifyListeners: () -> Void = {}

        initializationLock.lock()
        guard contextUpdateCount == generation else {
            initializationLock.unlock()
            return
        }

        if initializationTimeoutPhase == .claimed {
            deferredInitializationNetworkCompletion = { [weak self] in
                self?.finishContextUpdate(
                    generation: generation,
                    result: result,
                    publishStateLocked: publishStateLocked
                )
            }
            initializationLock.unlock()
            return
        }

        if initializationTimeoutPhase == .pending {
            initializationTimeoutPhase = .completed
            timeoutCancellation = initializationTimeoutCancellation
            initializationTimeoutCancellation = nil
        }

        notifyListeners = publishStateLocked()
        completions = pendingContextCompletions
            .sorted { $0.key < $1.key }
            .map(\.value)
        pendingContextCompletions.removeAll()
        initializationLock.unlock()

        timeoutCancellation?()
        for completion in completions {
            completion(result)
        }
        notifyListeners()
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

            notifyListeners()

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
        let contextUpdate = beginContextUpdate(
            for: context,
            completion: completion
        )
        startInitializationTimeout(for: context, contextUpdate: contextUpdate)
        contextUpdate.notifyReconciling()

        // Chain after disk read completes to ensure correct hadFlags determination
        whenFlagsDataRead { [weak self] in
            guard let self else {
                completion(.failure(.clientNotInitialized))
                return
            }

            let hadFlags = self.flagsData != nil
            let cachedContext = self.flagsData?.context
            let flagsDataVersionAtStart = self.flagsDataVersion
            self.flagAssignmentsFetcher.flagAssignments(for: context) { [weak self] result in
                guard let self else {
                    completion(.failure(.clientNotInitialized))
                    return
                }
                switch result {
                case .success(let flags):
                    self.finishContextUpdate(
                        generation: contextUpdate.generation,
                        result: .success(()),
                        publishStateLocked: {
                            self.publishSuccessLocked(
                                flags,
                                for: context
                            )
                        }
                    )
                case .failure(let error):
                    self.finishContextUpdate(
                        generation: contextUpdate.generation,
                        result: .failure(error),
                        publishStateLocked: {
                            self.publishFailureLocked(
                                hadFlags: hadFlags,
                                cachedContext: cachedContext,
                                requestedContext: context,
                                flagsDataVersionAtStart: flagsDataVersionAtStart
                            )
                        }
                    )
                }
            }
        }
    }

    func reset() {
        // Clear disk first, then memory, then update state.
        // This prevents race conditions where a listener reacts to the state
        // change and queries the data store before disk is cleared.
        featureScope.flagsDataStore.removeFlagsData(forClientNamed: clientName)
        var timeoutCancellation: FlagsInitializationTimeoutCancellation?
        var pendingCompletions: [ContextCompletion] = []
        initializationLock.lock()
        contextUpdateCount &+= 1
        didStartInitialization = false
        latestRequestedContext = nil
        flagsData = nil
        _flagsDataVersion.mutate { $0 &+= 1 }
        timedOutInitializationContextUpdate = nil
        timeoutCancellation = initializationTimeoutCancellation
        initializationTimeoutCancellation = nil
        initializationTimeoutGeneration = nil
        initializationTimeoutPhase = .completed
        deferredInitializationNetworkCompletion = nil
        pendingCompletions = pendingContextCompletions.values.map { $0 }
        pendingContextCompletions.removeAll()
        let notifyListeners = stateManager.updateStateDeferringNotification(.notReady)
        initializationLock.unlock()
        timeoutCancellation?()
        for completion in pendingCompletions {
            completion(.failure(.clientNotInitialized))
        }
        notifyListeners()
    }
}
