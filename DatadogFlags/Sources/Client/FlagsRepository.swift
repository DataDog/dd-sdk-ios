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

    func onFirstFlags(_ listener: @escaping FlagsClientEventListener) -> any FlagsSubscription
    func assignmentsSnapshot() -> FlagsData?

    func reset()

    func flush()
}

internal struct FlagEvaluationSnapshot {
    let context: FlagsEvaluationContext?
    let assignment: FlagAssignment?
    let telemetryOptedOut: Bool
    let observeFullEvaluationData: Bool
    var requestedContext: FlagsEvaluationContext? = nil
    var error: FlagEvaluationError? = nil
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
    private let firstFlags = FirstFlagsCallbacks()
    private let requestDiagnostics = FlagsRequestDiagnostics()

    private let flagAssignmentsFetcher: any FlagAssignmentsFetching
    private let dateProvider: any DateProvider
    private let featureScope: any FeatureScope
    private let flagSelection: CanonicalFlagSelection?
    private let readTimeout: TimeInterval
    private let cachePersistenceQueue = DispatchQueue(
        label: "com.datadoghq.ios-sdk-flags-cache-persistence",
        autoreleaseFrequency: .workItem,
        target: .global(qos: .utility)
    )
    private let initializationTimeout: TimeInterval?
    private let scheduleInitializationTimeout: FlagsInitializationTimeoutScheduler
    private let scheduleExpiry: (TimeInterval, @escaping () -> Void) -> Void
    private let experimentationOptOutMode: FlagsClient.ExperimentationOptOutMode

    @ReadWriteLock
    private var repositoryState = RepositoryState()

    struct CachedFlagsData {
        enum LookupResult: Equatable {
            case resolved(FlagAssignment?)
            /// The response served the key, but its assignment cannot be parsed.
            case unparsed
            case missingHash
        }

        static let lookupCacheLimit = 1_024
        let data: FlagsData
        // Swift String equality treats canonically equivalent Unicode sequences as equal.
        private(set) var lookupKeys: [Data: String] = [:]

        func cachedAssignment(for key: String, supportsObfuscation: Bool) -> LookupResult {
            guard data.obfuscation != nil else {
                if let assignment = plaintextAssignment(for: key) {
                    return .resolved(assignment)
                }
                return data.unparsedFlagKeys.contains { $0.utf8.elementsEqual(key.utf8) } ? .unparsed : .resolved(nil)
            }
            guard supportsObfuscation else {
                return .resolved(nil)
            }
            guard let lookupKey = lookupKeys[Data(key.utf8)] else {
                return .missingHash
            }
            if let assignment = data.flags[lookupKey] {
                return .resolved(assignment)
            }
            return data.unparsedFlagKeys.contains(lookupKey) ? .unparsed : .resolved(nil)
        }

