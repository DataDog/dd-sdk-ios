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

internal final class FlagsRepository {
    private enum Constants {
        static let readTimeout: TimeInterval = 0.1
    }

    let clientName: String
    private let stateManager = FlagsStateManager()

    private let flagAssignmentsFetcher: any FlagAssignmentsFetching
    private let dateProvider: any DateProvider
    private let featureScope: any FeatureScope
    private let cachePersistenceQueue = DispatchQueue(
        label: "com.datadoghq.ios-sdk-flags-cache-persistence",
        autoreleaseFrequency: .workItem,
        target: .global(qos: .utility)
    )

    private static func logRepositoryDiagnostic(_ message: String, startedAt: Date, details: String? = nil) {
        let now = Date()
        let elapsedMs = now.timeIntervalSince(startedAt) * 1_000
        let thread = Thread.isMainThread ? "main" : "background"
        let details = details.map { " \($0)" } ?? ""
        print(
            "Datadog Flags repository \(message)\(details) at \(now.timeIntervalSince1970) elapsedMs=\(elapsedMs) thread=\(thread)"
        )
    }

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
        var pendingDiskReadCallbacks: [() -> Void] = []

        var shouldWaitForFlagsDataRead: Bool {
            !isDiskReadComplete && flagsData == nil
        }

