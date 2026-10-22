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

    func evaluationSnapshot(for key: String) -> FlagEvaluationSnapshot

    func flagAssignments() -> [String: FlagAssignment]?

    func reset()

    func flush()
}

internal struct FlagEvaluationSnapshot {
    let context: FlagsEvaluationContext?
    let assignment: FlagAssignment?
    let telemetryOptedOut: Bool
}

/// Retain decisions only while their subjects have installed or pending assignments.
internal struct SubjectTelemetryPolicy {
    private var requestedSubject: String?
    private var decisions: [String: Bool] = [:]
    private var pending: [String: Int] = [:]

    mutating func begin(_ context: FlagsEvaluationContext, installed: FlagsEvaluationContext?) {
        requestedSubject = context.targetingKey
        decisions[context.targetingKey] = Self.isOptedOut(context)
        pending[context.targetingKey, default: 0] += 1
        prune(installed: installed)
    }

    mutating func finish(_ subject: String, installed: FlagsEvaluationContext?) {
        if let count = pending[subject] {
            pending[subject] = count > 1 ? count - 1 : nil
        }
        prune(installed: installed)
    }

    mutating func install(_ context: FlagsEvaluationContext?) {
        if let context, decisions[context.targetingKey] == nil {
            decisions[context.targetingKey] = Self.isOptedOut(context)
        }
        prune(installed: context)
    }

    func isOptedOut(evaluating context: FlagsEvaluationContext?) -> Bool {
        let requested = requestedSubject.flatMap { decisions[$0] } ?? false
        let evaluated = context.map { decisions[$0.targetingKey] ?? Self.isOptedOut($0) } ?? false
        return requested || evaluated
    }

    private mutating func prune(installed: FlagsEvaluationContext?) {
        decisions = decisions.filter {
            $0.key == requestedSubject || $0.key == installed?.targetingKey || pending[$0.key] != nil
        }
    }

    private static func isOptedOut(_ context: FlagsEvaluationContext) -> Bool {
        context.attributes["dd_evaluation_telemetry_opt_out"] == .bool(true)
    }
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

    struct CachedFlagsData {
        enum LookupResult: Equatable {
            case resolved(FlagAssignment?)
            case missingHash
        }

        static let lookupCacheLimit = 1_024
        let data: FlagsData
        // Swift String equality treats canonically equivalent Unicode sequences as equal.
        private(set) var lookupKeys: [Data: String] = [:]

        func cachedAssignment(for key: String, supportsObfuscation: Bool) -> LookupResult {
            guard data.obfuscation != nil else {
                return .resolved(data.flags[key])
            }
            guard supportsObfuscation else {
                return .resolved(nil)
            }
            guard let lookupKey = lookupKeys[Data(key.utf8)] else {
                return .missingHash
            }
            return .resolved(data.flags[lookupKey])
        }

        mutating func flagAssignment(for key: String) -> FlagAssignment? {
            guard let obfuscation = data.obfuscation else {
                return data.flags[key]
            }
            let keyBytes = Data(key.utf8)
            if let lookupKey = lookupKeys[keyBytes] {
                return data.flags[lookupKey]
            }
            let lookupKey = obfuscation.lookupKey(for: key)
            if lookupKeys.count >= Self.lookupCacheLimit { lookupKeys.removeAll(keepingCapacity: true) }
            lookupKeys[keyBytes] = lookupKey
            return data.flags[lookupKey]
        }
    }

    /// Synchronizes assignments, request supersession, and disk-read lifecycle. Client-state transitions
    /// acquire this lock before the state-manager lock; listeners and completions run after unlocking.
    private struct RepositoryState {
        var telemetry = SubjectTelemetryPolicy()
        var activeFlagsData: CachedFlagsData?
        var flagsData: FlagsData? {
            get { activeFlagsData?.data }
            // Replace assignments and lookup hashes together under the repository lock.
            set {
                activeFlagsData = newValue.map { CachedFlagsData(data: $0) }
                telemetry.install(newValue?.context)
            }
        }
        var cachedFlagsData: FlagsData?
        // A missing or delayed context must not expose encoded assignments to legacy bridges.
        var supportsFlagKeyObfuscation = false

        var readableFlagsData: FlagsData? {
            guard let data = flagsData, data.obfuscation == nil || supportsFlagKeyObfuscation else {
                return nil
            }
            return data
        }
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
        featureScope.context { [weak self] context in
            self?._repositoryState.mutate { state in
                state.supportsFlagKeyObfuscation = FlagKeyObfuscation.isSupported(source: context.source)
            }
        }
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
                let timeoutState: FlagsClientState = state.readableFlagsData?.context == context ? .stale : .error
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
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { [_repositoryState] data in
            var cachedData = data
            cachedData?.flags = data?.flags.mapValues { assignment in
                var cachedAssignment = assignment
                cachedAssignment.reason = "CACHED"
                return cachedAssignment
            } ?? [:]
            var callbacks: [PendingCacheReadCallback] = []
            _repositoryState.mutate { state in
                callbacks = state.applyInitialFlagsData(cachedData)
            }

            // Pending failures report `.clientNotInitialized` if the repository has been released.
            Self.executePendingDiskReadCallbacks(callbacks.map { $0.prepare() })
        }
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

