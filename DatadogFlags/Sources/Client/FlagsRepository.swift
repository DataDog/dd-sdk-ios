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
    private let firstFlags: FirstFlagsNotification?
    private let initializationTimeout: TimeInterval?
    private let scheduleInitializationTimeout: FlagsInitializationTimeoutScheduler

    private let initializationLock = NSLock()
    private var didStartInitialization = false

    @ReadWriteLock
    private var flagsData: FlagsData?

    /// Serializes request acceptance, data installation and state publication.
    /// Released before invoking application completions or state listeners.
    private let requestLock = NSLock()
    private var requestVersion: UInt64 = 0
    private var resetVersion: UInt64 = 0

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
        firstFlags: FirstFlagsNotification? = nil,
        scheduleInitializationTimeout: FlagsInitializationTimeoutScheduler? = nil
    ) {
        self.clientName = clientName
        self.flagAssignmentsFetcher = flagAssignmentsFetcher
        self.dateProvider = dateProvider
        self.featureScope = featureScope
        self.initializationTimeout = initializationTimeout
        self.firstFlags = firstFlags
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
        requestVersion: UInt64,
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
            self.requestLock.lock()
            guard self.requestVersion == requestVersion else {
                self.requestLock.unlock()
                completion(.failure(.initializationTimedOut))
                return
            }
            let timeoutState: FlagsClientState = self.flagsData?.context == context ? .stale : .error
            let accepted = self.stateManager.updateState(
                timeoutState,
                unlessCurrentStateIs: [.ready, .stale]
            ) {
                self.requestLock.unlock()
                completion(.failure(.initializationTimedOut))
            }
            if !accepted {
                self.requestLock.unlock()
                completion(.failure(.initializationTimedOut))
            }
        }
        initializationCompletion.armTimeoutCancellation(cancelTimeout)
        return initializationCompletion
    }

    private func readState() {
        let resetVersion = self.resetVersion
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { [weak self, readSemaphore] data in
            guard let self else {
                // Signal even if self is nil to unblock any waiting getters
                DispatchQueue.global(qos: .userInitiated).async {
                    readSemaphore.signal()
                }
                return
            }
            var claimedFirstInstallation = false
            self.requestLock.lock()
            if self.resetVersion == resetVersion {
                self.flagsData = data
                if let data {
                    claimedFirstInstallation = self.firstFlags?.claim(data: data) ?? false
                }
            }
            self.requestLock.unlock()

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

            if claimedFirstInstallation {
                self.firstFlags?.installed()
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
        guard stateManager.currentState != .error else {
            return nil
        }
        return flagsData?.context
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        waitForFlagsDataRead()
        guard stateManager.currentState != .error else {
            return nil
        }
        return flagsData?.flags[key]
    }

    func flagAssignments() -> [String: FlagAssignment]? {
        waitForFlagsDataRead()
        guard stateManager.currentState != .error else {
            return nil
        }
        return flagsData?.flags
    }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        requestLock.lock()
        requestVersion &+= 1
        let version = requestVersion
        requestLock.unlock()

        let initializationCompletion = makeInitializationCompletion(completion, context: context, requestVersion: version) {
            publishReconciling(for: version)
        }
        let takeCompletion: () -> ((Result<Void, FlagsError>) -> Void)? = {
            initializationCompletion?.take()
                ?? (initializationCompletion == nil ? completion : nil)
        }

        whenFlagsDataRead { [weak self] in
            guard let self else {
                takeCompletion()?(.failure(.clientNotInitialized))
                return
            }
            if initializationCompletion == nil {
                self.publishReconciling(for: version)
            }

            self.requestLock.lock()
            guard self.requestVersion == version else {
                self.requestLock.unlock()
                takeCompletion()?(.failure(.clientNotInitialized))
                return
            }
            self.requestLock.unlock()

            self.flagAssignmentsFetcher.flagAssignments(for: context) { [weak self] result in
                guard let self else {
                    takeCompletion()?(.failure(.clientNotInitialized))
                    return
                }
                self.requestLock.lock()
                guard self.requestVersion == version else {
                    self.requestLock.unlock()
                    // Obsolete operations still settle, but cannot publish data or state.
                    takeCompletion()?(.failure(.clientNotInitialized))
                    return
                }
                var claimedFirstInstallation = false
                let newState: FlagsClientState
                let completionResult: Result<Void, FlagsError>
                switch result {
                case .success(let flags):
                    let data = FlagsData(flags: flags, context: context, date: self.dateProvider.now)
                    self.flagsData = data
                    claimedFirstInstallation = self.firstFlags?.claim(data: data) ?? false
                    self.writeState()
                    newState = .ready
                    completionResult = .success(())
                case .failure(let error):
                    if self.flagsData?.context == context {
                        newState = .stale
                    } else {
                        self.flagsData = nil
                        newState = .error
                    }
                    completionResult = .failure(error)
                }
                let operationCompletion = takeCompletion()
                // Publish state before completion: the Swift provider reads it to recognize cache fallback.
                self.stateManager.updateState(newState) {
                    self.requestLock.unlock()
                    if claimedFirstInstallation {
                        self.firstFlags?.installed()
                    }
                    if initializationCompletion != nil {
                        operationCompletion?(completionResult)
                    }
                }
                if initializationCompletion == nil {
                    operationCompletion?(completionResult)
                }
            }
        }
    }

    private func publishReconciling(for version: UInt64) {
        requestLock.lock()
        guard requestVersion == version else {
            requestLock.unlock()
            return
        }
        stateManager.updateState(.reconciling) {
            self.requestLock.unlock()
        }
    }

    func reset() {
        requestLock.lock()
        requestVersion &+= 1
        resetVersion &+= 1
        // Clear disk first, then memory, then update state.
        // This prevents race conditions where a listener reacts to the state
        // change and queries the data store before disk is cleared.
        featureScope.flagsDataStore.removeFlagsData(forClientNamed: clientName)
        flagsData = nil
        stateManager.updateState(.notReady) {
            self.requestLock.unlock()
        }
    }
}