        mutating func applyInitialFlagsData(_ data: FlagsData?) -> [() -> Void] {
            cachedFlagsData = data

            let isInitialReadStillAuthoritative = !hasStartedEvaluationContextRequest
            let isReconcilingSameContextBeforeFirstSuccess = data.map {
                flagsDataVersion == 0 && reconcilingContext == $0.context
            } ?? false

            if isInitialReadStillAuthoritative || isReconcilingSameContextBeforeFirstSuccess {
                flagsData = data
            }

            isDiskReadComplete = true
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

        mutating func executeAfterDiskReadCompletes(_ callback: @escaping () -> Void) -> Bool {
            if isDiskReadComplete {
                return true
            } else {
                pendingDiskReadCallbacks.append(callback)
                return false
            }
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
        let startedAt = Date()
        Self.logRepositoryDiagnostic("initial cache read requested", startedAt: startedAt, details: "clientName=\(clientName)")
        featureScope.flagsDataStore.flagsData(forClientNamed: clientName) { [weak self, readSemaphore] data in
            Self.logRepositoryDiagnostic(
                "initial cache read callback received",
                startedAt: startedAt,
                details: "hasData=\(data != nil)"
            )
            guard let self else {
                // Signal even if self is nil to unblock any waiting getters
                DispatchQueue.global(qos: .userInitiated).async {
                    Self.logRepositoryDiagnostic("initial cache read signaling after repository deinit", startedAt: startedAt)
                    readSemaphore.signal()
                }
                return
            }
            var callbacks: [() -> Void] = []
            Self.logRepositoryDiagnostic("initial cache read applying state start", startedAt: startedAt)
            self._repositoryState.mutate { state in
                callbacks = state.applyInitialFlagsData(data)
            }
            Self.logRepositoryDiagnostic(
                "initial cache read applying state end",
                startedAt: startedAt,
                details: "pendingCallbacks=\(callbacks.count)"
            )

            // Signal semaphore for blocking getters (on elevated queue to avoid priority inversion)
            DispatchQueue.global(qos: .userInitiated).async {
                Self.logRepositoryDiagnostic("initial cache read signaling getters", startedAt: startedAt)
                readSemaphore.signal()
            }

            self.executePendingDiskReadCallbacks(callbacks, diagnosticStartedAt: startedAt)
        }
    }

    private func executePendingDiskReadCallbacks(_ callbacks: [() -> Void], diagnosticStartedAt: Date? = nil) {
        guard !callbacks.isEmpty else {
            return
        }

        if let diagnosticStartedAt {
            Self.logRepositoryDiagnostic(
                "initial cache read dispatching pending callbacks",
                startedAt: diagnosticStartedAt,
                details: "count=\(callbacks.count)"
            )
        }

        // The initial disk-read callback runs on DatadogCore's shared read/write queue.
        // Hop off that queue before notifying state listeners or invoking public completions.
        DispatchQueue.global(qos: .utility).async {
            if let diagnosticStartedAt {
                Self.logRepositoryDiagnostic("initial cache read invoking pending callbacks start", startedAt: diagnosticStartedAt)
            }
            callbacks.forEach { $0() }
            if let diagnosticStartedAt {
                Self.logRepositoryDiagnostic("initial cache read invoking pending callbacks end", startedAt: diagnosticStartedAt)
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

    /// Executes the callback after the initial disk read completes.
    /// Used on fetch failure so cached flags can be used without delaying the network request.
    private func whenFlagsDataRead(_ callback: @escaping () -> Void, diagnosticStartedAt: Date? = nil) {
        var shouldExecuteNow = false
        _repositoryState.mutate { state in
            shouldExecuteNow = state.executeAfterDiskReadCompletes(callback)
        }

        if let diagnosticStartedAt {
            Self.logRepositoryDiagnostic(
                "failure cache-read gate evaluated",
                startedAt: diagnosticStartedAt,
                details: "executeNow=\(shouldExecuteNow)"
            )
        }

        if shouldExecuteNow {
            callback()
        }
    }

    private func writeState(_ flagsData: FlagsData, version: UInt64, diagnosticStartedAt: Date? = nil) {
        let flagsDataStore = featureScope.flagsDataStore
        let clientName = clientName

        if let diagnosticStartedAt {
            Self.logRepositoryDiagnostic(
                "cache persistence enqueue",
                startedAt: diagnosticStartedAt,
                details: "version=\(version)"
            )
        }

        cachePersistenceQueue.async { [weak self] in
            if let diagnosticStartedAt {
                Self.logRepositoryDiagnostic(
                    "cache persistence queue started",
                    startedAt: diagnosticStartedAt,
                    details: "version=\(version)"
                )
            }

            guard let self else {
                if let diagnosticStartedAt {
                    Self.logRepositoryDiagnostic(
                        "cache persistence skipped",
                        startedAt: diagnosticStartedAt,
                        details: "reason=repositoryDeallocated version=\(version)"
                    )
                }
                return
            }

            guard self.repositoryState.flagsDataVersion == version else {
                if let diagnosticStartedAt {
                    Self.logRepositoryDiagnostic(
                        "cache persistence skipped",
                        startedAt: diagnosticStartedAt,
                        details: "reason=staleVersionBeforeEncode currentVersion=\(self.repositoryState.flagsDataVersion) expectedVersion=\(version)"
                    )
                }
                return
            }

            guard let encodedFlagsData = flagsDataStore.encodeFlagsData(
                flagsData,
                diagnosticStartedAt: diagnosticStartedAt
            ) else {
                if let diagnosticStartedAt {
                    Self.logRepositoryDiagnostic(
                        "cache persistence skipped",
                        startedAt: diagnosticStartedAt,
                        details: "reason=encodeFailed version=\(version)"
                    )
                }
                return
            }

            guard self.repositoryState.flagsDataVersion == version else {
                if let diagnosticStartedAt {
                    Self.logRepositoryDiagnostic(
                        "cache persistence skipped",
                        startedAt: diagnosticStartedAt,
                        details: "reason=staleVersionAfterEncode currentVersion=\(self.repositoryState.flagsDataVersion) expectedVersion=\(version)"
                    )
                }
                return
            }

            flagsDataStore.setEncodedFlagsData(
                encodedFlagsData,
                forClientNamed: clientName,
                diagnosticStartedAt: diagnosticStartedAt
            )
        }
    }

    private func handleFailedContextUpdate(
        error: FlagsError,
        context: FlagsEvaluationContext,
        versionAtStart: UInt64,
        completion: @escaping (Result<Void, FlagsError>) -> Void,
        diagnosticStartedAt: Date? = nil
    ) {
        if let diagnosticStartedAt {
            Self.logRepositoryDiagnostic(
                "failure handling start",
                startedAt: diagnosticStartedAt,
                details: "versionAtStart=\(versionAtStart)"
            )
        }

        // Only update state if no newer request has succeeded.
        // This prevents an older failing request from clearing data
        // written by a newer successful request.
        var stateToUpdate: FlagsClientState?
        if let diagnosticStartedAt {
            Self.logRepositoryDiagnostic("failure handling state mutate start", startedAt: diagnosticStartedAt)
        }
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
        if let diagnosticStartedAt {
            Self.logRepositoryDiagnostic(
                "failure handling state mutate end",
                startedAt: diagnosticStartedAt,
                details: "stateToUpdate=\(String(describing: stateToUpdate))"
            )
        }

        guard let stateToUpdate else {
            if let diagnosticStartedAt {
                Self.logRepositoryDiagnostic("failure completion start without state update", startedAt: diagnosticStartedAt)
            }
            completion(.failure(error))
            if let diagnosticStartedAt {
                Self.logRepositoryDiagnostic("failure completion returned without state update", startedAt: diagnosticStartedAt)
            }
            return
        }

        // State must be updated before calling completion —
        // dd-openfeature-provider-swift checks currentState in the callback.
        if let diagnosticStartedAt {
            Self.logRepositoryDiagnostic(
                "failure state update start",
                startedAt: diagnosticStartedAt,
                details: "state=\(stateToUpdate)"
            )
        }
        stateManager.updateState(stateToUpdate)
        if let diagnosticStartedAt {
            Self.logRepositoryDiagnostic(
                "failure state update end",
                startedAt: diagnosticStartedAt,
                details: "state=\(stateToUpdate)"
            )
            Self.logRepositoryDiagnostic("failure completion start", startedAt: diagnosticStartedAt)
        }
        completion(.failure(error))
        if let diagnosticStartedAt {
            Self.logRepositoryDiagnostic("failure completion returned", startedAt: diagnosticStartedAt)
        }
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
        let startedAt = Date()
        Self.logRepositoryDiagnostic("setEvaluationContext start", startedAt: startedAt)
        var versionAtStart: UInt64 = 0
        Self.logRepositoryDiagnostic("reconciling state mutate start", startedAt: startedAt)
        _repositoryState.mutate { state in
            state.hasStartedEvaluationContextRequest = true
            state.reconcilingContext = context
            versionAtStart = state.flagsDataVersion
        }
        Self.logRepositoryDiagnostic(
            "reconciling state mutate end",
            startedAt: startedAt,
            details: "versionAtStart=\(versionAtStart)"
        )
        Self.logRepositoryDiagnostic("state update reconciling start", startedAt: startedAt)
        stateManager.updateState(.reconciling)
        Self.logRepositoryDiagnostic("state update reconciling end", startedAt: startedAt)

        Self.logRepositoryDiagnostic("assignment fetch start", startedAt: startedAt)
        flagAssignmentsFetcher.flagAssignments(for: context) { [weak self] result in
            guard let self else {
                Self.logRepositoryDiagnostic("assignment fetch callback failed", startedAt: startedAt, details: "reason=repositoryDeallocated")
                completion(.failure(.clientNotInitialized))
                return
            }

            switch result {
            case .success(let flags):
                Self.logRepositoryDiagnostic(
                    "assignment fetch callback received",
                    startedAt: startedAt,
                    details: "result=success flagsCount=\(flags.count)"
                )
                Self.logRepositoryDiagnostic("flags data create start", startedAt: startedAt)
                let flagsData = FlagsData(
                    flags: flags,
                    context: context,
                    date: self.dateProvider.now
                )
                Self.logRepositoryDiagnostic("flags data create end", startedAt: startedAt)
                var versionAfterSuccess: UInt64 = 0
                Self.logRepositoryDiagnostic("success state mutate start", startedAt: startedAt)
                self._repositoryState.mutate { state in
                    state.flagsData = flagsData
                    state.cachedFlagsData = flagsData
                    state.flagsDataVersion += 1
                    versionAfterSuccess = state.flagsDataVersion
                    state.reconcilingContext = nil
                }
                Self.logRepositoryDiagnostic(
                    "success state mutate end",
                    startedAt: startedAt,
                    details: "versionAfterSuccess=\(versionAfterSuccess)"
                )
                self.writeState(flagsData, version: versionAfterSuccess, diagnosticStartedAt: startedAt)
                Self.logRepositoryDiagnostic("state update ready start", startedAt: startedAt)
                self.stateManager.updateState(.ready)
                Self.logRepositoryDiagnostic("state update ready end", startedAt: startedAt)
                Self.logRepositoryDiagnostic("completion success start", startedAt: startedAt)
                completion(.success(()))
                Self.logRepositoryDiagnostic("completion success returned", startedAt: startedAt)
            case .failure(let error):
                Self.logRepositoryDiagnostic(
                    "assignment fetch callback received",
                    startedAt: startedAt,
                    details: "result=failure error=\(error)"
                )
                self.whenFlagsDataRead({ [weak self] in
                    Self.logRepositoryDiagnostic("failure cache-read gate callback start", startedAt: startedAt)
                    guard let self else {
                        Self.logRepositoryDiagnostic(
                            "failure cache-read gate callback failed",
                            startedAt: startedAt,
                            details: "reason=repositoryDeallocated"
                        )
                        completion(.failure(.clientNotInitialized))
                        return
                    }

                    self.handleFailedContextUpdate(
                        error: error,
                        context: context,
                        versionAtStart: versionAtStart,
                        completion: completion,
                        diagnosticStartedAt: startedAt
                    )
                    Self.logRepositoryDiagnostic("failure cache-read gate callback end", startedAt: startedAt)
                }, diagnosticStartedAt: startedAt)
            }
        }
    }

    func reset() {
        let flagsDataStore = featureScope.flagsDataStore
        let clientName = clientName

        _repositoryState.mutate { state in
            state.flagsData = nil
            state.cachedFlagsData = nil
            state.flagsDataVersion += 1
            state.reconcilingContext = nil
        }
        // Enqueue removal after any already-started cache write to avoid
        // re-persisting stale flags after reset.
        cachePersistenceQueue.sync {
            flagsDataStore.removeFlagsData(forClientNamed: clientName)
        }
        stateManager.updateState(.notReady)
    }

    func flush() {
        cachePersistenceQueue.sync {}
    }
}