            flagsDataStore.setEncodedFlagsData(encodedFlagsData.data, forClientNamed: clientName, version: encodedFlagsData.version)
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
        _repositoryState.mutate { state in
            guard contextUpdateID == state.contextUpdateID, state.flagsDataVersion == versionAtStart else {
                return
            }

            let newState: FlagsClientState

            // Only use cached flags if they match the requested context to avoid
            // serving flags from a different user/context.
            if let matchingFlagsData = state.flagsData(matching: context),
               matchingFlagsData.obfuscation == nil || state.supportsFlagKeyObfuscation {
                state.flagsData = matchingFlagsData
                newState = .stale
            } else {
                // Drop active flags to prevent cross-context leakage. Keep the fallback cache:
                // it can only be selected by a later request with a matching context.
                state.flagsData = nil
                newState = .error
            }
            notifyListeners = stateManager.updateStateWithoutNotifying(newState)
        }

        return notifyListeners
    }
}

extension FlagsRepository: FlagsRepositoryProtocol {
    var state: FlagsStateObservable { stateManager }

    var context: FlagsEvaluationContext? {
        waitForFlagsDataRead()
        guard stateManager.currentState != .error else {
            return nil
        }
        return repositoryState.readableFlagsData?.context
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        evaluationSnapshot(for: key).assignment
    }

    func evaluationSnapshot(for key: String) -> FlagEvaluationSnapshot {
        waitForFlagsDataRead()
        let hasError = stateManager.currentState == .error
        let snapshot = repositoryState

        func result(from state: RepositoryState, assignment: FlagAssignment?) -> FlagEvaluationSnapshot {
            let readable = !hasError && (state.flagsData?.obfuscation == nil || state.supportsFlagKeyObfuscation)
            let context = readable ? state.flagsData?.context : nil
            return FlagEvaluationSnapshot(
                context: context,
                assignment: readable ? assignment : nil,
                // Unreadable assignments must not discard the stored subject's reporting policy.
                telemetryOptedOut: state.telemetry.isOptedOut(evaluating: state.flagsData?.context)
            )
        }

        guard !hasError else {
            return result(from: snapshot, assignment: nil)
        }
        switch snapshot.activeFlagsData?.cachedAssignment(for: key, supportsObfuscation: snapshot.supportsFlagKeyObfuscation) {
        case .resolved(let assignment): return result(from: snapshot, assignment: assignment)
        case nil: return result(from: snapshot, assignment: nil)
        case .missingHash: break
        }

        var resolved = result(from: snapshot, assignment: nil)
        _repositoryState.mutate { state in
            // A refresh or reset can replace the snapshot after the read. Recheck it under the write lock.
            var assignment: FlagAssignment?
            if state.flagsData?.obfuscation == nil || state.supportsFlagKeyObfuscation {
                assignment = state.activeFlagsData?.flagAssignment(for: key)
            }
            resolved = result(from: state, assignment: assignment)
        }
        return resolved
    }

    func flagAssignments() -> [String: FlagAssignment]? {
        waitForFlagsDataRead()
        guard stateManager.currentState != .error,
              let data = repositoryState.readableFlagsData,
              data.obfuscation == nil else {
            return nil
        }
        return data.flags
    }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        var contextUpdateID: UInt64 = 0
        var versionAtStart: UInt64 = 0
        var isFirstContextUpdate = false
        var notifyReconciling: (() -> Void)?
        // Request registration, assignments, and client state use the same synchronization boundary.
        // Listener delivery and public completions must remain outside this lock.
        _repositoryState.mutate { state in
            state.telemetry.begin(context, installed: state.flagsData?.context)
            state.contextUpdateID += 1
            contextUpdateID = state.contextUpdateID
            versionAtStart = state.flagsDataVersion
            isFirstContextUpdate = !state.hasStartedEvaluationContextRequest
            state.hasStartedEvaluationContextRequest = true
            state.latestRequestedContext = context
            // Apply the same context check whether the initial disk read wins or loses the race.
            if state.flagsDataVersion == 0 {
                state.flagsData = state.flagsData(matching: context)
            }
            notifyReconciling = stateManager.updateStateWithoutNotifying(.reconciling)
        }
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

            // A public initialization timeout does not terminate this request.
            defer {
                self._repositoryState.mutate { state in
                    state.telemetry.finish(context.targetingKey, installed: state.flagsData?.context)
                }
            }

            switch result {
            case .success(let response):
                // Claim success before processing assignments or publishing ready can race the timeout.
                let operationCompletion = takeCompletion()
                let flagsData = FlagsData(
                    flags: response.flags,
                    context: context,
                    date: self.dateProvider.now,
                    obfuscation: response.obfuscation
                )
                var versionAfterSuccess: UInt64?
                var callbacks: [PendingCacheReadCallback] = []
                var notifyListeners: (() -> Void)?
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
