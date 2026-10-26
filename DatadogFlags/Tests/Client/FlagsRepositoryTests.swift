/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@_spi(Internal)
@testable import DatadogFlags

final class FlagsRepositoryTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    // MARK: - Initialization Latency

    func testTelemetryPolicy_whenInitialCacheReadIsDelayed_suppressesUntilPolicyIsKnown() throws {
        for enabled in [false, true] {
            for cachedOptOut: Bool? in [nil, false, true] {
                // Given a cache read that outlasts the synchronous getter's timeout
                let cachedData = cachedOptOut.map { optedOut in
                    FlagsData(
                        flags: ["flag": .mockAnyBoolean()],
                        context: FlagsEvaluationContext(
                            targetingKey: "cached-user",
                            attributes: ["dd_evaluation_telemetry_opt_out": .bool(optedOut)]
                        ),
                        date: .mockAny()
                    )
                }
                let cachedValue = try cachedData.map {
                    DataStoreValueResult.value(try JSONEncoder().encode($0), dataStoreDefaultKeyVersion)
                } ?? .noValue
                let dataStore = DelayedReadDataStore(storage: ["client": cachedValue])
                let repository = FlagsRepository(
                    clientName: "client",
                    flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
                    dateProvider: DateProviderMock(),
                    featureScope: FeatureScopeMock(dataStore: dataStore),
                    readTimeout: 0,
                    initializationTimeout: nil
                )
                defer {
                    dataStore.resumeRead()
                    dataStore.flush()
                    repository.flush()
                }
                let evaluations = EvaluationLoggerMock()
                let exposures = ExposureLoggerMock()
                let rum = RUMFlagEvaluationReporterMock()
                let client = FlagsClient(
                    repository: repository,
                    exposureLogger: exposures,
                    evaluationLogger: evaluations,
                    rumFlagEvaluationReporter: rum,
                    configuration: .init(enableEvaluationTelemetryOptOutParameter: enabled)
                )
                wait(for: [dataStore.readStarted], timeout: 1)

                // When evaluated before any context or cached policy is known
                let initialDetails = client.getDetails(key: "flag", defaultValue: false)

                // Then the default is returned, with telemetry suppressed only when the control is enabled
                XCTAssertEqual(initialDetails.error, .providerNotReady)
                XCTAssertFalse(initialDetails.value)
                let initialEventCount = enabled ? 0 : 1
                XCTAssertEqual(evaluations.logEvaluationCalls.count, initialEventCount)
                XCTAssertTrue(exposures.logExposureCalls.isEmpty)
                XCTAssertTrue(rum.sendFlagEvaluationCalls.isEmpty)

                // When the cache read completes, its policy applies without affecting cached values or exposures
                dataStore.resumeRead()
                dataStore.flush()
                let details = client.getDetails(key: "flag", defaultValue: false)
                let shouldSuppress = enabled && cachedOptOut == true
                XCTAssertEqual(evaluations.logEvaluationCalls.count, initialEventCount + (shouldSuppress ? 0 : 1))
                XCTAssertEqual(exposures.logExposureCalls.count, cachedData == nil ? 0 : 1)
                XCTAssertEqual(rum.sendFlagEvaluationCalls.count, cachedData != nil && !shouldSuppress ? 1 : 0)
                XCTAssertEqual(details.error, cachedData == nil ? .providerNotReady : nil)
                XCTAssertEqual(details.value, cachedData?.flags["flag"]?.variation(as: Bool.self) ?? false)
            }
        }
    }

    func testTelemetryPolicy_whenContextIsRequestedBeforeCacheRead_usesRequestedDecision() throws {
        for optedOut in [false, true] {
            // Given a pending cache read with the opposite reporting decision
            let cachedData = FlagsData(
                flags: ["flag": .mockAnyBoolean()],
                context: FlagsEvaluationContext(
                    targetingKey: "subject",
                    attributes: ["dd_evaluation_telemetry_opt_out": .bool(!optedOut)]
                ),
                date: .mockAny()
            )
            let dataStore = DelayedReadDataStore(storage: [
                "client": .value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
            ])
            let repository = FlagsRepository(
                clientName: "client",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, _ in },
                dateProvider: DateProviderMock(),
                featureScope: FeatureScopeMock(dataStore: dataStore),
                readTimeout: 0,
                initializationTimeout: nil
            )
            defer {
                dataStore.resumeRead()
                dataStore.flush()
                repository.flush()
            }
            wait(for: [dataStore.readStarted], timeout: 1)
            XCTAssertTrue(repository.evaluationSnapshot(for: "flag").telemetryOptedOut)

            // When the application supplies an explicit context before disk or network completes
            repository.setEvaluationContext(FlagsEvaluationContext(
                targetingKey: "subject",
                attributes: ["dd_evaluation_telemetry_opt_out": .bool(optedOut)]
            )) { _ in }

            // Then the requested decision applies immediately and survives the delayed cache read
            XCTAssertEqual(repository.evaluationSnapshot(for: "flag").telemetryOptedOut, optedOut)
            dataStore.resumeRead()
            dataStore.flush()
            XCTAssertEqual(repository.evaluationSnapshot(for: "flag").telemetryOptedOut, optedOut)
        }
    }

    func testTelemetryPolicy_whenFetchSupersedesInitialCacheRead_preservesLatestDecision() throws {
        for optedOut in [false, true] {
            // Given an older cache whose reporting decision differs from the requested context
            let cachedContext = FlagsEvaluationContext(
                targetingKey: "subject",
                attributes: ["dd_evaluation_telemetry_opt_out": .bool(!optedOut)]
            )
            let requestedContext = FlagsEvaluationContext(
                targetingKey: "subject",
                attributes: ["dd_evaluation_telemetry_opt_out": .bool(optedOut)]
            )
            let cachedData = FlagsData(flags: ["cached": .mockAny()], context: cachedContext, date: .mockAny())
            let dataStore = DelayedReadDataStore(storage: [
                "client": .value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
            ])
            var fetchCompletion: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
            let repository = makeRepository(
                dataStore: dataStore,
                fetcher: FlagAssignmentsFetcherMock { _, completion in fetchCompletion = completion },
                initializationTimeout: nil
            )
            defer {
                dataStore.resumeRead()
                dataStore.flush()
                repository.flush()
            }
            wait(for: [dataStore.readStarted], timeout: 1)

            // When the requested assignments arrive before the initial cache read
            repository.setEvaluationContext(requestedContext) { _ in }
            try XCTUnwrap(fetchCompletion)(.success(.init(flags: ["fresh": .mockAny()])))

            // Then assignments and reporting policy are installed together
            let snapshot = repository.evaluationSnapshot(for: "fresh")
            XCTAssertEqual(snapshot.context, requestedContext)
            XCTAssertNotNil(snapshot.assignment)
            XCTAssertEqual(snapshot.telemetryOptedOut, optedOut)

            // When the older cache read completes, neither assignments nor policy can roll back
            dataStore.resumeRead()
            dataStore.flush()
            let restoredSnapshot = repository.evaluationSnapshot(for: "fresh")
            XCTAssertEqual(restoredSnapshot.context, requestedContext)
            XCTAssertEqual(restoredSnapshot.assignment, snapshot.assignment)
            XCTAssertEqual(restoredSnapshot.telemetryOptedOut, optedOut)
            XCTAssertNil(repository.flagAssignment(for: "cached"))
        }
    }

    func testSetEvaluationContext_whenInitialReadIsDelayed_becomesReadyBeforeReadAndPreservesFetchedFlags() throws {
        // Given an initial cache read that remains blocked, with or without cached flags
        let clientName = "client"
        let requestedContext = FlagsEvaluationContext(targetingKey: "fresh-user")
        let cachedData = FlagsData(
            flags: ["cached": .mockAny()],
            context: FlagsEvaluationContext(targetingKey: "cached-user"),
            date: .mockAny()
        )
        let cachedValue = DataStoreValueResult.value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)

        let obfuscation = try JSONDecoder().decode(
            FlagKeyObfuscation.self,
            from: Data(#"{"scheme":"flag-key-sha256-v1","salt":"00000000000000000000000000000000"}"#.utf8)
        )
        let scenarios: [(DataStoreValueResult, FlagKeyObfuscation?)] = [
            (cachedValue, nil), (.noValue, nil), (cachedValue, obfuscation), (.noValue, obfuscation)
        ]
        for (initialValue, obfuscation) in scenarios {
            let dataStore = DelayedReadDataStore(storage: [clientName: initialValue])
            let fetchStarted = expectation(description: "fetch started")
            let response = FlagAssignmentsResponse(
                flags: [obfuscation?.lookupKey(for: "fresh") ?? "fresh": .mockAny()],
                obfuscation: obfuscation
            )
            let repository = FlagsRepository(
                clientName: clientName,
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                    fetchStarted.fulfill()
                    completion(.success(response))
                },
                dateProvider: DateProviderMock(),
                featureScope: FeatureScopeMock(context: .mockWith(source: "ios"), dataStore: dataStore)
            )
            defer {
                dataStore.resumeRead()
                dataStore.flush()
                repository.flush()
            }
            wait(for: [dataStore.readStarted], timeout: 1)

            // When the assignment fetch succeeds
            let completed = expectation(description: "completed before cache read")
            repository.setEvaluationContext(requestedContext) { result in
                if case .failure(let error) = result {
                    XCTFail("Expected success, got \(error)")
                }
                completed.fulfill()
            }

            // Then initialization completes with fresh flags before the cache read
            wait(for: [fetchStarted, completed], timeout: 1)
            XCTAssertEqual(repository.state.currentState, .ready)
            XCTAssertEqual(repository.context, requestedContext)
            XCTAssertNotNil(repository.flagAssignment(for: "fresh"))
            XCTAssertNil(repository.flagAssignment(for: "cached"))

            // When the delayed cache read finishes
            dataStore.resumeRead()
            dataStore.flush()

            // Then it cannot replace the fresh flags
            XCTAssertEqual(repository.state.currentState, .ready)
            XCTAssertEqual(repository.context, requestedContext)
            XCTAssertNotNil(repository.flagAssignment(for: "fresh"))
            XCTAssertNil(repository.flagAssignment(for: "cached"))

            repository.flush()
            let version: DataStoreKeyVersion = obfuscation == nil ? dataStoreDefaultKeyVersion : 2
            let persisted = try XCTUnwrap(dataStore.value(forKey: clientName)?.data(expectedVersion: version))
            let restored = try JSONDecoder().decode(FlagsData.self, from: persisted)
            XCTAssertEqual(restored.context, requestedContext)
            XCTAssertEqual(restored.flags, response.flags)
            XCTAssertEqual(restored.obfuscation, obfuscation)
        }
    }

    func testSetEvaluationContext_whenCacheWriteIsBlocked_doesNotDelayReadyOrCompletion() {
        withBlockedCacheWrite { repository, dataStore in
            XCTAssertEqual(repository.state.currentState, .ready)
            XCTAssertFalse(dataStore.isWriteFinished)
        }
    }

    // MARK: - Cache Read and Fallback

    func testInitialDataStoreRead_duringFirstReconciliation_onlyServesMatchingContextRegardlessOfReadTiming() throws {
        // Given cached flags and a fetch whose completion is controlled by the test
        let cachedContext = FlagsEvaluationContext(targetingKey: "cached-user", attributes: ["tier": .string("gold")])
        let cachedData = FlagsData(flags: ["cached": .mockAny()], context: cachedContext, date: .mockAny())
        let cachedValue = DataStoreValueResult.value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
        let requestedContexts = [
            cachedContext,
            FlagsEvaluationContext(targetingKey: "another-user", attributes: cachedContext.attributes),
            FlagsEvaluationContext(targetingKey: cachedContext.targetingKey, attributes: ["tier": .string("silver")])
        ]
        for readFirst in [true, false] {
            for context in requestedContexts {
                let dataStore = DelayedReadDataStore(storage: ["client": cachedValue])
                var fetchCompletion: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
                let repository = makeRepository(
                    dataStore: dataStore,
                    fetcher: FlagAssignmentsFetcherMock { _, completion in fetchCompletion = completion },
                    initializationTimeout: nil
                )
                defer {
                    dataStore.resumeRead()
                    dataStore.flush()
                    repository.flush()
                }
                wait(for: [dataStore.readStarted], timeout: 1)

                // When the context is set and the cache becomes available, in either order
                if readFirst {
                    dataStore.resumeRead()
                    dataStore.flush()
                }

                var completionCount = 0
                repository.setEvaluationContext(context) { result in
                    if case .failure(let error) = result {
                        XCTFail("Expected success, got \(error)")
                    }
                    completionCount += 1
                }
                if !readFirst {
                    dataStore.resumeRead()
                    dataStore.flush()
                }

                // Then only matching cached flags are served while the fetch remains pending
                XCTAssertEqual(repository.state.currentState, .reconciling)
                XCTAssertEqual(repository.context, context == cachedContext ? cachedContext : nil)
                XCTAssertEqual(repository.flagAssignment(for: "cached") != nil, context == cachedContext)
                XCTAssertEqual(repository.flagAssignment(for: "cached")?.reason, context == cachedContext ? "CACHED" : nil)
                XCTAssertNil(repository.flagAssignment(for: "fresh"))
                XCTAssertEqual(completionCount, 0)

                if context == cachedContext {
                    // When the fetch succeeds
                    try XCTUnwrap(fetchCompletion)(.success(.init(flags: ["fresh": .mockAny()])))

                    // Then fresh flags replace the cache and initialization completes
                    XCTAssertEqual(completionCount, 1)
                    XCTAssertEqual(repository.state.currentState, .ready)
                    XCTAssertEqual(repository.context, context)
                    XCTAssertNil(repository.flagAssignment(for: "cached"))
                    XCTAssertEqual(repository.flagAssignment(for: "fresh"), .mockAny())
                } else {
                    // When we switch back before any successful fetch
                    repository.setEvaluationContext(cachedContext) { _ in }

                    // Then the matching cache is still available
                    XCTAssertNotNil(repository.flagAssignment(for: "cached"))
                }
            }
        }
    }

    func testInitialDataStoreRead_whenFetchFails_waitsForReadAndOnlyUsesMatchingCachedFlags() throws {
        // Given a blocked cache read and a fetch that fails
        let clientName = "client"
        let cachedContext = FlagsEvaluationContext(targetingKey: "cached-user")
        let otherContext = FlagsEvaluationContext(targetingKey: "other-user")
        let cachedData = FlagsData(flags: ["cached": .mockAny()], context: cachedContext, date: .mockAny())
        let cachedValue = DataStoreValueResult.value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)

        for requestedContext in [cachedContext, otherContext] {
            let dataStore = DelayedReadDataStore(storage: [clientName: cachedValue])
            let repository = makeRepository(
                dataStore: dataStore,
                fetcher: FlagAssignmentsFetcherMock { _, completion in
                    completion(.failure(.networkError(URLError(.notConnectedToInternet))))
                }
            )
            defer {
                dataStore.resumeRead()
                dataStore.flush()
            }
            wait(for: [dataStore.readStarted], timeout: 1)
            let completed = expectation(description: "completed after cache read")
            var didComplete = false

            // When the requested context triggers the failed fetch
            repository.setEvaluationContext(requestedContext) { result in
                didComplete = true
                if case .success = result {
                    XCTFail("Expected failure")
                }
                completed.fulfill()
            }

            // Then reconciliation waits for the cache before completing
            XCTAssertEqual(repository.state.currentState, .reconciling)
            XCTAssertFalse(didComplete)

            // When the cache read finishes
            dataStore.resumeRead()
            dataStore.flush()
            wait(for: [completed], timeout: 1)

            // Then only a matching cache provides a stale fallback
            let hasMatchingCache = requestedContext == cachedContext
            XCTAssertEqual(repository.state.currentState, hasMatchingCache ? .stale : .error)
            XCTAssertEqual(repository.context, hasMatchingCache ? requestedContext : nil)
            XCTAssertEqual(repository.flagAssignment(for: "cached") != nil, hasMatchingCache)
            XCTAssertEqual(repository.flagAssignment(for: "cached")?.reason, hasMatchingCache ? "CACHED" : nil)
        }
    }

    func testInitialDataStoreRead_whenCompletesAfterSuccess_preservesFetchedFallback() throws {
        let clientName = "client"
        let context = FlagsEvaluationContext(targetingKey: "user-A", attributes: [:])
        let otherContext = FlagsEvaluationContext(targetingKey: "user-B", attributes: [:])
        let cachedData = FlagsData(flags: ["old": .mockAny()], context: context, date: .mockAny())
        let cachedValue = DataStoreValueResult.value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)

        for initialValue in [cachedValue, .noValue] {
            // Given
            let dataStore = DelayedReadDataStore(storage: [clientName: initialValue])
            var fetchResult: Result<FlagAssignmentsResponse, FlagsError> = .success(.init(flags: ["fresh": .mockAny()]))
            let repository = makeRepository(
                dataStore: dataStore,
                fetcher: FlagAssignmentsFetcherMock { _, completion in completion(fetchResult) }
            )
            defer {
                dataStore.resumeRead()
                dataStore.flush()
                repository.flush()
            }
            wait(for: [dataStore.readStarted], timeout: 1)

            let initialized = expectation(description: "initialized")
            repository.setEvaluationContext(context) { result in
                if case .failure(let error) = result {
                    XCTFail("Expected success, got \(error)")
                }
                initialized.fulfill()
            }
            wait(for: [initialized], timeout: 1)

            // When
            dataStore.resumeRead()
            dataStore.flush()
            fetchResult = .failure(.networkError(URLError(.notConnectedToInternet)))
            let otherContextCompleted = expectation(description: "other context completed")
            repository.setEvaluationContext(otherContext) { _ in otherContextCompleted.fulfill() }
            wait(for: [otherContextCompleted], timeout: 1)
            XCTAssertEqual(repository.state.currentState, .error)
            XCTAssertNil(repository.flagAssignments())

            let originalContextCompleted = expectation(description: "original context completed")
            repository.setEvaluationContext(context) { result in
                if case .success = result {
                    XCTFail("Expected failure")
                }
                originalContextCompleted.fulfill()
            }
            wait(for: [originalContextCompleted], timeout: 1)

            // Then
            XCTAssertEqual(repository.state.currentState, .stale)
            XCTAssertEqual(repository.context, context)
            XCTAssertNotNil(repository.flagAssignment(for: "fresh"))
            XCTAssertNil(repository.flagAssignment(for: "old"))
        }
    }

    func testFailedContextUpdate_whenInitialReadIsDelayed_doesNotWaitAfterSuccess() {
        let context = FlagsEvaluationContext(targetingKey: "user-A", attributes: [:])
        let otherContext = FlagsEvaluationContext(targetingKey: "user-B", attributes: [:])

        for requestedContext in [context, otherContext] {
            // Given
            let dataStore = DelayedReadDataStore()
            var fetchResult: Result<FlagAssignmentsResponse, FlagsError> = .success(.init(flags: ["fresh": .mockAny()]))
            let repository = makeRepository(
                dataStore: dataStore,
                fetcher: FlagAssignmentsFetcherMock { _, completion in completion(fetchResult) }
            )
            defer {
                dataStore.resumeRead()
                dataStore.flush()
                repository.flush()
            }
            wait(for: [dataStore.readStarted], timeout: 1)
            let initialized = expectation(description: "initialized")
            repository.setEvaluationContext(context) { _ in initialized.fulfill() }
            wait(for: [initialized], timeout: 1)

            // When
            fetchResult = .failure(.networkError(URLError(.notConnectedToInternet)))
            let completed = DispatchSemaphore(value: 0)
            repository.setEvaluationContext(requestedContext) { result in
                if case .success = result {
                    XCTFail("Expected failure")
                }
                completed.signal()
            }

            // Then
            let completionBeforeRead = completed.wait(timeout: .now() + 1)
            XCTAssertEqual(completionBeforeRead, .success)
            XCTAssertEqual(repository.state.currentState, requestedContext == context ? .stale : .error)
            XCTAssertEqual(repository.context, requestedContext == context ? context : nil)
            XCTAssertEqual(repository.flagAssignment(for: "fresh") != nil, requestedContext == context)

            dataStore.resumeRead()
            dataStore.flush()
            if completionBeforeRead == .timedOut {
                XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
            }
        }
    }

    func testPendingFailedContextUpdates_whenCacheReadCompletes_doNotBlockEachOtherOrDataStoreQueue() {
        // Given
        let dataStore = DelayedReadDataStore()
        let olderCompletionStarted = expectation(description: "older completion started")
        let olderCompletionFinished = expectation(description: "older completion finished")
        let releaseOlderCompletion = DispatchSemaphore(value: 0)

        let flagsRepository = makeRepository(
            dataStore: dataStore,
            fetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.networkError(URLError(.notConnectedToInternet))))
            }
        )
        defer {
            releaseOlderCompletion.signal()
            dataStore.resumeRead()
            dataStore.flush()
            wait(for: [olderCompletionFinished], timeout: 1)
        }
        wait(for: [dataStore.readStarted], timeout: 1)

        let errorStateObserved = expectation(description: "error state observed")
        var wasErrorStateNotifiedOnDataStoreQueue: Bool?
        let listener = ClosureFlagsStateListener { state in
            guard state == .error else {
                return
            }
            wasErrorStateNotifiedOnDataStoreQueue = dataStore.isOnReadQueue
            errorStateObserved.fulfill()
        }
        flagsRepository.state.addListener(listener)

        let completed = expectation(description: "completed")
        var wasCompletionCalledOnDataStoreQueue: Bool?

        // When
        flagsRepository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "older")) { result in
            if case .success = result {
                XCTFail("Expected the older fetch to fail")
            }
            XCTAssertFalse(dataStore.isOnReadQueue)
            olderCompletionStarted.fulfill()
            releaseOlderCompletion.wait()
            olderCompletionFinished.fulfill()
        }
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            wasCompletionCalledOnDataStoreQueue = dataStore.isOnReadQueue
            completed.fulfill()
        }
        XCTAssertEqual(flagsRepository.state.currentState, .reconciling)

        dataStore.resumeRead()

        // Then
        wait(for: [olderCompletionStarted, errorStateObserved, completed], timeout: 1)
        XCTAssertEqual(flagsRepository.state.currentState, .error)
        XCTAssertEqual(wasErrorStateNotifiedOnDataStoreQueue, false)
        XCTAssertEqual(wasCompletionCalledOnDataStoreQueue, false)
    }

    // MARK: - Cache Lifecycle

    func testFlush_whenCacheWriteIsBlocked_waitsForCacheWrite() {
        withBlockedCacheWrite { repository, dataStore in
            let flushCompleted = DispatchSemaphore(value: 0)

            DispatchQueue.global().async {
                repository.flush()
                flushCompleted.signal()
            }

            XCTAssertEqual(flushCompleted.wait(timeout: .now() + 0.05), .timedOut)
            dataStore.resumeWrite()
            XCTAssertEqual(flushCompleted.wait(timeout: .now() + 1), .success)
            XCTAssertTrue(dataStore.isWriteFinished)
        }
    }

    func testReset_whenCacheWriteIsBlocked_doesNotLeaveStaleFlagsOnDisk() {
        withBlockedCacheWrite { repository, dataStore in
            let cacheRemoveCompleted = expectation(description: "cache remove completed")
            dataStore.onRemoveValue = { cacheRemoveCompleted.fulfill() }
            let resetStarted = expectation(description: "reset started")
            let resetCompleted = expectation(description: "reset completed")

            DispatchQueue.global().async {
                resetStarted.fulfill()
                repository.reset()
                resetCompleted.fulfill()
            }
            wait(for: [resetStarted], timeout: 1)
            XCTAssertFalse(dataStore.isWriteFinished)

            dataStore.resumeWrite()
            wait(for: [resetCompleted, cacheRemoveCompleted], timeout: 1)

            XCTAssertEqual(repository.state.currentState, .notReady)
            XCTAssertNil(repository.context)
            XCTAssertNil(repository.flagAssignment(for: "test"))
            XCTAssertNil(dataStore.value(forKey: "client")?.data())
        }
    }

    func testReset_whenNewerSuccessArrivesAfterStateReset_preservesNewerCache() throws {
        // Given a failed request waiting for the initial cache read
        let dataStore = DelayedReadDataStore()
        let fetcher = FlagAssignmentsFetcherMock { _, completion in completion(.failure(.invalidResponse)) }
        var onTimeoutCancellation: (() -> Void)?
        let repository = FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: fetcher,
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore),
            initializationTimeout: 5,
            scheduleInitializationTimeout: { _, _ in { onTimeoutCancellation?() } }
        )
        defer {
            dataStore.resumeRead()
            dataStore.flush()
            repository.flush()
        }
        wait(for: [dataStore.readStarted], timeout: 1)
        let failedRequestCompleted = expectation(description: "pending failure completed")
        repository.setEvaluationContext(.mockAny()) { result in
            guard case .failure(.invalidResponse) = result else {
                return XCTFail("Expected the original fetch error, got \(result)")
            }
            failedRequestCompleted.fulfill()
        }

        // When reset releases pending failures, a newer request succeeds before reset returns
        let newerContext = FlagsEvaluationContext(targetingKey: "newer-user")
        let freshFlags: [String: FlagAssignment] = ["fresh": .mockAny()]
        fetcher.flagAssignmentsStub = { _, completion in completion(.success(.init(flags: freshFlags))) }
        onTimeoutCancellation = { [weak repository] in
            guard let repository else {
                return XCTFail("Expected repository to remain alive")
            }
            // Cancellation runs after reset releases the repository lock, before draining persistence.
            XCTAssertEqual(repository.state.currentState, .notReady)
            repository.setEvaluationContext(newerContext) { result in
                if case .failure(let error) = result {
                    XCTFail("Expected success, got \(error)")
                }
            }
            repository.flush()
        }
        repository.reset()
        wait(for: [failedRequestCompleted], timeout: 1)

        // Then reset cannot delete the newer success's persisted fallback
        XCTAssertEqual(repository.state.currentState, .ready)
        XCTAssertEqual(repository.context, newerContext)
        XCTAssertEqual(repository.flagAssignments(), freshFlags)
        let persistedData = try XCTUnwrap(dataStore.value(forKey: "client")?.data())
        let persistedFlags = try JSONDecoder().decode(FlagsData.self, from: persistedData)
        XCTAssertEqual(persistedFlags.context, newerContext)
        XCTAssertEqual(persistedFlags.flags, freshFlags)
    }

    func testPendingFailedContextUpdates_whenCacheReadIsSuperseded_completeBeforeListenersWithoutWaitingForDisk() throws {
        // Given failed requests waiting for the initial cache read
        let scenarios = [
            (shouldReset: false, hasCache: false),
            (shouldReset: false, hasCache: true),
            (shouldReset: true, hasCache: true)
        ]
        for (shouldReset, hasCache) in scenarios {
            let context = FlagsEvaluationContext(targetingKey: "user-A")
            let newerContext = FlagsEvaluationContext(targetingKey: "user-B")
            let cachedData = FlagsData(flags: ["cached": .mockAny()], context: context, date: .mockAny())
            let cachedValue = DataStoreValueResult.value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
            let dataStore = DelayedReadDataStore(storage: ["client": hasCache ? cachedValue : .noValue])
            var fetchCompletions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
            var timeoutAction: (() -> Void)?
            @ReadWriteLock
            var timeoutCancellationCount = 0
            @ReadWriteLock
            var callbackCount = 0
            let completed = DispatchSemaphore(value: 0)
            let expectedState: FlagsClientState = shouldReset ? .notReady : .ready
            let repository = FlagsRepository(
                clientName: "client",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                    fetchCompletions.append(completion)
                },
                dateProvider: DateProviderMock(),
                featureScope: FeatureScopeMock(dataStore: dataStore),
                initializationTimeout: 5,
                scheduleInitializationTimeout: { _, action in
                    timeoutAction = action
                    return { _timeoutCancellationCount.mutate { $0 += 1 } }
                }
            )
            defer {
                dataStore.resumeRead()
                dataStore.flush()
                repository.flush()
            }
            wait(for: [dataStore.readStarted], timeout: 1)

            for index in 0..<2 {
                repository.setEvaluationContext(context) { result in
                    switch result {
                    case .failure(.invalidResponse):
                        break
                    default:
                        XCTFail("Expected the original fetch error, got \(result)")
                    }
                    XCTAssertEqual(repository.state.currentState, expectedState)
                    XCTAssertFalse(dataStore.isOnReadQueue)
                    // Reentrant getters verify that callbacks do not run under the repository lock.
                    XCTAssertEqual(repository.context, shouldReset ? nil : newerContext)
                    _callbackCount.mutate { $0 += 1 }
                    completed.signal()
                }
                fetchCompletions[index](.failure(.invalidResponse))
            }
            XCTAssertEqual(callbackCount, 0)

            let stateObserved = expectation(description: "state listener completed")
            let listener = ClosureFlagsStateListener { state in
                guard state == expectedState else {
                    return
                }
                XCTAssertEqual(timeoutCancellationCount, 1)
                timeoutAction?()
                // Pending failures must complete even while this listener is blocked.
                XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
                XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
                stateObserved.fulfill()
            }
            repository.state.addListener(listener)
            defer { repository.state.removeListener(listener) }

            // When a reset or a newer success supersedes the pending cache read
            if shouldReset {
                repository.reset()
            } else {
                repository.setEvaluationContext(newerContext) { result in
                    if case .failure(let error) = result {
                        XCTFail("Expected success, got \(error)")
                    }
                    timeoutAction?()
                }
                fetchCompletions[2](.success(.init(flags: ["fresh": .mockAny()])))
            }

            // Then pending failures complete even while the listener is blocked and disk is unread
            wait(for: [stateObserved], timeout: 1)
            XCTAssertEqual(callbackCount, 2)
            XCTAssertEqual(timeoutCancellationCount, 1)

            // When the late disk read and an already-scheduled timeout finish
            dataStore.resumeRead()
            dataStore.flush()
            try XCTUnwrap(timeoutAction)()

            // Then requests do not complete again and the newer state is preserved
            XCTAssertEqual(completed.wait(timeout: .now() + 0.05), .timedOut)
            XCTAssertEqual(callbackCount, 2)
            XCTAssertEqual(repository.state.currentState, expectedState)
            XCTAssertEqual(repository.context, shouldReset ? nil : newerContext)
            XCTAssertEqual(repository.flagAssignment(for: "fresh") != nil, !shouldReset)
            XCTAssertNil(repository.flagAssignment(for: "cached"))
        }
    }

    func testWaitingGetters_whenInitialDataBecomesAvailable_allResumeBeforeTimeout() throws {
        enum DataSource {
            case fetch, reset, disk
        }

        for source in [DataSource.fetch, .reset, .disk] {
            // Given
            let cachedContext = FlagsEvaluationContext(targetingKey: "cached-user")
            let freshContext = FlagsEvaluationContext(targetingKey: "fresh-user")
            let flags = ["test": FlagAssignment.mockAny()]
            let cachedData = FlagsData(flags: flags, context: cachedContext, date: .mockAny())
            let dataStore = DelayedReadDataStore(storage: [
                "client": .value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
            ])
            let repository = FlagsRepository(
                clientName: "client",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                    completion(.success(.init(flags: flags)))
                },
                dateProvider: DateProviderMock(),
                featureScope: FeatureScopeMock(dataStore: dataStore),
                readTimeout: 5
            )
            let started = DispatchGroup()
            let finished = DispatchGroup()
            defer {
                dataStore.resumeRead()
                dataStore.flush()
                XCTAssertEqual(finished.wait(timeout: .now() + 6), .success)
                repository.flush()
            }
            wait(for: [dataStore.readStarted], timeout: 1)
            let expectedContext = source == .fetch ? freshContext : cachedContext
            let expectedFlags = source == .disk ? flags.mapValues { assignment in
                var cachedAssignment = assignment
                cachedAssignment.reason = "CACHED"
                return cachedAssignment
            } : flags
            let getters: [() -> Void] = [
                { XCTAssertEqual(repository.context, source == .reset ? nil : expectedContext) },
                { XCTAssertEqual(repository.flagAssignment(for: "test"), source == .reset ? nil : expectedFlags["test"]) },
                { XCTAssertEqual(repository.flagAssignments(), source == .reset ? nil : expectedFlags) }
            ]
            for getter in getters {
                started.enter()
                finished.enter()
                DispatchQueue.global().async {
                    started.leave()
                    getter()
                    finished.leave()
                }
            }
            XCTAssertEqual(started.wait(timeout: .now() + 1), .success)
            XCTAssertEqual(finished.wait(timeout: .now() + 0.05), .timedOut)

            // When
            switch source {
            case .fetch:
                repository.setEvaluationContext(freshContext) { result in
                    if case .failure(let error) = result {
                        XCTFail("Expected success, got \(error)")
                    }
                }
            case .reset:
                repository.reset()
            case .disk:
                dataStore.resumeRead()
                dataStore.flush()
            }

            // Then: all three getters finish well before their five-second timeout.
            XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)
            dataStore.resumeRead()
            dataStore.flush()
            XCTAssertEqual(repository.context, source == .reset ? nil : expectedContext)
        }
    }

    func testInitialDataStoreRead_whenPending_doesNotRetainRepository() {
        // Given
        let dataStore = DelayedReadDataStore()
        var repository: FlagsRepository? = makeRepository(dataStore: dataStore)
        weak var weakRepository = repository
        wait(for: [dataStore.readStarted], timeout: 1)

        // When
        repository = nil

        // Then
        XCTAssertNil(weakRepository)
        dataStore.resumeRead()
        dataStore.flush()
    }

    func testPendingFailedContextUpdate_whenRepositoryIsReleased_completesAfterCacheRead() {
        let dataStore = DelayedReadDataStore()
        var repository: FlagsRepository? = makeRepository(
            dataStore: dataStore,
            fetcher: FlagAssignmentsFetcherMock { _, completion in completion(.failure(.invalidResponse)) },
            initializationTimeout: nil
        )
        weak var weakRepository = repository
        wait(for: [dataStore.readStarted], timeout: 1)
        let completed = expectation(description: "released repository completes pending failure")
        repository?.setEvaluationContext(.mockAny()) { result in
            guard case .failure(.clientNotInitialized) = result else {
                return XCTFail("Expected clientNotInitialized, got \(result)")
            }
            completed.fulfill()
        }

        repository = nil
        XCTAssertNil(weakRepository)
        dataStore.resumeRead()
        dataStore.flush()

        wait(for: [completed], timeout: 1)
    }

    func testInitialDataStoreRead_whenCompletesAfterReset_doesNotRestoreCachedFlags() throws {
        // Given
        let clientName = "client"
        let context = FlagsEvaluationContext.mockAny()
        let cachedData = FlagsData(flags: ["old": .mockAny()], context: context, date: .mockAny())
        let dataStore = DelayedReadDataStore(storage: [
            clientName: .value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
        ])
        let repository = makeRepository(
            dataStore: dataStore,
            fetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.networkError(URLError(.notConnectedToInternet))))
            }
        )
        defer {
            dataStore.resumeRead()
            dataStore.flush()
        }
        wait(for: [dataStore.readStarted], timeout: 1)

        // When
        repository.reset()
        dataStore.resumeRead()
        dataStore.flush()

        // Then
        XCTAssertEqual(repository.state.currentState, .notReady)
        XCTAssertNil(repository.flagAssignments())

        let completed = expectation(description: "failed request completed")
        repository.setEvaluationContext(context) { _ in completed.fulfill() }
        wait(for: [completed], timeout: 1)
        XCTAssertEqual(repository.state.currentState, .error)
        XCTAssertNil(repository.flagAssignments())
    }

    // MARK: - Disk Restoration and Context Updates

    func testDiskProjectionPreservesPersistenceAndUsesCachedReasonForCapturedSPITelemetry() throws {
        let context = FlagsEvaluationContext.mockAny()
        let original = FlagAssignment(
            allocationKey: "allocation",
            variationKey: "variant",
            variation: .boolean(true),
            reason: "DEFAULT",
            doLog: true,
            serialID: 42
        )
        let diskData = FlagsData(flags: ["flag": original], context: context, date: .mockAny())
        let diskBytes = try JSONEncoder().encode(diskData)
        featureScope.dataStoreMock.setValue(diskBytes, forKey: "cached")
        var network = original
        network.reason = "TARGETING_MATCH"
        let repository = FlagsRepository(
            clientName: "cached",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(.init(flags: ["flag": network])))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        featureScope.dataStore.flush()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            flushInterval: 100
        )
        let exposures = ExposureLoggerMock()
        let rum = RUMFlagEvaluationReporterMock()
        let client = FlagsClient(
            repository: repository,
            exposureLogger: exposures,
            evaluationLogger: EvaluationLogger(aggregator: aggregator),
            rumFlagEvaluationReporter: rum
        )
        let captured = try XCTUnwrap(client.getFlagAssignments()?["flag"])
        var expected = original
        expected.reason = "CACHED"
        XCTAssertEqual(captured, expected)
        XCTAssertEqual(repository.context, context)
        XCTAssertEqual(featureScope.dataStoreMock.storage["cached"]?.data(), diskBytes)
        XCTAssertEqual(client.snapshot()?.assignments["flag"]?.reason, "CACHED")
        XCTAssertTrue(exposures.logExposureCalls.isEmpty)
        XCTAssertTrue(rum.sendFlagEvaluationCalls.isEmpty)
        aggregator.sendEvaluations()
        XCTAssertTrue(featureScope.eventsWritten.isEmpty)

        let details = client.getDetails(key: "flag", defaultValue: false)
        XCTAssertEqual(details.reason, "CACHED")
        XCTAssertTrue(details.value)
        XCTAssertNil(details.error)
        aggregator.sendEvaluations()
        let first = try XCTUnwrap(featureScope.eventsWritten(ofType: FlagEvaluationEvent.self).first)
        XCTAssertNil(first.runtimeDefaultUsed)
        XCTAssertEqual(first.variant?.key, "variant")
        XCTAssertEqual(first.allocation?.key, "allocation")

        let completed = expectation(description: "network")
        repository.setEvaluationContext(context) { result in
            if case .failure(let error) = result {
                XCTFail("Unexpected network failure: \(error)")
            }
            completed.fulfill()
        }
        waitForExpectations(timeout: 1)
        repository.flush()
        featureScope.dataStore.flush()
        XCTAssertEqual(repository.flagAssignment(for: "flag"), network)
        let persisted = try XCTUnwrap(featureScope.dataStoreMock.storage["cached"]?.data())
        let restored = try JSONDecoder().decode(FlagsData.self, from: persisted)
        XCTAssertEqual(restored.flags["flag"], network)
        client.sendFlagEvaluation(key: "captured", assignment: captured, context: context)
        _ = client.getDetails(key: "flag", defaultValue: false)
        aggregator.sendEvaluations()
        let events = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let capturedEvent = try XCTUnwrap(events.first { $0.flag.key == "captured" })
        XCTAssertNil(capturedEvent.runtimeDefaultUsed)
        XCTAssertEqual(capturedEvent.variant?.key, "variant")
        XCTAssertEqual(capturedEvent.allocation?.key, "allocation")
        let networkEvent = try XCTUnwrap(events.last { $0.flag.key == "flag" })
        XCTAssertNil(networkEvent.runtimeDefaultUsed)
        XCTAssertEqual(networkEvent.variant?.key, "variant")
        XCTAssertEqual(networkEvent.allocation?.key, "allocation")

        let reloaded = FlagsRepository(
            clientName: "cached",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        featureScope.dataStore.flush()
        XCTAssertEqual(reloaded.flagAssignment(for: "flag")?.reason, "CACHED")
        XCTAssertEqual(featureScope.dataStoreMock.storage["cached"]?.data(), persisted)
    }

    func testEmptyAndInvalidDiskRestoration() throws {
        for valid in [true, false] {
            let scope = FeatureScopeMock()
            let data = valid
                ? try JSONEncoder().encode(FlagsData(flags: [:], context: .mockAny(), date: .mockAny()))
                : Data("invalid".utf8)
            scope.dataStoreMock.setValue(data, forKey: "cached")
            let repository = FlagsRepository(
                clientName: "cached",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
                dateProvider: DateProviderMock(),
                featureScope: scope
            )
            scope.dataStore.flush()
            XCTAssertEqual(repository.flagAssignments(), valid ? [:] : nil)
            XCTAssertEqual(repository.state.currentState, .notReady)
        }
    }

    func testInitAndReset() throws {
        // Given
        let initialState = FlagsData(
            flags: ["test": .mockAny()],
            context: .mockAny(),
            date: .mockAny()
        )
        try featureScope.dataStoreMock.setValue(
            JSONEncoder().encode(initialState),
            forKey: .mockAny()
        )

        // When
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        featureScope.dataStore.flush()

        // Then
        XCTAssertEqual(flagsRepository.clientName, .mockAny())
        XCTAssertEqual(flagsRepository.context, .mockAny())
        var cachedAssignment = FlagAssignment.mockAny()
        cachedAssignment.reason = "CACHED"
        XCTAssertEqual(flagsRepository.flagAssignment(for: "test"), cachedAssignment)

        // When
        flagsRepository.reset()
        featureScope.dataStore.flush()

        // Then
        XCTAssertNil(flagsRepository.context)
        XCTAssertNil(flagsRepository.flagAssignment(for: "test"))
        XCTAssertTrue(featureScope.dataStoreMock.storage.isEmpty)
    }

    func testSetEvaluationContext() throws {
        // Given
        let evaluationContext = FlagsEvaluationContext.mockAny()
        let flags = ["test": FlagAssignment.mockAny()]
        let dateProvider = DateProviderMock(now: .mockAny())
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(.init(flags: flags)))
            },
            dateProvider: dateProvider,
            featureScope: featureScope
        )
        let completed = expectation(description: "completed")

        // When
        var capturedResult: Result<Void, FlagsError>?
        flagsRepository.setEvaluationContext(evaluationContext) { result in
            capturedResult = result
            completed.fulfill()
        }

        // Then
        wait(for: [completed], timeout: 0)

        XCTAssertNotNil(capturedResult)
        XCTAssertNoThrow(try capturedResult?.get())

        XCTAssertEqual(flagsRepository.context, .mockAny())
        XCTAssertEqual(flagsRepository.flagAssignment(for: "test"), .mockAny())

        flagsRepository.flush()
        let data = try XCTUnwrap(featureScope.dataStoreMock.storage[.mockAny()]?.data())
        let storedState = try JSONDecoder().decode(FlagsData.self, from: data)

        XCTAssertEqual(
            storedState,
            FlagsData(
                flags: flags,
                context: evaluationContext,
                date: dateProvider.now
            )
        )
    }

    func testSetEvaluationContextError() throws {
        // Given
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.invalidResponse))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let completed = expectation(description: "completed")

        // When
        var capturedResult: Result<Void, FlagsError>?
        flagsRepository.setEvaluationContext(.mockAny()) { result in
            capturedResult = result
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)

        XCTAssertNotNil(capturedResult)
        XCTAssertThrowsError(try capturedResult?.get())
        XCTAssertNil(flagsRepository.context)
        XCTAssertNil(flagsRepository.flagAssignment(for: "test"))
    }

    // MARK: - Initialization Timeout and Completion Ordering

    func testInitializationTimeoutReturnsFailureAndAllowsLateReadyState() throws {
        // Given
        var fetchCompletion: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
        var timeoutAction: (() -> Void)?
        var scheduledTimeout: TimeInterval?
        var callbackResults: [Result<Void, FlagsError>] = []
        var stateAtTimeoutCallback: FlagsClientState?
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                fetchCompletion = completion
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { timeout, action in
                scheduledTimeout = timeout
                timeoutAction = action
                return {}
            }
        )

        flagsRepository.setEvaluationContext(.mockAny()) {
            stateAtTimeoutCallback = flagsRepository.state.currentState
            callbackResults.append($0)
        }

        // When
        try XCTUnwrap(timeoutAction)()

        // Then
        XCTAssertEqual(scheduledTimeout, 2.5)
        XCTAssertEqual(callbackResults.count, 1)
        guard case .failure(.initializationTimedOut) = callbackResults[0] else {
            return XCTFail("Expected initialization timeout")
        }
        XCTAssertEqual(stateAtTimeoutCallback, .error)
        XCTAssertEqual(flagsRepository.state.currentState, .error)

        // When
        try XCTUnwrap(fetchCompletion)(.success(.init(flags: ["test": .mockAny()])))

        // Then
        XCTAssertEqual(callbackResults.count, 1)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "test"))
    }

    func testInitializationTimeout_whenCacheReadIsBlocked_boundsFailedOrPendingFetch() throws {
        // Given initialization waiting on a blocked cache read and a failed or pending fetch
        let context = FlagsEvaluationContext(targetingKey: "cached-user")
        let cachedData = FlagsData(flags: ["cached": .mockAny()], context: context, date: .mockAny())
        let cachedValue = DataStoreValueResult.value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
        for fetchFailsBeforeTimeout in [true, false] {
            for hasCache in [true, false] {
                let dataStore = DelayedReadDataStore(storage: hasCache ? ["client": cachedValue] : [:])
                var fetchCompletion: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
                var timeoutAction: (() -> Void)?
                var scheduledTimeout: TimeInterval?
                var timeoutCancelled = false
                @ReadWriteLock
                var results: [Result<Void, FlagsError>] = []
                let duplicateCompletion = XCTestExpectation(description: "initialization completed twice")
                duplicateCompletion.isInverted = true
                let repository = FlagsRepository(
                    clientName: "client",
                    flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in fetchCompletion = completion },
                    dateProvider: DateProviderMock(),
                    featureScope: FeatureScopeMock(dataStore: dataStore),
                    initializationTimeout: 5,
                    scheduleInitializationTimeout: { timeout, action in
                        scheduledTimeout = timeout
                        timeoutAction = action
                        return { timeoutCancelled = true }
                    }
                )
                defer {
                    dataStore.resumeRead()
                    dataStore.flush()
                    repository.flush()
                }
                wait(for: [dataStore.readStarted], timeout: 1)
                repository.setEvaluationContext(context) { result in
                    _results.mutate { $0.append(result) }
                    if results.count > 1 { duplicateCompletion.fulfill() }
                }
                if fetchFailsBeforeTimeout {
                    try XCTUnwrap(fetchCompletion)(.failure(.invalidResponse))
                }
                XCTAssertEqual(scheduledTimeout, 5)
                XCTAssertFalse(timeoutCancelled, "Waiting for disk must not cancel the initialization deadline")
                XCTAssertTrue(results.isEmpty)
                XCTAssertEqual(repository.state.currentState, .reconciling)

                // When the initialization deadline expires
                try XCTUnwrap(timeoutAction)()

                // Then initialization fails once without waiting for disk or the fetch
                XCTAssertEqual(results.count, 1)
                guard case .failure(.initializationTimedOut)? = results.first else {
                    XCTFail("Expected initializationTimedOut, got \(results)")
                    continue
                }
                XCTAssertEqual(repository.state.currentState, .error)
                let staleObserved = XCTestExpectation(description: "late matching cache becomes stale")
                let listener = ClosureFlagsStateListener { state in
                    if state == .stale { staleObserved.fulfill() }
                }
                repository.state.addListener(listener)
                defer { repository.state.removeListener(listener) }

                // When the cache read finishes and any pending fetch fails
                dataStore.resumeRead()
                dataStore.flush()
                if !fetchFailsBeforeTimeout {
                    try XCTUnwrap(fetchCompletion)(.failure(.invalidResponse))
                }

                // Then matching cache can become stale without completing initialization again
                if hasCache { wait(for: [staleObserved], timeout: 1) }
                wait(for: [duplicateCompletion], timeout: 0.2)
                XCTAssertEqual(results.count, 1)
                XCTAssertEqual(repository.state.currentState, hasCache ? .stale : .error)
                XCTAssertEqual(repository.flagAssignment(for: "cached") != nil, hasCache)
            }
        }
    }

    func testInitializationTimeoutCompletesWhenRepositoryIsReleased() throws {
        // Given
        var timeoutAction: (() -> Void)?
        var callbackResult: Result<Void, FlagsError>?
        var flagsRepository: FlagsRepository? = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, _ in },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, action in
                timeoutAction = action
                return {}
            }
        )
        featureScope.dataStore.flush()
        flagsRepository?.setEvaluationContext(.mockAny()) { callbackResult = $0 }

        // When
        flagsRepository = nil
        try XCTUnwrap(timeoutAction)()

        // Then
        guard case .failure(.clientNotInitialized) = callbackResult else {
            return XCTFail("Expected client-not-initialized failure")
        }
    }

    func testInitializationTimeoutPublishesStaleForMatchingCachedContext() throws {
        // Given
        let context = FlagsEvaluationContext.mockAny()
        let cachedData = FlagsData(
            flags: ["cached": .mockAny()],
            context: context,
            date: .mockAny()
        )
        try featureScope.dataStoreMock.setValue(
            JSONEncoder().encode(cachedData),
            forKey: .mockAny()
        )
        var timeoutAction: (() -> Void)?
        var callbackResult: Result<Void, FlagsError>?
        var stateAtTimeoutCallback: FlagsClientState?
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, _ in },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, action in
                timeoutAction = action
                return {}
            }
        )
        featureScope.dataStore.flush()

        flagsRepository.setEvaluationContext(context) { result in
            stateAtTimeoutCallback = flagsRepository.state.currentState
            callbackResult = result
        }

        // When
        try XCTUnwrap(timeoutAction)()

        // Then
        guard case .failure(.initializationTimedOut) = callbackResult else {
            return XCTFail("Expected initialization timeout")
        }
        XCTAssertEqual(stateAtTimeoutCallback, .stale)
        XCTAssertEqual(flagsRepository.state.currentState, .stale)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "cached"))
    }

    func testInitializationTimeoutDoesNotEvaluateCachedAssignmentsFromAnotherContext() throws {
        // Given
        let cachedContext = FlagsEvaluationContext(targetingKey: "user-A")
        let requestedContext = FlagsEvaluationContext(targetingKey: "user-B")
        let cachedAssignment = FlagAssignment(
            allocationKey: "allocation",
            variationKey: "enabled",
            variation: .boolean(true),
            reason: "TARGETING_MATCH",
            doLog: true
        )
        let cachedData = FlagsData(
            flags: ["promotion": cachedAssignment],
            context: cachedContext,
            date: .mockAny()
        )
        try featureScope.dataStoreMock.setValue(
            JSONEncoder().encode(cachedData),
            forKey: .mockAny()
        )
        var fetchCompletion: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
        var timeoutAction: (() -> Void)?
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                fetchCompletion = completion
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, action in
                timeoutAction = action
                return {}
            }
        )
        let exposureLogger = ExposureLoggerMock()
        let client = FlagsClient(
            repository: flagsRepository,
            exposureLogger: exposureLogger,
            evaluationLogger: EvaluationLoggerMock(),
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )
        featureScope.dataStore.flush()
        XCTAssertEqual(flagsRepository.context, cachedContext)

        // When
        client.setEvaluationContext(requestedContext) { _ in }
        try XCTUnwrap(timeoutAction)()
        let details = client.getBooleanDetails(key: "promotion", defaultValue: false)

        // Then
        XCTAssertFalse(details.value)
        XCTAssertEqual(details.error, .providerNotReady)
        XCTAssertNil(flagsRepository.context)
        XCTAssertNil(flagsRepository.flagAssignment(for: "promotion"))
        XCTAssertNil(flagsRepository.flagAssignments())
        XCTAssertTrue(exposureLogger.logExposureCalls.isEmpty)

        // When a late response finishes the same request
        try XCTUnwrap(fetchCompletion)(.success(.init(flags: ["promotion": .mockRandom()])))

        // Then the requested context becomes readable
        XCTAssertEqual(flagsRepository.context, requestedContext)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "promotion"))
    }

    func testInitializationTimeoutDoesNotReplaceStateFromANewerRequest() throws {
        for expectedState: FlagsClientState in [.reconciling, .ready, .error, .notReady] {
            // Given
            let featureScope = FeatureScopeMock()
            var fetchCompletions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
            var timeoutAction: (() -> Void)?
            var firstResult: Result<Void, FlagsError>?
            let flagsRepository = FlagsRepository(
                clientName: .mockAny(),
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                    fetchCompletions.append(completion)
                },
                dateProvider: DateProviderMock(),
                featureScope: featureScope,
                initializationTimeout: 2.5,
                scheduleInitializationTimeout: { _, action in
                    timeoutAction = action
                    return {}
                }
            )
            featureScope.dataStore.flush()
            defer { flagsRepository.flush() }

            flagsRepository.setEvaluationContext(.mockAny()) { firstResult = $0 }
            flagsRepository.setEvaluationContext(.mockRandom()) { _ in }
            XCTAssertEqual(fetchCompletions.count, 2)

            // When
            switch expectedState {
            case .ready: fetchCompletions[1](.success(.init(flags: ["newer": .mockAny()])))
            case .error: fetchCompletions[1](.failure(.invalidResponse))
            case .notReady: flagsRepository.reset()
            default: break
            }
            XCTAssertEqual(flagsRepository.state.currentState, expectedState)
            try XCTUnwrap(timeoutAction)()

            // Then
            guard case .failure(.initializationTimedOut) = firstResult else {
                return XCTFail("Expected the first request to time out")
            }
            XCTAssertEqual(flagsRepository.state.currentState, expectedState)
        }
    }

    func testInitializationSuccessDeliversCompletionBeforeReadyListeners() throws {
        // Given
        let dateProvider = PausingDateProvider()
        var fetchCompletion: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
        var timeoutAction: (() -> Void)?
        var callbackResult: Result<Void, FlagsError>?
        var callbackWasDeliveredBeforeReadyListener = false
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                fetchCompletion = completion
            },
            dateProvider: dateProvider,
            featureScope: featureScope,
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, action in
                timeoutAction = action
                return {}
            }
        )
        featureScope.dataStore.flush()
        let listener = ClosureFlagsStateListener { state in
            if state == .ready {
                callbackWasDeliveredBeforeReadyListener = callbackResult != nil
                timeoutAction?()
            }
        }
        flagsRepository.state.addListener(listener)
        flagsRepository.setEvaluationContext(.mockAny()) { callbackResult = $0 }

        // When
        let completeFetch = try XCTUnwrap(fetchCompletion)
        let fetchFinished = DispatchGroup()
        fetchFinished.enter()
        defer {
            dateProvider.resume.signal()
            XCTAssertEqual(fetchFinished.wait(timeout: .now() + 2), .success)
            flagsRepository.flush()
        }
        DispatchQueue.global().async {
            completeFetch(.success(.init(flags: [:])))
            fetchFinished.leave()
        }
        XCTAssertEqual(dateProvider.started.wait(timeout: .now() + 2), .success)
        // A received success must claim completion before assignment processing can delay it.
        try XCTUnwrap(timeoutAction)()
        XCTAssertNil(callbackResult)
        dateProvider.resume.signal()
        XCTAssertEqual(fetchFinished.wait(timeout: .now() + 2), .success)

        // Then
        XCTAssertTrue(callbackWasDeliveredBeforeReadyListener)
        XCTAssertNoThrow(try XCTUnwrap(callbackResult).get())
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    func testLaterContextUpdate_deliversTerminalStateListenersBeforeCompletion() {
        for succeeds in [true, false] {
            let featureScope = FeatureScopeMock()
            var completions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
            var events: [String] = []
            let repository = makeRepository(
                dataStore: featureScope.dataStore,
                fetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
                initializationTimeout: nil
            )
            featureScope.dataStore.flush()
            defer { repository.flush() }
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-A")) { _ in }
            completions[0](.success(.init(flags: [:])))
            let expectedState: FlagsClientState = succeeds ? .ready : .error
            let listener = ClosureFlagsStateListener { state in
                if state == expectedState { events.append("listener") }
            }
            repository.state.addListener(listener)
            events.removeAll()

            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-B")) { _ in
                events.append("completion")
            }
            completions[1](succeeds ? .success(.init(flags: [:])) : .failure(.invalidResponse))

            XCTAssertEqual(events, ["listener", "completion"])
            XCTAssertEqual(repository.state.currentState, expectedState)
        }
    }

    func testInitializationFailureClaimsCompletionBeforeStateListeners() throws {
        for hasCache in [false, true] {
            // Given
            let featureScope = FeatureScopeMock()
            let context = FlagsEvaluationContext.mockAny()
            let expectedState: FlagsClientState = hasCache ? .stale : .error
            if hasCache {
                let cachedData = FlagsData(flags: ["cached": .mockAny()], context: context, date: .mockAny())
                try featureScope.dataStoreMock.setValue(JSONEncoder().encode(cachedData), forKey: .mockAny())
            }
            var fetchCompletion: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
            var timeoutAction: (() -> Void)?
            var timeoutCancellationCount = 0
            var callbackResults: [Result<Void, FlagsError>] = []
            var stateAtCompletion: FlagsClientState?
            var callbackWasDeliveredBeforeListener = false
            let flagsRepository = FlagsRepository(
                clientName: .mockAny(),
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                    fetchCompletion = completion
                },
                dateProvider: DateProviderMock(),
                featureScope: featureScope,
                initializationTimeout: 2.5,
                scheduleInitializationTimeout: { _, action in
                    timeoutAction = action
                    return { timeoutCancellationCount += 1 }
                }
            )
            featureScope.dataStore.flush()
            let listener = ClosureFlagsStateListener { state in
                if state == expectedState {
                    callbackWasDeliveredBeforeListener = !callbackResults.isEmpty
                    timeoutAction?()
                }
            }
            flagsRepository.state.addListener(listener)
            flagsRepository.setEvaluationContext(context) {
                stateAtCompletion = flagsRepository.state.currentState
                callbackResults.append($0)
            }

            // When
            try XCTUnwrap(fetchCompletion)(.failure(.networkError(URLError(.notConnectedToInternet))))

            // Then
            XCTAssertTrue(callbackWasDeliveredBeforeListener)
            XCTAssertEqual(callbackResults.count, 1)
            XCTAssertEqual(timeoutCancellationCount, 1)
            XCTAssertEqual(stateAtCompletion, expectedState)
            XCTAssertEqual(flagsRepository.state.currentState, expectedState)
            guard case .failure(.networkError(let error)) = try XCTUnwrap(callbackResults.first) else {
                return XCTFail("Expected the network error, not an initialization timeout")
            }
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testInitializationTimeoutCompletesBeforeErrorListeners() throws {
        // Given
        var timeoutAction: (() -> Void)?
        var callbackResult: Result<Void, FlagsError>?
        var callbackWasDeliveredBeforeErrorListener = false
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, _ in },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, action in
                timeoutAction = action
                return {}
            }
        )
        featureScope.dataStore.flush()
        let listener = ClosureFlagsStateListener { state in
            if state == .error {
                callbackWasDeliveredBeforeErrorListener = callbackResult != nil
            }
        }
        flagsRepository.state.addListener(listener)
        flagsRepository.setEvaluationContext(.mockAny()) { callbackResult = $0 }

        // When
        try XCTUnwrap(timeoutAction)()

        // Then
        XCTAssertTrue(callbackWasDeliveredBeforeErrorListener)
        guard case .failure(.initializationTimedOut) = callbackResult else {
            return XCTFail("Expected initialization timeout")
        }
    }

    func testNonPositiveOrNonFiniteInitializationTimeoutDisablesTimeout() throws {
        let disabledTimeouts: [TimeInterval] = [0, -1, .nan, .infinity, -.infinity]

        for timeout in disabledTimeouts {
            // Given
            let featureScope = FeatureScopeMock()
            var scheduledTimeoutCount = 0
            var callbackResult: Result<Void, FlagsError>?
            let flagsRepository = FlagsRepository(
                clientName: .mockAny(),
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                    completion(.success(.init(flags: [:])))
                },
                dateProvider: DateProviderMock(),
                featureScope: featureScope,
                initializationTimeout: timeout,
                scheduleInitializationTimeout: { _, _ in
                    scheduledTimeoutCount += 1
                    return {}
                }
            )
            featureScope.dataStore.flush()

            // When
            flagsRepository.setEvaluationContext(.mockAny()) { callbackResult = $0 }

            // Then
            XCTAssertEqual(scheduledTimeoutCount, 0, "Unexpected timer for \(timeout)")
            XCTAssertNoThrow(try XCTUnwrap(callbackResult).get())
            XCTAssertEqual(flagsRepository.state.currentState, .ready)
        }
    }

    func testInitializationCompletionCancelsTimeout() throws {
        // Given
        var timeoutAction: (() -> Void)?
        var timeoutCancellationCount = 0
        var callbackCount = 0
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(.init(flags: [:])))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, action in
                timeoutAction = action
                return { timeoutCancellationCount += 1 }
            }
        )

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { _ in callbackCount += 1 }
        try XCTUnwrap(timeoutAction)()

        // Then
        XCTAssertEqual(timeoutCancellationCount, 1)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    func testInitializationTimeoutOnlyAppliesToFirstContext() {
        // Given
        var scheduledTimeoutCount = 0
        var callbackCount = 0
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(.init(flags: [:])))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, _ in
                scheduledTimeoutCount += 1
                return {}
            }
        )

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { _ in callbackCount += 1 }
        flagsRepository.setEvaluationContext(.mockRandom()) { _ in callbackCount += 1 }

        // Then
        XCTAssertEqual(scheduledTimeoutCount, 1)
        XCTAssertEqual(callbackCount, 2)
    }

    func testInitializationTimeoutDefaultsToFiveSeconds() {
        // Given
        var scheduledTimeoutCount = 0
        var scheduledTimeout: TimeInterval?
        var callbackCount = 0
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(.init(flags: [:])))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            scheduleInitializationTimeout: { timeout, _ in
                scheduledTimeoutCount += 1
                scheduledTimeout = timeout
                return {}
            }
        )

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { _ in callbackCount += 1 }

        // Then
        XCTAssertEqual(scheduledTimeoutCount, 1)
        XCTAssertEqual(scheduledTimeout, 5)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    func testInitializationTimeoutDeadlineDoesNotUsePlatformIntWidth() {
        // Given
        let start = DispatchTime(uptimeNanoseconds: 1_000_000_000)

        // When
        let deadline = FlagsRepository.initializationTimeoutDeadline(after: 5, from: start)
        let delay = deadline.uptimeNanoseconds - start.uptimeNanoseconds

        // Then
        XCTAssertEqual(delay, 5_000_000_000)
        XCTAssertGreaterThan(delay, UInt64(Int32.max))
    }

    // MARK: - State Transitions

    func testStateTransitionsToReadyOnSuccess() {
        // Given
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(.init(flags: ["test": .mockAny()])))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        XCTAssertEqual(flagsRepository.state.currentState, .notReady)
        let completed = expectation(description: "completed")

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    func testStateTransitionsToErrorOnFailureWithNoCache() {
        // Given
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.networkError(URLError(.notConnectedToInternet))))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        XCTAssertEqual(flagsRepository.state.currentState, .notReady)
        let completed = expectation(description: "completed")

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.state.currentState, .error)
    }

    func testStateTransitionsToStaleOnFailureWithCache() {
        // Given — first set context successfully to populate cache
        let fetcherMock = FlagAssignmentsFetcherMock { _, completion in
            completion(.success(.init(flags: ["test": .mockAny()])))
        }
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: fetcherMock,
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let firstCompleted = expectation(description: "first completed")
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            firstCompleted.fulfill()
        }
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)

        // Given — now make the fetcher fail
        fetcherMock.flagAssignmentsStub = { _, completion in
            completion(.failure(.networkError(URLError(.notConnectedToInternet))))
        }
        let secondCompleted = expectation(description: "second completed")

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            secondCompleted.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.state.currentState, .stale)
        // Cached flags should still be available
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "test"))
    }

    func testStateTransitionsToReconcilingDuringFetch() {
        // Given
        var capturedCompletion: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                capturedCompletion = completion
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        XCTAssertEqual(flagsRepository.state.currentState, .notReady)

        // When — start the fetch (but don't complete it)
        flagsRepository.setEvaluationContext(.mockAny()) { _ in }

        // Then — state should be reconciling while fetch is in progress
        XCTAssertEqual(flagsRepository.state.currentState, .reconciling)

        // Complete the fetch
        capturedCompletion?(.success(.init(flags: ["test": .mockAny()])))
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    func testResetTransitionsToNotReady() {
        // Given — set context to reach ready state
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(.init(flags: ["test": .mockAny()])))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let completed = expectation(description: "completed")
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            completed.fulfill()
        }
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)

        // When
        flagsRepository.reset()

        // Then
        XCTAssertEqual(flagsRepository.state.currentState, .notReady)
    }

    func testStateTransitionsToStaleOnFailureWithDiskCache() throws {
        // Given — pre-populate the data store with cached flags, using an async
        // data store that delays the callback to simulate production behavior
        // where the disk read may not complete before setEvaluationContext is called.
        let cachedData = FlagsData(
            flags: ["cached": .mockAny()],
            context: .mockAny(),
            date: .mockAny()
        )
        let asyncStore = DataStoreAsyncMock()
        try asyncStore.setValue(
            JSONEncoder().encode(cachedData),
            forKey: .mockAny()
        )
        let asyncFeatureScope = FeatureScopeMock(dataStore: asyncStore)

        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.networkError(URLError(.notConnectedToInternet))))
            },
            dateProvider: DateProviderMock(),
            featureScope: asyncFeatureScope
        )

        // When — call setEvaluationContext while the disk read may still be in-flight.
        // The repository waits for the disk read before deciding stale vs error on failure.
        let completed = expectation(description: "completed")
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            completed.fulfill()
        }

        // Then — should be .stale (not .error) because cached flags exist on disk
        waitForExpectations(timeout: 1)
        XCTAssertEqual(flagsRepository.state.currentState, .stale)
        XCTAssertEqual(flagsRepository.flagAssignment(for: "cached")?.reason, "CACHED")
    }

    func testStateTransitionsToErrorOnFailureWithMismatchedCachedContext() {
        // Given — first set context successfully to populate cache with context A
        let contextA = FlagsEvaluationContext(targetingKey: "user-A", attributes: [:])
        let contextB = FlagsEvaluationContext(targetingKey: "user-B", attributes: [:])

        let fetcherMock = FlagAssignmentsFetcherMock { _, completion in
            completion(.success(.init(flags: ["test": .mockAny()])))
        }
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: fetcherMock,
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let firstCompleted = expectation(description: "first completed")
        flagsRepository.setEvaluationContext(contextA) { _ in
            firstCompleted.fulfill()
        }
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)

        // Given — now make the fetcher fail and request a DIFFERENT context
        fetcherMock.flagAssignmentsStub = { _, completion in
            completion(.failure(.networkError(URLError(.notConnectedToInternet))))
        }
        let secondCompleted = expectation(description: "second completed")

        // When — set context B (different from cached context A)
        flagsRepository.setEvaluationContext(contextB) { _ in
            secondCompleted.fulfill()
        }

        // Then — should be .error (not .stale) because cached context A != requested context B
        // This prevents serving user A's flags to user B
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.state.currentState, .error)
    }

    func testStateRecoveryFromStaleToReady() {
        // Given — first succeed, then fail (stale), then succeed again
        let fetcherMock = FlagAssignmentsFetcherMock { _, completion in
            completion(.success(.init(flags: ["test": .mockAny()])))
        }
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: fetcherMock,
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )

        // Reach ready state
        let first = expectation(description: "first")
        flagsRepository.setEvaluationContext(.mockAny()) { _ in first.fulfill() }
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)

        // Reach stale state
        fetcherMock.flagAssignmentsStub = { _, completion in
            completion(.failure(.networkError(URLError(.timedOut))))
        }
        let second = expectation(description: "second")
        flagsRepository.setEvaluationContext(.mockAny()) { _ in second.fulfill() }
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.state.currentState, .stale)

        // Recover to ready
        fetcherMock.flagAssignmentsStub = { _, completion in
            completion(.success(.init(flags: ["test": .mockAny()])))
        }
        let third = expectation(description: "third")
        flagsRepository.setEvaluationContext(.mockAny()) { _ in third.fulfill() }
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    // MARK: - Overlapping Requests

    func testOverlappingContextUpdates_whenSuccessPublicationIsDelayed_preservesNewerState() {
        for expectedState: FlagsClientState in [.reconciling, .error, .ready, .notReady] {
            // Given A's success paused after applying assignments but before notifying listeners
            let featureScope = FeatureScopeMock()
            let successApplied = DispatchSemaphore(value: 0)
            let resumePublication = DispatchSemaphore(value: 0)
            var completions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
            let repository = FlagsRepository(
                clientName: "client",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                    completions.append(completion)
                },
                dateProvider: DateProviderMock(),
                featureScope: featureScope,
                initializationTimeout: 5,
                scheduleInitializationTimeout: { _, _ in {} }
            )
            featureScope.dataStore.flush()
            @ReadWriteLock
            var states: [FlagsClientState] = []
            let listener = ClosureFlagsStateListener { state in _states.mutate { $0.append(state) } }
            repository.state.addListener(listener)
            let olderFinished = DispatchGroup()
            olderFinished.enter()
            defer {
                resumePublication.signal()
                XCTAssertEqual(olderFinished.wait(timeout: .now() + 2), .success)
                repository.flush()
            }

            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-A")) { result in
                if case .failure(let error) = result {
                    XCTFail("Expected success, got \(error)")
                }
                // Pause after applying A's assignments but before notifying its listeners.
                successApplied.signal()
                resumePublication.wait()
            }
            let olderCompletion = completions[0]
            DispatchQueue.global().async {
                olderCompletion(.success(.init(flags: ["old": .mockAny()])))
                olderFinished.leave()
            }
            XCTAssertEqual(successApplied.wait(timeout: .now() + 2), .success)

            // When a newer context update or reset changes the state
            let newerContext = FlagsEvaluationContext(targetingKey: "user-B")
            repository.setEvaluationContext(newerContext) { _ in }
            switch expectedState {
            case .error: completions[1](.failure(.invalidResponse))
            case .ready: completions[1](.success(.init(flags: ["new": .mockAny()])))
            case .notReady: repository.reset()
            default: break
            }

            // Then the newer state is visible before A resumes
            XCTAssertEqual(repository.state.currentState, expectedState)
            let statesBeforeResuming = states

            // When A resumes listener notification
            resumePublication.signal()
            XCTAssertEqual(olderFinished.wait(timeout: .now() + 2), .success)

            // Then it cannot overwrite the newer state or deliver its superseded notification
            XCTAssertEqual(repository.state.currentState, expectedState)
            XCTAssertEqual(states, statesBeforeResuming, "A must not deliver a superseded ready notification")
            if expectedState == .ready {
                XCTAssertEqual(repository.context, newerContext)
                XCTAssertNotNil(repository.flagAssignment(for: "new"))
            } else if expectedState != .reconciling {
                XCTAssertNil(repository.flagAssignments())
            }
        }
    }

    func testOverlappingContextUpdates_whenResultDeliveryIsReordered_preservesNewerSuccess() throws {
        // Given overlapping requests for A and B with controllable result delivery
        let dateProvider = PausingDateProvider()
        let requested = expectation(description: "both requests started")
        requested.expectedFulfillmentCount = 2
        @ReadWriteLock
        var networkCompletions: [(Result<(Data, HTTPURLResponse), Error>) -> Void] = []
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: featureScope,
            fetch: { _, completion in
                _networkCompletions.mutate { $0.append(completion) }
                requested.fulfill()
            }
        )
        let repository = FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: fetcher,
            dateProvider: dateProvider,
            featureScope: featureScope,
            initializationTimeout: nil
        )
        featureScope.dataStore.flush()
        let contextA = FlagsEvaluationContext(targetingKey: "user-A")
        let contextB = FlagsEvaluationContext(targetingKey: "user-B")
        let finished = DispatchGroup()
        let secondFinished = DispatchSemaphore(value: 0)
        finished.enter()
        finished.enter()
        defer {
            dateProvider.resume.signal()
            _ = finished.wait(timeout: .now() + 2)
            repository.flush()
        }
        repository.setEvaluationContext(contextA) { result in
            if case .failure(let error) = result {
                XCTFail("Expected success, got \(error)")
            }
            finished.leave()
        }
        repository.setEvaluationContext(contextB) { result in
            if case .failure(let error) = result {
                XCTFail("Expected success, got \(error)")
            }
            secondFinished.signal()
            finished.leave()
        }
        wait(for: [requested], timeout: 1)

        let completions = networkCompletions
        XCTAssertEqual(completions.count, 2)
        guard completions.count == 2 else {
            return
        }

        // When A's success processing is paused and B's success arrives
        completions[0](.success((.mockAnyFlagAssignmentsResponse(), .mockAny())))
        XCTAssertEqual(dateProvider.started.wait(timeout: .now() + 1), .success)
        completions[1](.success((.mockAnyFlagAssignmentsResponse(), .mockAny())))

        // Then B completes without waiting for A
        XCTAssertEqual(secondFinished.wait(timeout: .now() + 1), .success)

        // When A resumes
        dateProvider.resume.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)

        // Then B's ready state and persisted context remain authoritative
        XCTAssertEqual(repository.context, contextB)
        XCTAssertEqual(repository.state.currentState, .ready)

        repository.flush()
        featureScope.dataStore.flush()
        let persisted = try XCTUnwrap(featureScope.dataStoreMock.storage["client"]?.data())
        XCTAssertEqual(try JSONDecoder().decode(FlagsData.self, from: persisted).context, contextB)
    }

    func testOverlappingContextUpdates_whenSuccessesArriveInEitherOrder_preservesNewerFlags() {
        for responseOrder in [[0, 1], [1, 0]] {
            let featureScope = FeatureScopeMock()
            var completions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
            let repository = makeRepository(
                dataStore: featureScope.dataStore,
                fetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
                initializationTimeout: nil
            )
            featureScope.dataStore.flush()
            defer { repository.flush() }
            let olderContext = FlagsEvaluationContext(targetingKey: "user-A")
            let newerContext = FlagsEvaluationContext(targetingKey: "user-B")
            var callbackCounts = [0, 0]
            for (index, context) in [olderContext, newerContext].enumerated() {
                repository.setEvaluationContext(context) { result in
                    if case .failure(let error) = result {
                        XCTFail("Expected the original success, got \(error)")
                    }
                    callbackCounts[index] += 1
                }
            }

            for index in responseOrder {
                completions[index](.success(.init(flags: [index == 0 ? "old" : "new": .mockAny()])))

                if index == 0 && responseOrder[0] == 0 {
                    XCTAssertEqual(callbackCounts, [1, 0])
                    XCTAssertEqual(repository.state.currentState, .reconciling)
                    XCTAssertNil(repository.context)
                    XCTAssertNil(repository.flagAssignments())
                    repository.flush()
                    featureScope.dataStore.flush()
                    XCTAssertNil(featureScope.dataStoreMock.storage["client"]?.data())
                }
            }

            XCTAssertEqual(callbackCounts, [1, 1])
            XCTAssertEqual(repository.context, newerContext)
            XCTAssertEqual(repository.state.currentState, .ready)
            XCTAssertNotNil(repository.flagAssignment(for: "new"))
            XCTAssertNil(repository.flagAssignment(for: "old"))
        }
    }

    func testOverlappingContextUpdates_withSameContext_preservesFreshSuccess() {
        for latestSucceeds in [false, true] {
            for responseOrder in [[0, 1], [1, 0]] {
                let featureScope = FeatureScopeMock()
                var completions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
                let repository = makeRepository(
                    dataStore: featureScope.dataStore,
                    fetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
                    initializationTimeout: nil
                )
                featureScope.dataStore.flush()
                defer { repository.flush() }
                let context = FlagsEvaluationContext(targetingKey: "user-A")
                var callbackCounts = [0, 0]
                for index in 0..<2 {
                    repository.setEvaluationContext(context) { result in
                        XCTAssertEqual((try? result.get()) != nil, index == 0 || latestSucceeds)
                        callbackCounts[index] += 1
                    }
                }
                let results: [Result<FlagAssignmentsResponse, FlagsError>] = [
                    .success(.init(flags: ["older": .mockAny()])),
                    latestSucceeds ? .success(.init(flags: ["newer": .mockAny()])) : .failure(.invalidResponse)
                ]

                for index in responseOrder {
                    completions[index](results[index])
                }

                XCTAssertEqual(callbackCounts, [1, 1])
                XCTAssertEqual(repository.state.currentState, .ready)
                XCTAssertEqual(repository.context, context)
                XCTAssertEqual(Set(repository.flagAssignments()?.keys ?? [:].keys), [latestSucceeds ? "newer" : "older"])
            }
        }
    }

    func testOverlappingContextUpdates_withSameContext_afterReset_rejectsEarlierSuccess() {
        var completions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
        let repository = makeRepository(
            dataStore: featureScope.dataStore,
            fetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
            initializationTimeout: nil
        )
        defer { repository.flush() }
        let context = FlagsEvaluationContext(targetingKey: "user-A")
        repository.setEvaluationContext(context) { _ in }
        repository.reset()
        repository.setEvaluationContext(context) { _ in }

        completions[0](.success(.init(flags: ["old": .mockAny()])))

        XCTAssertEqual(repository.state.currentState, .reconciling)
        XCTAssertNil(repository.flagAssignments())
        completions[1](.success(.init(flags: ["new": .mockAny()])))
        XCTAssertEqual(repository.state.currentState, .ready)
        XCTAssertNotNil(repository.flagAssignment(for: "new"))
        XCTAssertNil(repository.flagAssignment(for: "old"))
    }

    func testOverlappingContextUpdates_whenSupersededSuccessArrives_doesNotEndNewerReconciliation() {
        var completions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
        let repository = makeRepository(
            dataStore: featureScope.dataStore,
            fetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
            initializationTimeout: nil
        )
        defer { repository.flush() }
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-A")) { _ in }
        let newerContext = FlagsEvaluationContext(targetingKey: "user-B")
        repository.setEvaluationContext(newerContext) { _ in }
        completions[1](.success(.init(flags: ["new": .mockAny()])))
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-C")) { _ in }

        completions[0](.success(.init(flags: ["old": .mockAny()])))

        XCTAssertEqual(repository.state.currentState, .reconciling)
        XCTAssertEqual(repository.context, newerContext)
        XCTAssertNotNil(repository.flagAssignment(for: "new"))
        XCTAssertNil(repository.flagAssignment(for: "old"))
        completions[2](.success(.init(flags: ["latest": .mockAny()])))
        XCTAssertEqual(repository.state.currentState, .ready)
        XCTAssertNotNil(repository.flagAssignment(for: "latest"))
    }

    func testSetEvaluationContext_whenSuccessArrivesAfterReset_doesNotRestoreFlags() {
        var fetchCompletion: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
        let repository = makeRepository(
            dataStore: featureScope.dataStore,
            fetcher: FlagAssignmentsFetcherMock { _, completion in fetchCompletion = completion },
            initializationTimeout: nil
        )
        var completed = false
        repository.setEvaluationContext(.mockAny()) { _ in completed = true }
        repository.reset()

        fetchCompletion?(.success(.init(flags: ["old": .mockAny()])))
        repository.flush()
        featureScope.dataStore.flush()

        XCTAssertTrue(completed)
        XCTAssertEqual(repository.state.currentState, .notReady)
        XCTAssertNil(repository.context)
        XCTAssertNil(repository.flagAssignments())
        XCTAssertNil(featureScope.dataStoreMock.storage["client"]?.data())
    }

    func testOverlappingContextUpdates_whenBothFail_onlyLatestContextCanUseCache() throws {
        let olderContext = FlagsEvaluationContext(targetingKey: "user-A")
        let newerContext = FlagsEvaluationContext(targetingKey: "user-B")
        let cachedContexts: [FlagsEvaluationContext?] = [olderContext, newerContext, nil]

        for cachedContext in cachedContexts {
            for responseOrder in [[0, 1], [1, 0]] {
                for delayCacheRead in [false, true] {
                    var storage: [String: DataStoreValueResult] = [:]
                    if let cachedContext {
                        let data = FlagsData(flags: ["cached": .mockAny()], context: cachedContext, date: .mockAny())
                        storage["client"] = .value(try JSONEncoder().encode(data), dataStoreDefaultKeyVersion)
                    }
                    let dataStore = DelayedReadDataStore(storage: storage)
                    var completions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
                    let repository = makeRepository(
                        dataStore: dataStore,
                        fetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
                        initializationTimeout: nil
                    )
                    defer {
                        dataStore.resumeRead()
                        dataStore.flush()
                    }
                    wait(for: [dataStore.readStarted], timeout: 1)
                    if !delayCacheRead {
                        dataStore.resumeRead()
                        dataStore.flush()
                    }
                    let completed = expectation(description: "both failures completed")
                    completed.expectedFulfillmentCount = 2
                    @ReadWriteLock
                    var callbackCounts = [0, 0]
                    for (index, context) in [olderContext, newerContext].enumerated() {
                        repository.setEvaluationContext(context) { result in
                            guard case .failure(.invalidResponse) = result else {
                                return XCTFail("Expected the original fetch error, got \(result)")
                            }
                            _callbackCounts.mutate { $0[index] += 1 }
                            completed.fulfill()
                        }
                    }

                    for index in responseOrder {
                        completions[index](.failure(.invalidResponse))
                        if index == 0 && responseOrder[0] == 0 && !delayCacheRead {
                            XCTAssertEqual(callbackCounts, [1, 0])
                            XCTAssertEqual(repository.state.currentState, .reconciling)
                            XCTAssertEqual(repository.context, cachedContext == newerContext ? newerContext : nil)
                            XCTAssertEqual(repository.flagAssignment(for: "cached") != nil, cachedContext == newerContext)
                        }
                    }
                    dataStore.resumeRead()
                    dataStore.flush()
                    wait(for: [completed], timeout: 1)

                    let hasMatchingCache = cachedContext == newerContext
                    XCTAssertEqual(callbackCounts, [1, 1])
                    XCTAssertEqual(repository.state.currentState, hasMatchingCache ? .stale : .error)
                    XCTAssertEqual(repository.context, hasMatchingCache ? newerContext : nil)
                    XCTAssertEqual(repository.flagAssignment(for: "cached") != nil, hasMatchingCache)
                    XCTAssertEqual(repository.flagAssignments() != nil, hasMatchingCache)
                }
            }
        }
    }

    func testOverlappingContextUpdates_whenLatestRequestFails_olderSuccessCannotRestoreWrongContext() {
        for responseOrder in [[0, 1], [1, 0]] {
            let featureScope = FeatureScopeMock()
            var completions: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
            let repository = makeRepository(
                dataStore: featureScope.dataStore,
                fetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
                initializationTimeout: nil
            )
            featureScope.dataStore.flush()
            defer { repository.flush() }
            var callbackCounts = [0, 0]
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-A")) { result in
                if case .failure(let error) = result {
                    XCTFail("Expected the original success, got \(error)")
                }
                callbackCounts[0] += 1
            }
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-B")) { result in
                if case .success = result {
                    XCTFail("Expected the original fetch error")
                }
                callbackCounts[1] += 1
            }

            for index in responseOrder {
                completions[index](index == 0 ? .success(.init(flags: ["old": .mockAny()])) : .failure(.invalidResponse))
            }

            XCTAssertEqual(callbackCounts, [1, 1])
            XCTAssertEqual(repository.state.currentState, .error)
            XCTAssertNil(repository.context)
            XCTAssertNil(repository.flagAssignment(for: "old"))
            XCTAssertNil(repository.flagAssignments())
        }
    }

    func testOverlappingContextUpdates_laterSuccessShouldNotBeClearedByEarlierFailure() {
        // This test reproduces the race condition from Codex feedback #24:
        // 1. Request A starts (captures hadFlags = false)
        // 2. Request B starts and succeeds (writes flags)
        // 3. Request A fails (should NOT clear request B's flags)

        // Given — a fetcher that captures completions so we can control timing
        var capturedCompletions: [(context: FlagsEvaluationContext, completion: (Result<FlagAssignmentsResponse, FlagsError>) -> Void)] = []
        let fetcherMock = FlagAssignmentsFetcherMock { context, completion in
            capturedCompletions.append((context, completion))
        }

        let contextA = FlagsEvaluationContext(targetingKey: "user-A", attributes: [:])
        let contextB = FlagsEvaluationContext(targetingKey: "user-B", attributes: [:])
        let flagsForB: [String: FlagAssignment] = ["feature": .mockAny()]

        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: fetcherMock,
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )

        let completedA = expectation(description: "request A completed")
        let completedB = expectation(description: "request B completed")

        // When — start request A (captures hadFlags = false)
        flagsRepository.setEvaluationContext(contextA) { _ in
            completedA.fulfill()
        }

        // When — start request B (also captures hadFlags = false)
        flagsRepository.setEvaluationContext(contextB) { _ in
            completedB.fulfill()
        }

        // Both requests should be in-flight
        XCTAssertEqual(capturedCompletions.count, 2)

        // When — request B completes successfully first (writes flags)
        capturedCompletions[1].completion(.success(.init(flags: flagsForB)))

        // When — request A fails after B succeeded
        capturedCompletions[0].completion(.failure(.networkError(URLError(.notConnectedToInternet))))

        waitForExpectations(timeout: 1)

        // Then — request B's flags should still be available
        // This is the key assertion: the later successful request's flags should NOT
        // be wiped out by the earlier failing request
        XCTAssertNotNil(
            flagsRepository.flagAssignment(for: "feature"),
            "Request B's flags should not be cleared by request A's failure"
        )
        XCTAssertEqual(flagsRepository.context, contextB, "Context should be from request B")
    }

    // MARK: - State-Before-Completion Ordering

    func testStateIsUpdatedBeforeCompletionOnSuccess() {
        // Given
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(.init(flags: ["test": .mockAny()])))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let completed = expectation(description: "completed")

        // When
        var stateInCompletion: FlagsClientState?
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            stateInCompletion = flagsRepository.state.currentState
            completed.fulfill()
        }

        // Then — state must already be .ready when completion is called
        // (dd-openfeature-provider-swift depends on this ordering)
        waitForExpectations(timeout: 0)
        XCTAssertEqual(stateInCompletion, .ready)
    }

    func testStateIsUpdatedBeforeCompletionOnFailure() {
        // Given
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.networkError(URLError(.notConnectedToInternet))))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let completed = expectation(description: "completed")

        // When
        var stateInCompletion: FlagsClientState?
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            stateInCompletion = flagsRepository.state.currentState
            completed.fulfill()
        }

        // Then — state must already be .error when completion is called (no cached flags)
        // (dd-openfeature-provider-swift depends on this ordering)
        waitForExpectations(timeout: 0)
        XCTAssertEqual(stateInCompletion, .error)
    }

    // MARK: - Flag Selection

    func testCachedFlagsDataWithMatchingFlagSelectionIsLoaded() throws {
        // Given
        let selection = CanonicalFlagSelection(tags: ["mobile"], keyPatterns: ["checkout.*"])
        let cachedData = FlagsData(flags: ["flag": .mockAny()], context: .mockAny(), date: .mockAny(), flagSelection: selection)
        try featureScope.dataStoreMock.setValue(JSONEncoder().encode(cachedData), forKey: "cached")

        // When
        let repository = FlagsRepository(
            clientName: "cached",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            flagSelection: CanonicalFlagSelection(tags: ["mobile"], keyPatterns: ["checkout.*"])
        )
        featureScope.dataStore.flush()

        // Then
        XCTAssertNotNil(repository.flagAssignment(for: "flag"))
        XCTAssertEqual(repository.context, .mockAny())
    }

    func testCachedFlagsDataWithDifferentFlagSelectionIsNotLoaded() throws {
        let mobile = CanonicalFlagSelection(tags: ["mobile"], keyPatterns: [])
        let cases: [(cached: CanonicalFlagSelection?, configured: CanonicalFlagSelection?)] = [
            (mobile, CanonicalFlagSelection(tags: ["web"], keyPatterns: [])),
            (mobile, CanonicalFlagSelection(tags: [], keyPatterns: ["mobile"])),
            (nil, mobile),
            (mobile, nil),
            (CanonicalFlagSelection(tags: ["caf\u{00E9}"], keyPatterns: []), CanonicalFlagSelection(tags: ["cafe\u{0301}"], keyPatterns: [])),
        ]

        for (cached, configured) in cases {
            // Given
            let scope = FeatureScopeMock()
            let cachedData = FlagsData(flags: ["flag": .mockAny()], context: .mockAny(), date: .mockAny(), flagSelection: cached)
            try scope.dataStoreMock.setValue(JSONEncoder().encode(cachedData), forKey: "cached")

            // When
            let repository = FlagsRepository(
                clientName: "cached",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
                dateProvider: DateProviderMock(),
                featureScope: scope,
                flagSelection: configured
            )
            scope.dataStore.flush()

            // Then
            XCTAssertNil(repository.flagAssignment(for: "flag"), "cached: \(String(describing: cached)), configured: \(String(describing: configured))")
            XCTAssertNil(repository.flagAssignments())
            XCTAssertNil(repository.context)
        }
    }

    func testFetchedFlagsDataIsPersistedWithFlagSelection() throws {
        // Given
        let selection = CanonicalFlagSelection(tags: ["mobile"], keyPatterns: [])
        let repository = FlagsRepository(
            clientName: "persisted",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(.init(flags: ["flag": .mockAny()])))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            flagSelection: selection
        )
        featureScope.dataStore.flush()
        let completed = expectation(description: "completed")

        // When
        repository.setEvaluationContext(.mockAny()) { _ in
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1)
        repository.flush()
        featureScope.dataStore.flush()
        let persisted = try XCTUnwrap(featureScope.dataStoreMock.storage["persisted"]?.data())
        XCTAssertEqual(try JSONDecoder().decode(FlagsData.self, from: persisted).flagSelection, selection)
    }

    private func withBlockedCacheWrite(_ assertions: (FlagsRepository, BlockingWriteDataStore) -> Void) {
        let dataStore = BlockingWriteDataStore()
        let cacheWriteStarted = expectation(description: "cache write started")
        dataStore.onSetValueStarted = { cacheWriteStarted.fulfill() }
        let repository = makeRepository(
            dataStore: dataStore,
            fetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(.init(flags: ["test": .mockAny()])))
            }
        )
        defer {
            dataStore.resumeWrite()
            repository.flush()
            XCTAssertTrue(dataStore.isWriteFinished)
        }
        let completed = expectation(description: "ready before cache write completes")
        DispatchQueue.global().async {
            repository.setEvaluationContext(.mockAny()) { result in
                if case .failure(let error) = result {
                    XCTFail("Expected success, got \(error)")
                }
                XCTAssertEqual(repository.state.currentState, .ready)
                completed.fulfill()
            }
        }
        wait(for: [completed, cacheWriteStarted], timeout: 1)

        assertions(repository, dataStore)
    }

    private func makeRepository(
        dataStore: any DataStore,
        fetcher: any FlagAssignmentsFetching = FlagAssignmentsFetcherMock(),
        initializationTimeout: TimeInterval? = Flags.Configuration.defaultInitializationTimeout
    ) -> FlagsRepository {
        FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: fetcher,
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore),
            initializationTimeout: initializationTimeout
        )
    }
}

