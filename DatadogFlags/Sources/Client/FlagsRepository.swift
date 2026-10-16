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

    func onFirstFlags(_ listener: @escaping FlagsClientEventListener) -> any FlagsSubscription

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

private struct PendingCacheReadCallback {
    let takeCompletion: () -> InitializationCompletion.Completion?
    let callback: (InitializationCompletion.Completion?) -> Void

    // Claim results before any application callback can delay cancellation of their timeouts.
    func prepare() -> () -> Void {
        let completion = takeCompletion()
        return { callback(completion) }
    }
}

internal final class FlagsRepository {
    let clientName: String
    private let stateManager = FlagsStateManager()
    private let firstFlags = FirstFlagsCallbacks()

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

    @ReadWriteLock
    private var repositoryState = RepositoryState()

    /// Synchronizes assignments, request supersession, and disk-read lifecycle. Client-state transitions
    /// acquire this lock before the state-manager lock; listeners and completions run after unlocking.
    private struct RepositoryState {
        var flagsData: FlagsData?
        var cachedFlagsData: FlagsData?
        /// Advances on accepted fetches and reset; zero means the initial disk read can still apply.
        var flagsDataVersion: UInt64 = 0
        /// Advances on every context request and reset, even when assignments have not changed.
        var contextUpdateID: UInt64 = 0
        var hasStartedEvaluationContextRequest = false
        var latestRequestedContext: FlagsEvaluationContext?
        var pendingDiskReadCallbacks: [PendingCacheReadCallback] = []
        var initialFlagsDataGroup: DispatchGroup? = {
            let group = DispatchGroup()
            group.enter()
            return group
        }()

        var shouldWaitForFlagsDataRead: Bool {
            initialFlagsDataGroup != nil
        }

        mutating func applyInitialFlagsData(_ data: FlagsData?) -> [PendingCacheReadCallback] {
            // A successful fetch or reset supersedes both active and fallback data from disk.
            if flagsDataVersion == 0 {
                cachedFlagsData = data

                let isInitialReadStillAuthoritative = !hasStartedEvaluationContextRequest
                let isReconcilingSameContext = data.map {
                    latestRequestedContext == $0.context
                } ?? false

                if isInitialReadStillAuthoritative || isReconcilingSameContext {
                    flagsData = data
                }
            }

            return finishWaitingForInitialFlagsData()
        }

        mutating func finishWaitingForInitialFlagsData() -> [PendingCacheReadCallback] {
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
        contextUpdateID: UInt64
    ) -> InitializationCompletion? {
        guard let initializationTimeout,
              initializationTimeout.isFinite,
              initializationTimeout > 0 else {
            return nil
        }

        let initializationCompletion = InitializationCompletion(completion: completion)
        let cancelTimeout = scheduleInitializationTimeout(initializationTimeout) { [weak self, initializationCompletion] in
            guard let completion = initializationCompletion.take() else {
                return
            }
            guard let self else {
                completion(.failure(.clientNotInitialized))
                return
            }
            var notifyListeners: (() -> Void)?
            self._repositoryState.mutate { state in
                guard contextUpdateID == state.contextUpdateID else {
                    return
                }
                let timeoutState: FlagsClientState = state.flagsData?.context == context ? .stale : .error
                notifyListeners = self.stateManager.updateStateWithoutNotifying(
                    timeoutState,
                    unlessCurrentStateIs: [.ready, .stale]
                )
            }
            completion(.failure(.initializationTimedOut))
            notifyListeners?()
        }
        initializationCompletion.armTimeoutCancellation(cancelTimeout)
        return initializationCompletion
    }

    private func readState() {
        // Retain the read lifecycle, not the repository, so the group is balanced even after deallocation.
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { [_repositoryState, weak firstFlags] data in
            var cachedData = data
            cachedData?.flags = data?.flags.mapValues { assignment in
                var cachedAssignment = assignment
                cachedAssignment.reason = "CACHED"
                return cachedAssignment
            } ?? [:]
            // Keep the helper alive outside the state lock if repository destruction races this read.
            let firstFlags = firstFlags
            var callbacks: [PendingCacheReadCallback] = []
            var publish: (() -> Void)?
            _repositoryState.mutate { state in
                callbacks = state.applyInitialFlagsData(cachedData)
                publish = state.flagsData.flatMap { firstFlags?.reserve(keys: Array($0.flags.keys)) }
            }

            // Pending failures report `.clientNotInitialized` if the repository has been released.
            let pendingCompletions = callbacks.map { $0.prepare() }
            Self.publishFirstFlags(publish)
            Self.executePendingDiskReadCallbacks(pendingCompletions)
            withExtendedLifetime(firstFlags) {}
        }
    }