        mutating func flagAssignment(for key: String) -> FlagAssignment? {
            guard let obfuscation = data.obfuscation else {
                return plaintextAssignment(for: key)
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

        /// Plaintext keys match byte for byte, like encoded keys. A `String` dictionary lookup alone would also
        /// return the assignment of a canonically equivalent spelling.
        private func plaintextAssignment(for key: String) -> FlagAssignment? {
            if let index = data.flags.index(forKey: key), data.flags[index].key.utf8.elementsEqual(key.utf8) {
                return data.flags[index].value
            }
            return data.keySpellings.first { $0.key.utf8.elementsEqual(key.utf8) }?.assignment
        }
    }

    /// Synchronizes assignments, request supersession, and disk-read lifecycle. Client-state transitions
    /// acquire this lock before the state-manager lock; listeners and completions run after unlocking.
    private struct StateBeforeVerifiedExpiry {
        let state: FlagsClientState
        let updateCount: UInt64
        let flagsDataVersion: UInt64
    }

    private struct RepositoryState {
        var experimentationOptOutMode: FlagsClient.ExperimentationOptOutMode = .disabled
        var requestedOptOut: ExperimentationOptOut?
        var hasInvalidContext = false
        /// A usable token or explicit authorization rejection requires assignments to match the requested subject.
        /// The boundary survives failures until an eligible fallback or fresh response is installed.
        var assignmentSubjectIsolationRequired = false
        /// Tokens can change without changing the sanitized targeting context. Once authorization
        /// is observed, only the latest request may install assignments, even after recovery.
        var hasObservedAssignmentAuthorization = false
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
        // Observation data never replaces this process-local verified fallback.
        var verifiedFlagsData: FlagsData?
        /// Required mode: the state before proof expiry or a backward clock step changed it. It is valid only while
        /// no other state update and no new install happened.
        var stateBeforeVerifiedExpiry: StateBeforeVerifiedExpiry?
        // A missing or delayed context must not expose encoded assignments to legacy bridges.
        var supportsFlagKeyObfuscation = false

        var readableFlagsData: FlagsData? {
            guard let data = flagsData, data.obfuscation == nil || supportsFlagKeyObfuscation else {
                return nil
            }
            if experimentationOptOutMode != .disabled {
                guard !hasInvalidContext,
                      latestRequestedContext == data.context,
                      requestedOptOut == data.experimentationOptOutPolicy else { return nil }
            } else if data.experimentationOptOutPolicy != nil {
                return nil
            }
            if assignmentSubjectIsolationRequired {
                guard let requestedContext = latestRequestedContext,
                      data.context.targetingKey.utf8.elementsEqual(requestedContext.targetingKey.utf8) else { return nil }
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
                let isReconcilingSameContext = data.map { data in
                    latestRequestedContext.map {
                        isEligible(data, for: $0, allowingSameSubject: assignmentSubjectIsolationRequired)
                    } ?? false
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

        func flagsData(matching context: FlagsEvaluationContext, allowingSameSubject: Bool = false) -> FlagsData? {
            if let data = flagsData, isEligible(data, for: context, allowingSameSubject: allowingSameSubject) {
                return data
            }
            if let data = cachedFlagsData, isEligible(data, for: context, allowingSameSubject: allowingSameSubject) {
                return data
            }
            return nil
        }

        private func isEligible(
            _ data: FlagsData,
            for context: FlagsEvaluationContext,
            allowingSameSubject: Bool
        ) -> Bool {
            guard data.experimentationOptOutPolicy == requestedOptOut else {
                return false
            }
            if allowingSameSubject {
                // Subject identities are opaque: Swift's canonical Unicode equivalence must not
                // merge distinct targeting keys accepted by the assignment service.
                guard data.context.targetingKey.utf8.elementsEqual(context.targetingKey.utf8) else {
                    return false
                }
                return experimentationOptOutMode == .disabled || data.context == context
            }
            return data.context == context
        }
    }

    init(
        clientName: String,
        flagAssignmentsFetcher: any FlagAssignmentsFetching,
        dateProvider: any DateProvider,
        featureScope: any FeatureScope,
        flagSelection: CanonicalFlagSelection?,
        readTimeout: TimeInterval = 0.1,
        initializationTimeout: TimeInterval? = Flags.Configuration.defaultInitializationTimeout,
        scheduleInitializationTimeout: FlagsInitializationTimeoutScheduler? = nil,
        experimentationOptOutMode: FlagsClient.ExperimentationOptOutMode = .disabled,
        scheduleExpiry: ((TimeInterval, @escaping () -> Void) -> Void)? = nil
    ) {
        self.clientName = clientName
        self.flagAssignmentsFetcher = flagAssignmentsFetcher
        self.dateProvider = dateProvider
        self.featureScope = featureScope
        self.flagSelection = flagSelection
        self.readTimeout = readTimeout
        self.initializationTimeout = initializationTimeout
        self.experimentationOptOutMode = experimentationOptOutMode
        self.repositoryState = RepositoryState(experimentationOptOutMode: experimentationOptOutMode)
        self.scheduleInitializationTimeout = scheduleInitializationTimeout ?? Self.scheduleInitializationTimeout
        // Wall time keeps counting while the device sleeps.
        self.scheduleExpiry = scheduleExpiry ?? { delay, work in
            // Two deadlines, and the first one applies the expiry. The monotonic deadline is not delayed by a wall clock
            // step back. The wall deadline counts the time that the device sleeps. Applying the expiry twice is safe.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: work)
            DispatchQueue.global(qos: .utility).asyncAfter(wallDeadline: .now() + delay, execute: work)
        }
        featureScope.context { [weak self] context in
            guard let self else {
                return
            }
            var publish: (() -> Void)?
            self._repositoryState.mutate { state in
                state.supportsFlagKeyObfuscation = FlagKeyObfuscation.isSupported(source: context.source)
                publish = state.readableFlagsData.flatMap { self.firstFlags.reserve(keys: $0.allFlagKeys) }
            }
            Self.publishFirstFlags(publish)
        }
        readState()
    }

    deinit {
        firstFlags.invalidate()
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
                let hasEligibleAssignments = state.assignmentSubjectIsolationRequired
                    ? state.readableFlagsData != nil
                    : state.readableFlagsData?.context == context
                let timeoutState: FlagsClientState = hasEligibleAssignments ? .stale : .error
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

    private func canUseSigned(_ data: FlagsData?, matching context: FlagsEvaluationContext?, at now: Date? = nil) -> Bool {
        guard flagAssignmentsFetcher.responseSigningMode != .off else {
            return true
        }
        guard let data, let scope = flagAssignmentsFetcher.responseSigningCacheScope,
            data.responseSigningCacheScope == scope
        else {
            return false
        }
        guard flagAssignmentsFetcher.responseSigningMode == .required else {
            return true
        }
        // A proof binds the request bytes, so required mode matches contexts by their wire identity.
        guard let context, data.context.hasSameWireIdentity(as: context) else {
            return false
        }
        return flagAssignmentsFetcher.isTrusted(data.verification, at: now ?? dateProvider.now)
    }

    /// Required mode only. When the installed proof expires, `ready` becomes `stale`, or `ready` and `stale`
    /// become `error` when `expireVerifiedFlags` is set. Reads and an expiry timer call this.
    ///
    /// It also applies while a refresh is reconciling, and keeps the pending request. When the clock returns into
    /// the proof window, the client gets back the state from before this rule changed it, if nothing else changed
    /// the state in between. Otherwise a client in `error` recovers to `ready` (or `stale` when not fresh).
    private func applyVerifiedExpiry() {
        guard flagAssignmentsFetcher.responseSigningMode == .required else {
            return
        }
        let now = dateProvider.now
        // Most reads change nothing: decide under the read lock first, and take the write lock only for a change.
        let snapshot = repositoryState
        if let data = snapshot.flagsData, data.verification != nil {
            guard needsVerifiedExpiryUpdate(snapshot, data: data, now: now) else {
                return
            }
        } else {
            return
        }
        var notifyListeners: (() -> Void)?
        _repositoryState.mutate { state in
            let current = stateManager.currentState
            guard let data = state.flagsData, data.verification != nil else {
                return
            }
            let verified = flagAssignmentsFetcher.isVerified(data.verification, at: now)
            let trusted = flagAssignmentsFetcher.isTrusted(data.verification, at: now)
            if let before = state.stateBeforeVerifiedExpiry {
                if before.updateCount != stateManager.updateCount || before.flagsDataVersion != state.flagsDataVersion {
                    // Another update happened after this rule changed the state. Use the rules below.
                    state.stateBeforeVerifiedExpiry = nil
                } else if verified {
                    // The clock returned into the proof window: restore the state from before this rule changed it.
                    state.stateBeforeVerifiedExpiry = nil
                    guard canUseSigned(data, matching: state.latestRequestedContext) else {
                        return
                    }
                    notifyListeners = stateManager.updateStateWithoutNotifying(before.state)
                    return
                }
            }
            let newState: FlagsClientState
            switch current {
            case .ready, .stale, .reconciling:
                guard !verified else {
                    return
                }
                newState = trusted ? .stale : .error
                // A failed refresh can already be `stale`; expiry only moves it further, to `error`.
                if current == .stale && newState == .stale {
                    return
                }
            case .error:
                // Recover only the installed, trusted proof of the requested context.
                guard trusted, canUseSigned(data, matching: state.latestRequestedContext) else {
                    return
                }
                newState = verified ? .ready : .stale
            case .notReady:
                return
            }
            guard newState != current else {
                return
            }
            notifyListeners = stateManager.updateStateWithoutNotifying(newState)
            state.stateBeforeVerifiedExpiry = current == .error ? nil : StateBeforeVerifiedExpiry(
                state: current,
                updateCount: stateManager.updateCount,
                flagsDataVersion: state.flagsDataVersion
            )
        }
        notifyListeners?()
    }

    /// A read-only test for `applyVerifiedExpiry`: `true` when its write-lock pass can change something.
    private func needsVerifiedExpiryUpdate(_ state: RepositoryState, data: FlagsData, now: Date) -> Bool {
        let verified = flagAssignmentsFetcher.isVerified(data.verification, at: now)
        if let before = state.stateBeforeVerifiedExpiry {
            let isCurrent = before.updateCount == stateManager.updateCount && before.flagsDataVersion == state.flagsDataVersion
            if !isCurrent || verified {
                return true
            }
        }
        switch stateManager.currentState {
        case .ready, .reconciling:
            return !verified
        case .stale:
            return !verified && !flagAssignmentsFetcher.isTrusted(data.verification, at: now)
        case .error:
            return flagAssignmentsFetcher.isTrusted(data.verification, at: now)
                && canUseSigned(data, matching: state.latestRequestedContext)
        case .notReady:
            return false
        }
    }

    private func scheduleVerifiedExpiry(for data: FlagsData) {
        guard flagAssignmentsFetcher.responseSigningMode == .required, let verification = data.verification else {
            return
        }
        let delay = max(0, verification.expiresAt - verification.effectiveTime(at: dateProvider.now))
        scheduleExpiry(delay) { [weak self] in self?.applyVerifiedExpiry() }
    }

    private func readState() {
        let fetcher = flagAssignmentsFetcher
        let store = featureScope.flagsDataStore
        let clientName = clientName
        // Retain the read lifecycle, not the repository, so the group is balanced after deallocation.
        let finish: (FlagsData?) -> Void = { [_repositoryState, weak firstFlags, flagSelection] data in
            var cachedData = data?.flagSelection == flagSelection ? data : nil
            if let context = cachedData?.context {
                cachedData?.context = context.extractingAssignmentAuthorization().context
            }
            cachedData?.flags = data?.flags.mapValues { assignment in
                var cachedAssignment = assignment
                cachedAssignment.reason = "CACHED"
                return cachedAssignment
            } ?? [:]
            cachedData?.keySpellings = data?.keySpellings.map { spelling in
                var cachedSpelling = spelling
                cachedSpelling.assignment.reason = "CACHED"
                return cachedSpelling
            } ?? []
            // Keep the helper alive outside the state lock if repository destruction races this read.
            let firstFlags = firstFlags
            var callbacks: [PendingCacheReadCallback] = []
            var publish: (() -> Void)?
            _repositoryState.mutate { state in
                if fetcher.responseSigningMode != .off,
                    cachedData?.responseSigningCacheScope != fetcher.responseSigningCacheScope {
                    cachedData = nil
                }
                callbacks = state.applyInitialFlagsData(cachedData)
                publish = state.readableFlagsData.flatMap { firstFlags?.reserve(keys: $0.allFlagKeys) }
            }
            let pendingCompletions = callbacks.map { $0.prepare() }
            Self.publishFirstFlags(publish)
            Self.executePendingDiskReadCallbacks(pendingCompletions)
            withExtendedLifetime(firstFlags) {}
        }
        switch fetcher.responseSigningMode {
        case .off:
            store.flagsData(forClientNamed: clientName, callback: finish)
        case .required:
            finish(nil)
        case .observe:
            fetcher.resolveResponseSigningCacheScope { scope in
                guard let scope, scope == fetcher.responseSigningCacheScope else {
                    finish(nil)
                    return
                }
                let key = FlagsResponseVerifier.cacheKey(clientName: clientName)
                store.flagsData(forClientNamed: key) { data in
                    guard data?.responseSigningCacheScope == scope, scope == fetcher.responseSigningCacheScope else {
                        finish(nil)
                        return
                    }
                    finish(data)
                }
            }
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

    private func writeState(_ flagsData: FlagsData, version: UInt64, contextUpdateID: UInt64) {
        guard flagAssignmentsFetcher.responseSigningMode != .required else {
            return
        }
        let flagsDataStore = featureScope.flagsDataStore
        let clientName: String
        if flagAssignmentsFetcher.responseSigningMode == .off {
            clientName = self.clientName
        } else {
            guard let scope = flagsData.responseSigningCacheScope,
                scope == flagAssignmentsFetcher.responseSigningCacheScope
            else {
                return
            }
            clientName = FlagsResponseVerifier.cacheKey(clientName: self.clientName)
        }

        cachePersistenceQueue.async { [weak self] in
            guard let self, self.canUseSigned(flagsData, matching: flagsData.context),
                self.repositoryState.flagsDataVersion == version,
                self.flagAssignmentsFetcher.responseSigningMode == .off
                    || self.repositoryState.contextUpdateID == contextUpdateID
            else {
                return
            }

            guard let encodedFlagsData = flagsDataStore.encodeFlagsData(flagsData) else {
                return
            }

            guard self.canUseSigned(flagsData, matching: flagsData.context),
                self.repositoryState.flagsDataVersion == version,
                self.flagAssignmentsFetcher.responseSigningMode == .off
                    || self.repositoryState.contextUpdateID == contextUpdateID
            else {
                return
            }

            flagsDataStore.setEncodedFlagsData(encodedFlagsData.data, forClientNamed: clientName, version: encodedFlagsData.version)
        }
    }

    private func applyFailedContextUpdate(
        for context: FlagsEvaluationContext,
        error: FlagsError,
        contextUpdateID: UInt64,
        versionAtStart: UInt64
    ) -> (() -> Void)? {
        // Only the latest request can select fallback data, unless a success for its
        // context already supplied fresh assignments while it was in flight.
        var notifyListeners: (() -> Void)?
        var publish: (() -> Void)?
        _repositoryState.mutate { state in
            guard contextUpdateID == state.contextUpdateID else {
                return
            }
            if state.flagsDataVersion != versionAtStart {
                // A no-token success for the same context can precede the first typed rejection.
                // That rejection still needs to select a stale fallback and publish its state.
                guard case .assignmentAuthorizationFailed = error else {
                    return
                }
            }

            if case .assignmentAuthorizationFailed = error {
                state.assignmentSubjectIsolationRequired = true
                state.hasObservedAssignmentAuthorization = true
            }

            let newState: FlagsClientState

            // Only use cached flags if they match the requested context to avoid
            // serving flags from a different user/context.
            let verified = state.verifiedFlagsData.flatMap { data in
                data.context.hasSameWireIdentity(as: context)
                    && data.experimentationOptOutPolicy == state.requestedOptOut
                    && flagAssignmentsFetcher.isTrusted(data.verification, at: dateProvider.now)
                    ? data : nil
            }
            if let matchingFlagsData = verified ?? state.flagsData(
                matching: context,
                allowingSameSubject: state.assignmentSubjectIsolationRequired
            ),
                canUseSigned(matchingFlagsData, matching: context),
                matchingFlagsData.obfuscation == nil || state.supportsFlagKeyObfuscation {
                state.flagsData = matchingFlagsData
                // An eligible fallback re-establishes a usable assignment set.
                state.assignmentSubjectIsolationRequired = false
                publish = firstFlags.reserve(keys: matchingFlagsData.allFlagKeys)
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
        applyVerifiedExpiry()
        guard stateManager.currentState != .error else {
            return nil
        }
        let state = repositoryState
        guard canUseSigned(state.readableFlagsData, matching: state.latestRequestedContext) else {
            return nil
        }
        return state.readableFlagsData?.context
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        evaluationSnapshot(for: key).assignment
    }

    func evaluationSnapshot(for key: String) -> FlagEvaluationSnapshot {
        waitForFlagsDataRead()
        applyVerifiedExpiry()
        let hasError = stateManager.currentState == .error
        let snapshot = repositoryState

        func result(from state: RepositoryState, assignment: FlagAssignment?, unparsed: Bool = false) -> FlagEvaluationSnapshot {
            let readable = !hasError && state.readableFlagsData != nil
                && canUseSigned(state.readableFlagsData, matching: state.latestRequestedContext)
            let context = readable ? state.flagsData?.context : nil
            let authorizationError = state.assignmentSubjectIsolationRequired && !readable
            // Until a context is requested, a pending cache read may still contain an opt-out.
            let isPolicyLoading = state.shouldWaitForFlagsDataRead && state.latestRequestedContext == nil
            let telemetryContext = state.experimentationOptOutMode == .disabled
                ? state.flagsData?.context : (state.latestRequestedContext ?? state.flagsData?.context)
            return FlagEvaluationSnapshot(
                context: context,
                assignment: readable ? assignment : nil,
                // Unreadable assignments must not discard the stored subject's reporting policy.
                telemetryOptedOut: isPolicyLoading || state.telemetry.isOptedOut(evaluating: telemetryContext),
                observeFullEvaluationData: readable ? (state.flagsData?.observeFullEvaluationData ?? false) : false,
                requestedContext: state.experimentationOptOutMode == .disabled && !authorizationError
                    ? nil : state.latestRequestedContext,
                error: state.hasInvalidContext ? .invalidContext
                    : (authorizationError ? .general : (readable && unparsed ? .parseError : nil))
            )
        }

        guard !hasError else {
            return result(from: snapshot, assignment: nil)
        }
        switch snapshot.activeFlagsData?.cachedAssignment(for: key, supportsObfuscation: snapshot.supportsFlagKeyObfuscation) {
        case .resolved(let assignment): return result(from: snapshot, assignment: assignment)
        case .unparsed: return result(from: snapshot, assignment: nil, unparsed: true)
        case nil: return result(from: snapshot, assignment: nil)
        case .missingHash: break
        }

        var resolved = result(from: snapshot, assignment: nil)
        _repositoryState.mutate { state in
            // A refresh or reset can replace the snapshot after the read. Recheck it under the write lock.
            var assignment: FlagAssignment?
            var unparsed = false
            if state.flagsData?.obfuscation == nil || state.supportsFlagKeyObfuscation {
                assignment = state.activeFlagsData?.flagAssignment(for: key)
                // `flagAssignment(for:)` stored the lookup key, so this lookup resolves without hashing again.
                unparsed = assignment == nil
                    && state.activeFlagsData?.cachedAssignment(for: key, supportsObfuscation: true) == .unparsed
            }
            resolved = result(from: state, assignment: assignment, unparsed: unparsed)
        }
        return resolved
    }

    func flagAssignments() -> [String: FlagAssignment]? {
        assignmentsSnapshot()?.flags
    }

    func assignmentsSnapshot() -> FlagsData? {
        waitForFlagsDataRead()
        applyVerifiedExpiry()
        let snapshot = repositoryState
        guard stateManager.currentState != .error,
            let data = snapshot.readableFlagsData,
            canUseSigned(data, matching: snapshot.latestRequestedContext),
            data.obfuscation == nil
        else {
            return nil
        }
        return data
    }

    func setEvaluationContext(
        _ context: FlagsEvaluationContext,
        completion: @escaping (Result<Void, FlagsError>) -> Void
    ) {
        let authorization = context.extractingAssignmentAuthorization()
        let context = authorization.context
        if authorization.shouldWarn {
            DD.logger.warn(AssignmentAuthorization.unusableTokenWarning)
        }
        let parsedPolicy = Result { try context.experimentationOptOut(mode: experimentationOptOutMode) }
        let policy = try? parsedPolicy.get()
        let invalidContext = if case .failure = parsedPolicy { true } else { false }
        var diagnostics: FlagsRequestDiagnostics.Snapshot?
        var contextUpdateID: UInt64 = 0
        var versionAtStart: UInt64 = 0
        var isFirstContextUpdate = false
        var notifyReconciling: (() -> Void)?
        var publish: (() -> Void)?
        // Request registration, assignments, and client state use the same synchronization boundary.
        // Listener delivery and public completions must remain outside this lock.
        _repositoryState.mutate { state in
            diagnostics = requestDiagnostics.accept()
            state.telemetry.begin(context, installed: state.flagsData?.context)
            state.contextUpdateID += 1
            contextUpdateID = state.contextUpdateID
            versionAtStart = state.flagsDataVersion
            isFirstContextUpdate = !state.hasStartedEvaluationContextRequest
            // The first call consumes the initialization timeout even when it sends no request.
            state.hasStartedEvaluationContextRequest = true
            state.latestRequestedContext = context
            state.requestedOptOut = policy
            state.hasInvalidContext = invalidContext
            state.hasObservedAssignmentAuthorization = state.hasObservedAssignmentAuthorization || authorization.token != nil
            state.assignmentSubjectIsolationRequired = state.assignmentSubjectIsolationRequired || authorization.token != nil
            if invalidContext {
                // Retain the last successful snapshot for a later valid context or offline restart.
                state.telemetry.finish(context.targetingKey, installed: state.flagsData?.context)
                notifyReconciling = stateManager.updateStateWithoutNotifying(.error)
                return
            }
            // Once authorization isolation is active, immediately install only an eligible retained
            // subject. This lets a return to that subject recover during the network request while
            // keeping another subject's assignments unreadable.
            if state.assignmentSubjectIsolationRequired {
                state.flagsData = state.flagsData(matching: context, allowingSameSubject: true)
                publish = state.readableFlagsData.flatMap { firstFlags.reserve(keys: $0.allFlagKeys) }
            } else if state.flagsDataVersion == 0 {
                // Apply the same context check whether the initial disk read wins or loses the race.
                state.flagsData = state.flagsData(
                    matching: context,
                    allowingSameSubject: false
                )
                publish = state.readableFlagsData.flatMap { firstFlags.reserve(keys: $0.allFlagKeys) }
            }
            notifyReconciling = stateManager.updateStateWithoutNotifying(.reconciling)
        }
        Self.publishFirstFlags(publish)
        notifyReconciling?()
        guard !invalidContext else {
            // Keep validation completions off the caller's stack, consistent with fetch completions.
            DispatchQueue.global(qos: .utility).async { completion(.failure(.invalidContext)) }
            return
        }
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

        flagAssignmentsFetcher.flagAssignments(
            for: context,
            experimentationOptOut: policy,
            diagnostics: diagnostics,
            assignmentToken: authorization.token
        ) { [weak self] result in
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

            let validated = result.flatMap { response -> Result<FlagAssignmentsResponse, FlagsError> in
                ExperimentationOptOut.accepts(response, for: policy) ? .success(response) : .failure(.invalidResponse)
            }
            let admittedResult: Result<FlagAssignmentsResponse, FlagsError>
            // One clock read decides admission. Required mode: a response that verified but crossed `expires-at` is
            // still trusted when `expireVerifiedFlags` is off, so it is admitted. The install step decides its state.
            // Only required mode reads the clock here: a success claims its completion before any other clock read.
            let required = self.flagAssignmentsFetcher.responseSigningMode == .required
            let admissionNow = required ? self.dateProvider.now : Date.distantPast
            var trustedAtAdmission = false
            if case .success(let response) = validated, required,
                response.responseSigningCacheScope != nil,
                response.responseSigningCacheScope == self.flagAssignmentsFetcher.responseSigningCacheScope,
                self.flagAssignmentsFetcher.isTrusted(response.verification, at: admissionNow) {
                trustedAtAdmission = true
            }
            if case .success(let response) = validated, self.flagAssignmentsFetcher.responseSigningMode != .off,
                !trustedAtAdmission,
                response.responseSigningCacheScope == nil
                    || response.responseSigningCacheScope != self.flagAssignmentsFetcher.responseSigningCacheScope
                    || (self.flagAssignmentsFetcher.responseSigningMode == .required
                        && !self.flagAssignmentsFetcher.isVerified(response.verification, at: admissionNow)) {
                // A proof that expired before admission is a signing failure. A changed request scope is not.
                let expired = self.flagAssignmentsFetcher.responseSigningMode == .required
                    && response.verification != nil
                    && response.responseSigningCacheScope == self.flagAssignmentsFetcher.responseSigningCacheScope
                admittedResult = .failure(
                    expired ? .responseSigningFailed(reason: FlagsSigningError.expiredProof.rawValue) : .invalidResponse
                )
            } else {
                admittedResult = validated
            }
            func fail(_ error: FlagsError, takeCompletion: @escaping () -> InitializationCompletion.Completion?) {
                if case .assignmentAuthorizationFailed = error {
                    // Establish the subject boundary as soon as the rejection is known, even if
                    // fallback selection is waiting for the initial disk read to complete.
                    self._repositoryState.mutate { state in
                        guard contextUpdateID == state.contextUpdateID else {
                            return
                        }
                        state.assignmentSubjectIsolationRequired = true
                        state.hasObservedAssignmentAuthorization = true
                    }
                }
                self.whenCacheReady(PendingCacheReadCallback(takeCompletion: takeCompletion) { [weak self] operationCompletion in
                    guard let self else {
                        complete(.failure(.clientNotInitialized), notifyListeners: nil, completion: operationCompletion)
                        return
                    }

                    let notifyListeners = self.applyFailedContextUpdate(
                        for: context,
                        error: error,
                        contextUpdateID: contextUpdateID,
                        versionAtStart: versionAtStart
                    )
                    complete(.failure(error), notifyListeners: notifyListeners, completion: operationCompletion)
                })
            }

            switch admittedResult {
            case .success(let response):
                // Claim success before processing assignments or publishing ready can race the timeout.
                let operationCompletion = takeCompletion()
                var flagsData = FlagsData(
                    flags: response.flags,
                    context: context,
                    date: self.dateProvider.now,
                    obfuscation: response.obfuscation,
                    flagSelection: self.flagSelection,
                    experimentationOptOutPolicy: policy,
                    observeFullEvaluationData: response.observeFullEvaluationData,
                    keySpellings: response.keySpellings,
                    unparsedFlagKeys: Array(response.failedFlags.keys)
                )
                flagsData.verification = response.verification
                flagsData.responseSigningCacheScope = response.responseSigningCacheScope
                var versionAfterSuccess: UInt64?
                var expiredBeforeAdmission = false
                var expiredAtInstall = false
                var staleAtInstall = false
                var isServingRequestedContext = false
                var callbacks: [PendingCacheReadCallback] = []
                var notifyListeners: (() -> Void)?
                var publish: (() -> Void)?
                self._repositoryState.mutate { state in
                    // Accept an older success for the current context only if no success or reset
                    // superseded its starting version. The latest request's success always applies.
                    let isLatestRequest = contextUpdateID == state.contextUpdateID
                    // Required mode compares wire identity: a proof binds the request bytes.
                    let required = self.flagAssignmentsFetcher.responseSigningMode == .required
                    let isLatestContext = state.latestRequestedContext.map {
                        required ? $0.hasSameWireIdentity(as: context) : $0 == context
                    } ?? false
                    let isFreshForLatestContext = isLatestContext && state.flagsDataVersion == versionAtStart
                    guard isLatestRequest || (!state.hasObservedAssignmentAuthorization && isFreshForLatestContext) else {
                        // A newer success for the same context and policy still satisfies this request.
                        isServingRequestedContext = state.readableFlagsData?.context == context
                        return
                    }
                    // One clock read decides the install. With `expireVerifiedFlags`, a proof that expired after admission
                    // installs nothing and changes no state: the fetch fails with `expired-proof`, as before admission.
                    let installNow = self.dateProvider.now
                    let fetcher = self.flagAssignmentsFetcher
                    if required, flagsData.responseSigningCacheScope == fetcher.responseSigningCacheScope,
                        !fetcher.isTrusted(flagsData.verification, at: installNow) {
                        expiredAtInstall = true
                        return
                    }
                    guard self.canUseSigned(flagsData, matching: context, at: installNow) else {
                        expiredBeforeAdmission = true
                        state.flagsData = nil
                        notifyListeners = self.stateManager.updateStateWithoutNotifying(.error)
                        return
                    }
                    // A trusted proof that is no longer fresh is installed as `stale`, and it stays the verified fallback.
                    let fresh = fetcher.isVerified(flagsData.verification, at: installNow)
                    staleAtInstall = required && !fresh
                    state.flagsData = flagsData
                    if fresh || staleAtInstall {
                        state.verifiedFlagsData = flagsData
                    }
                    state.assignmentSubjectIsolationRequired = false
                    publish = state.readableFlagsData.flatMap { self.firstFlags.reserve(keys: $0.allFlagKeys) }
                    state.cachedFlagsData = flagsData
                    state.flagsDataVersion += 1
                    versionAfterSuccess = state.flagsDataVersion
                    callbacks = state.finishWaitingForInitialFlagsData()
                    notifyListeners = self.stateManager.updateStateWithoutNotifying(staleAtInstall ? .stale : .ready)
                }
                if expiredAtInstall {
                    fail(.responseSigningFailed(reason: FlagsSigningError.expiredProof.rawValue)) { operationCompletion }
                    return
                }
                guard let versionAfterSuccess else {
                    let canComplete = !expiredBeforeAdmission
                        && (self.experimentationOptOutMode == .disabled || isServingRequestedContext)
                    complete(
                        canComplete ? .success(()) : .failure(.invalidResponse),
                        notifyListeners: notifyListeners,
                        completion: operationCompletion
                    )
                    return
                }
                let pendingCompletions = callbacks.map { $0.prepare() }
                Self.publishFirstFlags(publish)
                self.scheduleVerifiedExpiry(for: flagsData)
                self.writeState(flagsData, version: versionAfterSuccess, contextUpdateID: contextUpdateID)
                complete(
                    .success(()),
                    notifyListeners: notifyListeners,
                    completion: operationCompletion,
                    pendingCompletions: pendingCompletions
                )
            case .failure(let error):
                fail(error, takeCompletion: takeCompletion)
            }
        }
    }

    func reset() {
        let flagsDataStore = featureScope.flagsDataStore
        let cacheKey: String?
        switch flagAssignmentsFetcher.responseSigningMode {
        case .off: cacheKey = clientName
        case .required: cacheKey = nil
        case .observe:
            cacheKey = FlagsResponseVerifier.cacheKey(clientName: clientName)
        }
        var callbacks: [PendingCacheReadCallback] = []
        var notifyListeners: (() -> Void)?

        _repositoryState.mutate { state in
            state.flagsData = nil
            state.cachedFlagsData = nil
            state.verifiedFlagsData = nil
            state.flagsDataVersion += 1
            state.contextUpdateID += 1
            state.latestRequestedContext = nil
            state.requestedOptOut = nil
            state.hasInvalidContext = false
            state.assignmentSubjectIsolationRequired = false
            callbacks = state.finishWaitingForInitialFlagsData()
            notifyListeners = stateManager.updateStateWithoutNotifying(.notReady)
            // Order removal with reset so newer successes enqueue their writes after it.
            if let cacheKey {
                cachePersistenceQueue.async {
                    flagsDataStore.removeFlagsData(forClientNamed: cacheKey)
                }
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