private final class BlockingWriteDataStore: DataStore, @unchecked Sendable {
    @ReadWriteLock
    private var storage: [String: DataStoreValueResult] = [:]

    @ReadWriteLock
    private var hasFinishedWrite = false

    private let writeSemaphore = DispatchSemaphore(value: 0)

    var onSetValueStarted: (() -> Void)?
    var onRemoveValue: (() -> Void)?

    var isWriteFinished: Bool {
        hasFinishedWrite
    }

    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        onSetValueStarted?()
        writeSemaphore.wait()
        storage[key] = .value(value, version)
        hasFinishedWrite = true
    }

    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        callback(storage[key] ?? .noValue)
    }

    func removeValue(forKey key: String) {
        storage[key] = nil
        onRemoveValue?()
    }

    func clearAllData() {
        storage.removeAll()
    }

    func flush() {}

    func resumeWrite() {
        writeSemaphore.signal()
    }

    func value(forKey key: String) -> DataStoreValueResult? {
        storage[key]
    }
}

private final class DelayedReadDataStore: DataStore, @unchecked Sendable {
    @ReadWriteLock
    private var storage: [String: DataStoreValueResult]

    private let queue = DispatchQueue(label: "com.datadoghq.flags-delayed-read-data-store")
    private let queueKey = DispatchSpecificKey<Void>()
    private let readSemaphore = DispatchSemaphore(value: 0)

