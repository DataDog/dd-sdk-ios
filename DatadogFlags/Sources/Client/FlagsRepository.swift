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
    let evaluationFailure: FlagEvaluationFailure?
    let dependencyEvaluations: [ResolvedDependencyEvaluation]
    let hasInvalidDependencyGraph: Bool
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

        func cachedAssignment(
            for key: String,
            supportsObfuscation: Bool
        ) -> LookupResult {
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

        func cachedEvaluationFailure(for key: String) -> FlagEvaluationFailure? {
            guard data.obfuscation != nil else {
                return plaintextEvaluationFailure(for: key)
            }
            guard let lookupKey = lookupKeys[Data(key.utf8)] else {
                return nil
            }
            return data.flagEvaluationErrors[lookupKey]
        }

        mutating func evaluation(for key: String) -> (FlagAssignment?, FlagEvaluationFailure?) {
            guard let obfuscation = data.obfuscation else {
                return (plaintextAssignment(for: key), plaintextEvaluationFailure(for: key))
            }
            let keyBytes = Data(key.utf8)
            let lookupKey: String
            if let cached = lookupKeys[keyBytes] {
                lookupKey = cached
            } else {
                lookupKey = obfuscation.lookupKey(for: key)
                if lookupKeys.count >= Self.lookupCacheLimit { lookupKeys.removeAll(keepingCapacity: true) }
                lookupKeys[keyBytes] = lookupKey
            }
            return (data.flags[lookupKey], data.flagEvaluationErrors[lookupKey])
        }

        mutating func resolveDependencies(
            _ evaluations: [PrecomputedDependencyEvaluation],
            rootFlagKey: String
        ) -> [ResolvedDependencyEvaluation]? {
            var resolved: [ResolvedDependencyEvaluation] = []
            resolved.reserveCapacity(evaluations.count)
            for evaluation in evaluations {
                let dependencyKey: String
                if let obfuscation = data.obfuscation {
                    guard let decrypted = obfuscation.dependencyFlagKey(evaluation.flagKey, rootFlagKey: rootFlagKey) else {
                        return nil
                    }
                    dependencyKey = decrypted
                } else {
                    dependencyKey = evaluation.flagKey
                }
                switch evaluation {
                case .success(_, let isPresentInAssignment):
                    let (assignment, failure) = self.evaluation(for: dependencyKey)
                    guard let assignment, failure == nil else { return nil }
                    resolved.append(.success(
                        flagKey: dependencyKey,
                        assignment: assignment,
                        isPresentInAssignment: isPresentInAssignment
                    ))
                case .failure(_, let errorCode, let errorMessage):
                    resolved.append(.failure(
                        flagKey: dependencyKey,
                        errorCode: errorCode,
                        errorMessage: errorMessage
                    ))
                }
            }
            return resolved
        }

        /// Plaintext keys match byte for byte, like encoded keys. A `String` dictionary lookup alone would also
        /// return the assignment of a canonically equivalent spelling.
        private func plaintextAssignment(for key: String) -> FlagAssignment? {
            if let index = data.flags.index(forKey: key), data.flags[index].key.utf8.elementsEqual(key.utf8) {
                return data.flags[index].value
            }
            return data.keySpellings.first { $0.key.utf8.elementsEqual(key.utf8) }?.assignment
        }

        private func plaintextEvaluationFailure(for key: String) -> FlagEvaluationFailure? {
            if let index = data.flagEvaluationErrors.index(forKey: key),
               data.flagEvaluationErrors[index].key.utf8.elementsEqual(key.utf8) {
                return data.flagEvaluationErrors[index].value
            }
            return data.errorKeySpellings.first { $0.key.utf8.elementsEqual(key.utf8) }?.failure
        }
    }

    /// Synchronizes assignments, request supersession, and disk-read lifecycle. Client-state transitions
    /// acquire this lock before the state-manager lock; listeners and completions run after unlocking.
    private struct RepositoryState {
        enum CapabilityIdentity {
            case unknown
            case native
            case bridge
        }

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
        // Source identity can arrive after the disk cache. It gates only representations the bridge cannot decode.
        var capabilityIdentity: CapabilityIdentity = .unknown

        var supportsFlagKeyObfuscation: Bool { capabilityIdentity == .native }

        var readableFlagsData: FlagsData? {
            guard let stored = flagsData, let data = capabilityProjection(of: stored) else {
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

        func capabilityProjection(of data: FlagsData) -> FlagsData? {
            guard data.obfuscation == nil || supportsFlagKeyObfuscation else {
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
        experimentationOptOutMode: FlagsClient.ExperimentationOptOutMode = .disabled
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
        featureScope.context { [weak self] context in
            guard let self else {
                return
            }
            var publish: (() -> Void)?
            self._repositoryState.mutate { state in
                state.capabilityIdentity = context.source == "ios" ? .native : .bridge
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

    private func readState() {
        // Retain the read lifecycle, not the repository, so the group is balanced even after deallocation.
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { [_repositoryState, weak firstFlags, flagSelection] data in
            // A cache written under another selection holds a different set of flags.
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
                callbacks = state.applyInitialFlagsData(cachedData)
                publish = state.readableFlagsData.flatMap { firstFlags?.reserve(keys: $0.allFlagKeys) }
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
            if let matchingFlagsData = state.flagsData(
                matching: context,
                allowingSameSubject: state.assignmentSubjectIsolationRequired
            ),
               state.capabilityProjection(of: matchingFlagsData) != nil {
                state.flagsData = matchingFlagsData
                // An eligible fallback re-establishes a usable assignment set.
                state.assignmentSubjectIsolationRequired = false
                publish = state.readableFlagsData.flatMap { firstFlags.reserve(keys: $0.allFlagKeys) }
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
        return repositoryState.readableFlagsData?.context
    }

    func flagAssignment(for key: String) -> FlagAssignment? {
        evaluationSnapshot(for: key).assignment
    }

    func evaluationSnapshot(for key: String) -> FlagEvaluationSnapshot {
        waitForFlagsDataRead()
        let hasError = stateManager.currentState == .error
        let snapshot = repositoryState

        func result(
            from state: RepositoryState,
            assignment: FlagAssignment?,
            evaluationFailure: FlagEvaluationFailure? = nil,
            unparsed: Bool = false
        ) -> FlagEvaluationSnapshot {
            let readable = !hasError && state.readableFlagsData != nil
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
                evaluationFailure: readable ? evaluationFailure : nil,
                dependencyEvaluations: [],
                hasInvalidDependencyGraph: false,
                requestedContext: state.experimentationOptOutMode == .disabled && !authorizationError
                    ? nil : state.latestRequestedContext,
                error: state.hasInvalidContext ? .invalidContext
                    : (authorizationError ? .general : (readable && unparsed ? .parseError : nil))
            )
        }

        guard !hasError else {
            return result(from: snapshot, assignment: nil)
        }
        switch snapshot.activeFlagsData?.cachedAssignment(
            for: key,
            supportsObfuscation: snapshot.supportsFlagKeyObfuscation
        ) {
        case .resolved(let assignment):
            let evaluationFailure = snapshot.activeFlagsData?.cachedEvaluationFailure(for: key)
            let trace = assignment?.dependencyEvaluations ?? evaluationFailure?.dependencyEvaluations ?? []
            if trace.isEmpty {
                return result(from: snapshot, assignment: assignment, evaluationFailure: evaluationFailure)
            }
            break
        case .unparsed: return result(from: snapshot, assignment: nil, unparsed: true)
        case nil: return result(from: snapshot, assignment: nil)
        case .missingHash: break
        }

        var resolved = result(from: snapshot, assignment: nil)
        _repositoryState.mutate { state in
            // A refresh or reset can replace the snapshot after the read. Recheck it under the write lock.
            var assignment: FlagAssignment?
            var evaluationFailure: FlagEvaluationFailure?
            var dependencies: [ResolvedDependencyEvaluation] = []
            var hasInvalidDependencyGraph = false
            var unparsed = false
            if state.flagsData?.obfuscation == nil || state.supportsFlagKeyObfuscation {
                (assignment, evaluationFailure) = state.activeFlagsData?.evaluation(for: key) ?? (nil, nil)
                let trace = assignment?.dependencyEvaluations ?? evaluationFailure?.dependencyEvaluations ?? []
                if !trace.isEmpty {
                    if let resolved = state.activeFlagsData?.resolveDependencies(trace, rootFlagKey: key) {
                        dependencies = resolved
                        if assignment != nil && resolved.contains(where: { dependency in
                            switch dependency {
                            case .failure: return true
                            case .success: return false
                            }
                        }) {
                            hasInvalidDependencyGraph = true
                        }
                    } else {
                        hasInvalidDependencyGraph = true
                    }
                }
                unparsed = assignment == nil
                    && evaluationFailure == nil
                    && state.activeFlagsData?.cachedAssignment(
                        for: key,
                        supportsObfuscation: true
                    ) == .unparsed
            }
            resolved = result(
                from: state,
                assignment: assignment,
                evaluationFailure: evaluationFailure,
                unparsed: unparsed
            )
            resolved = FlagEvaluationSnapshot(
                context: resolved.context,
                assignment: resolved.assignment,
                telemetryOptedOut: resolved.telemetryOptedOut,
                observeFullEvaluationData: resolved.observeFullEvaluationData,
                evaluationFailure: resolved.evaluationFailure,
                dependencyEvaluations: dependencies,
                hasInvalidDependencyGraph: hasInvalidDependencyGraph,
                requestedContext: resolved.requestedContext,
                error: resolved.error
            )
        }
        return resolved
    }

    func flagAssignments() -> [String: FlagAssignment]? {
        assignmentsSnapshot()?.flags
    }

    func assignmentsSnapshot() -> FlagsData? {
        waitForFlagsDataRead()
        guard stateManager.currentState != .error,
              let data = repositoryState.readableFlagsData,
              data.obfuscation == nil else {
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
            switch validated {
            case .success(let response):
                // Claim success before processing assignments or publishing ready can race the timeout.
                let operationCompletion = takeCompletion()
                let flagsData = FlagsData(
                    flags: response.flags,
                    flagEvaluationErrors: response.flagEvaluationErrors,
                    context: context,
                    date: self.dateProvider.now,
                    obfuscation: response.obfuscation,
                    flagSelection: self.flagSelection,
                    experimentationOptOutPolicy: policy,
                    observeFullEvaluationData: response.observeFullEvaluationData,
                    keySpellings: response.keySpellings,
                    errorKeySpellings: response.errorKeySpellings,
                    unparsedFlagKeys: response.unparsedFlagKeys
                )
                var versionAfterSuccess: UInt64?
                var isServingRequestedContext = false
                var callbacks: [PendingCacheReadCallback] = []
                var notifyListeners: (() -> Void)?
                var publish: (() -> Void)?
                self._repositoryState.mutate { state in
                    // Accept an older success for the current context only if no success or reset
                    // superseded its starting version. The latest request's success always applies.
                    let isLatestRequest = contextUpdateID == state.contextUpdateID
                    let isFreshForLatestContext = state.latestRequestedContext == context
                        && state.flagsDataVersion == versionAtStart
                    guard isLatestRequest || (!state.hasObservedAssignmentAuthorization && isFreshForLatestContext) else {
                        // A newer success for the same context and policy still satisfies this request.
                        isServingRequestedContext = state.readableFlagsData?.context == context
                        return
                    }
                    state.flagsData = flagsData
                    state.assignmentSubjectIsolationRequired = false
                    publish = state.readableFlagsData.flatMap { self.firstFlags.reserve(keys: $0.allFlagKeys) }
                    state.cachedFlagsData = flagsData
                    state.flagsDataVersion += 1
                    versionAfterSuccess = state.flagsDataVersion
                    callbacks = state.finishWaitingForInitialFlagsData()
                    notifyListeners = self.stateManager.updateStateWithoutNotifying(.ready)
                }
                guard let versionAfterSuccess else {
                    let result: Result<Void, FlagsError> = self.experimentationOptOutMode == .disabled || isServingRequestedContext
                        ? .success(()) : .failure(.invalidResponse)
                    complete(result, notifyListeners: nil, completion: operationCompletion)
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
            state.requestedOptOut = nil
            state.hasInvalidContext = false
            state.assignmentSubjectIsolationRequired = false
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