    /// Publication follows the internal commit, independently of customer state/context callbacks.
    /// Each broadcast remains sequential, but never occupies storage or network completion queues.
    private static func publishFirstFlags(_ publish: (() -> Void)?) {
        guard let publish else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: DispatchWorkItem(block: publish))
    }

    private static func executePendingDiskReadCallbacks(_ callbacks: [() -> Void]) {
        // Disk reads can release callbacks on DatadogCore's shared read/write queue.
        // Keep callbacks off that queue and independent of other application completions.
        for callback in callbacks {
            DispatchQueue.global(qos: .utility).async {
                callback()
            }
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

    /// Runs immediately if the initial read finished or a fetch or reset superseded it.
    /// Otherwise queues the callback until then; queued callbacks run on a global utility queue.
    /// Used on fetch failure so cached flags can be used without delaying the network request.
    private func whenCacheReady(_ callback: PendingCacheReadCallback) {
        var shouldExecuteNow = false
        _repositoryState.mutate { state in
            if state.shouldWaitForFlagsDataRead {
                state.pendingDiskReadCallbacks.append(callback)
            } else {
                shouldExecuteNow = true
            }
        }

        if shouldExecuteNow {
            callback.prepare()()
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
        contextUpdateID: UInt64,
        versionAtStart: UInt64
    ) -> (() -> Void)? {
        // Only the latest request can select fallback data, unless a success for its
        // context already supplied fresh assignments while it was in flight.
        var notifyListeners: (() -> Void)?
        var publish: (() -> Void)?
        _repositoryState.mutate { state in
            guard contextUpdateID == state.contextUpdateID, state.flagsDataVersion == versionAtStart else {
                return
            }

            let newState: FlagsClientState

            // Only use cached flags if they match the requested context to avoid
            // serving flags from a different user/context.
            if let matchingFlagsData = state.flagsData(matching: context) {
                state.flagsData = matchingFlagsData
                publish = firstFlags.reserve(keys: Array(matchingFlagsData.flags.keys))
                newState = .stale
            } else {
                // Drop active flags to prevent cross-context leakage. Keep the fallback cache:
                // it can only be selected by a later request with a matching context.
                state.flagsData = nil
                newState = .error
            }
            notifyListeners = stateManager.updateStateWithoutNotifying(newState)
        }

        Self.publishFirstFlags(publish)
        return notifyListeners
    }
}

extension FlagsRepository: FlagsRepositoryProtocol {
    var state: FlagsStateObservable { stateManager }

    func onFirstFlags(_ listener: @escaping FlagsClientEventListener) -> any FlagsSubscription {
        firstFlags.register(listener)
    }

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
        var contextUpdateID: UInt64 = 0
        var versionAtStart: UInt64 = 0
        var isFirstContextUpdate = false
        var notifyReconciling: (() -> Void)?
        var publish: (() -> Void)?
        // Request registration, assignments, and client state use the same synchronization boundary.
        // Listener delivery and public completions must remain outside this lock.
        _repositoryState.mutate { state in
            state.contextUpdateID += 1
            contextUpdateID = state.contextUpdateID
            versionAtStart = state.flagsDataVersion
            isFirstContextUpdate = !state.hasStartedEvaluationContextRequest
            state.hasStartedEvaluationContextRequest = true
            state.latestRequestedContext = context
            // Apply the same context check whether the initial disk read wins or loses the race.
            if state.flagsDataVersion == 0 {
                state.flagsData = state.flagsData(matching: context)
                publish = state.flagsData.flatMap { firstFlags.reserve(keys: Array($0.flags.keys)) }
            }
            notifyReconciling = stateManager.updateStateWithoutNotifying(.reconciling)
        }
        Self.publishFirstFlags(publish)
        notifyReconciling?()
        let initializationCompletion = isFirstContextUpdate
            ? makeInitializationCompletion(completion, context: context, contextUpdateID: contextUpdateID)
            : nil
        let takeCompletion = {
            initializationCompletion?.take()
                ?? (initializationCompletion == nil ? completion : nil)
        }
        func complete(
            _ result: Result<Void, FlagsError>,
            notifyListeners: (() -> Void)?,
            completion operationCompletion: InitializationCompletion.Completion?,
            pendingCompletions: [() -> Void] = []
        ) {
            guard let notifyListeners else {
                operationCompletion?(result)
                return
            }

            // Publish state before completion: dd-openfeature-provider-swift reads `currentState`
            // in its failure callback to detect stale assignments. With an initialization timeout,
            // a completion still owned by this helper must also run before listeners.
            Self.executePendingDiskReadCallbacks(pendingCompletions)
            if initializationCompletion != nil {
                operationCompletion?(result)
            }
            notifyListeners()
            if initializationCompletion == nil {
                operationCompletion?(result)
            }
        }

        flagAssignmentsFetcher.flagAssignments(for: context) { [weak self] result in
            guard let self else {
                complete(.failure(.clientNotInitialized), notifyListeners: nil, completion: takeCompletion())
                return
            }

            switch result {
            case .success(let flags):
                // Claim success before processing assignments or publishing ready can race the timeout.
                let operationCompletion = takeCompletion()
                let flagsData = FlagsData(
                    flags: flags,
                    context: context,
                    date: self.dateProvider.now
                )
                var versionAfterSuccess: UInt64?
                var callbacks: [PendingCacheReadCallback] = []
                var notifyListeners: (() -> Void)?
                var publish: (() -> Void)?
                self._repositoryState.mutate { state in
                    // Accept an older success for the current context only if no success or reset
                    // superseded its starting version. The latest request's success always applies.
                    let isLatestRequest = contextUpdateID == state.contextUpdateID
                    let isFreshForLatestContext = state.latestRequestedContext == context
                        && state.flagsDataVersion == versionAtStart
                    guard isLatestRequest || isFreshForLatestContext else {
                        return
                    }
                    state.flagsData = flagsData
                    publish = self.firstFlags.reserve(keys: Array(flags.keys))
                    state.cachedFlagsData = flagsData
                    state.flagsDataVersion += 1
                    versionAfterSuccess = state.flagsDataVersion
                    callbacks = state.finishWaitingForInitialFlagsData()
                    notifyListeners = self.stateManager.updateStateWithoutNotifying(.ready)
                }
                guard let versionAfterSuccess else {
                    complete(.success(()), notifyListeners: nil, completion: operationCompletion)
                    return
                }
                let pendingCompletions = callbacks.map { $0.prepare() }
                Self.publishFirstFlags(publish)
                self.writeState(flagsData, version: versionAfterSuccess)
                complete(
                    .success(()),
                    notifyListeners: notifyListeners,
                    completion: operationCompletion,
                    pendingCompletions: pendingCompletions
                )
            case .failure(let error):
                self.whenCacheReady(PendingCacheReadCallback(takeCompletion: takeCompletion) { [weak self] operationCompletion in
                    guard let self else {
                        complete(.failure(.clientNotInitialized), notifyListeners: nil, completion: operationCompletion)
                        return
                    }

                    let notifyListeners = self.applyFailedContextUpdate(
                        for: context,
                        contextUpdateID: contextUpdateID,
                        versionAtStart: versionAtStart
                    )
                    complete(.failure(error), notifyListeners: notifyListeners, completion: operationCompletion)
                })
            }
        }
    }

    func reset() {
        let flagsDataStore = featureScope.flagsDataStore
        let clientName = clientName
        var callbacks: [PendingCacheReadCallback] = []
        var notifyListeners: (() -> Void)?

        _repositoryState.mutate { state in
            state.flagsData = nil
            state.cachedFlagsData = nil
            state.flagsDataVersion += 1
            state.contextUpdateID += 1
            state.latestRequestedContext = nil
            callbacks = state.finishWaitingForInitialFlagsData()
            notifyListeners = stateManager.updateStateWithoutNotifying(.notReady)
            // Order removal with reset so newer successes enqueue their writes after it.
            cachePersistenceQueue.async {
                flagsDataStore.removeFlagsData(forClientNamed: clientName)
            }
        }
        let pendingCompletions = callbacks.map { $0.prepare() }
        // Drain outside the lock: queued writes read the repository state.
        cachePersistenceQueue.sync {}
        Self.executePendingDiskReadCallbacks(pendingCompletions)
        notifyListeners?()
    }

    func flush() {
        cachePersistenceQueue.sync {}
    }
}