    let readStarted = XCTestExpectation(description: "initial cache read started")

    var isOnReadQueue: Bool {
        DispatchQueue.getSpecific(key: queueKey) != nil
    }

    init(storage: [String: DataStoreValueResult] = [:]) {
        self.storage = storage
        queue.setSpecific(key: queueKey, value: ())
    }

    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        storage[key] = .value(value, version)
    }

    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        queue.async {
            let result = self.storage[key] ?? .noValue
            self.readStarted.fulfill()
            self.readSemaphore.wait()
            callback(result)
        }
    }

    func removeValue(forKey key: String) {
        storage[key] = nil
    }

    func clearAllData() {
        storage.removeAll()
    }

    func flush() {
        queue.sync {}
    }

    func resumeRead() {
        readSemaphore.signal()
    }

    func value(forKey key: String) -> DataStoreValueResult? {
        storage[key]
    }
}

private final class PausingDateProvider: DateProvider {
    @ReadWriteLock
    private var calls = 0
    let started = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)

    var now: Date {
        var shouldPause = false
        _calls.mutate { value in
            shouldPause = value == 0
            value += 1
        }
        if shouldPause {
            started.signal()
            resume.wait()
        }
        return Date()
    }
}

private final class ClosureFlagsStateListener: FlagsStateListener {
    private let onStateChange: (FlagsClientState) -> Void

    init(onStateChange: @escaping (FlagsClientState) -> Void) {
        self.onStateChange = onStateChange
    }

    func flagsStateDidChange(_ newState: FlagsClientState) {
        onStateChange(newState)
    }
}
