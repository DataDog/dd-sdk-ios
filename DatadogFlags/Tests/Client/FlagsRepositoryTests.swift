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

    func testOverlappingContextUpdates_whenResultDeliveryIsReordered_preservesNewerSuccess() throws {
        let dateProvider = PausingDateProvider()
        let requested = expectation(description: "both requests started")
        requested.expectedFulfillmentCount = 2
        @ReadWriteLock
        var networkCompletions: [(Result<Data, Error>) -> Void] = []
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
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
        completions[0](.success(.mockAnyFlagAssignmentsResponse()))
        XCTAssertEqual(dateProvider.started.wait(timeout: .now() + 1), .success)
        completions[1](.success(.mockAnyFlagAssignmentsResponse()))
        // B can finish while A is paused, but A must not overwrite it when resumed.
        XCTAssertEqual(secondFinished.wait(timeout: .now() + 1), .success)
        dateProvider.resume.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(repository.context, contextB)
        XCTAssertEqual(repository.state.currentState, .ready)

        repository.flush()
        featureScope.dataStore.flush()
        let persisted = try XCTUnwrap(featureScope.dataStoreMock.storage["client"]?.data())
        XCTAssertEqual(try JSONDecoder().decode(FlagsData.self, from: persisted).context, contextB)
    }

    func testOverlappingContextUpdates_whenSuccessesArriveInEitherOrder_preservesNewerFlags() {
        for responseOrder in [[0, 1], [1, 0]] {
            var completions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
            let repository = FlagsRepository(
                clientName: "client",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
                dateProvider: DateProviderMock(),
                featureScope: featureScope,
                initializationTimeout: nil
            )
            featureScope.dataStore.flush()
            defer { repository.flush() }
            let olderContext = FlagsEvaluationContext(targetingKey: "user-A")
            let newerContext = FlagsEvaluationContext(targetingKey: "user-B")
            var completed = 0
            repository.setEvaluationContext(olderContext) { _ in completed += 1 }
            repository.setEvaluationContext(newerContext) { _ in completed += 1 }

            for index in responseOrder {
                completions[index](.success([index == 0 ? "old" : "new": .mockAny()]))
            }

            XCTAssertEqual(completed, 2)
            XCTAssertEqual(repository.context, newerContext)
            XCTAssertEqual(repository.state.currentState, .ready)
            XCTAssertNotNil(repository.flagAssignment(for: "new"))
            XCTAssertNil(repository.flagAssignment(for: "old"))
        }
    }

    func testOverlappingContextUpdates_whenSupersededSuccessArrives_doesNotEndNewerReconciliation() {
        var completions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        let repository = FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: nil
        )
        defer { repository.flush() }
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-A")) { _ in }
        let newerContext = FlagsEvaluationContext(targetingKey: "user-B")
        repository.setEvaluationContext(newerContext) { _ in }
        completions[1](.success(["new": .mockAny()]))
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-C")) { _ in }

        completions[0](.success(["old": .mockAny()]))

        XCTAssertEqual(repository.state.currentState, .reconciling)
        XCTAssertEqual(repository.context, newerContext)
        XCTAssertNotNil(repository.flagAssignment(for: "new"))
        XCTAssertNil(repository.flagAssignment(for: "old"))
        completions[2](.success(["latest": .mockAny()]))
        XCTAssertEqual(repository.state.currentState, .ready)
        XCTAssertNotNil(repository.flagAssignment(for: "latest"))
    }

    func testSetEvaluationContext_whenSuccessArrivesAfterReset_doesNotRestoreFlags() {
        var fetchCompletion: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
        let repository = FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in fetchCompletion = completion },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: nil
        )
        var completed = false
        repository.setEvaluationContext(.mockAny()) { _ in completed = true }
        repository.reset()

        fetchCompletion?(.success(["old": .mockAny()]))
        repository.flush()
        featureScope.dataStore.flush()

        XCTAssertTrue(completed)
        XCTAssertEqual(repository.state.currentState, .notReady)
        XCTAssertNil(repository.context)
        XCTAssertNil(repository.flagAssignments())
        XCTAssertNil(featureScope.dataStoreMock.storage["client"]?.data())
    }

    func testPendingFailure_whenNewerRequestSucceeds_claimsResultBeforeReadyListener() throws {
        let dataStore = DelayedReadDataStore()
        let readStarted = expectation(description: "initial read started")
        dataStore.onReadStarted = { readStarted.fulfill() }
        var fetchCompletions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        var timeoutAction: (() -> Void)?
        var timeoutCancellationCount = 0
        @ReadWriteLock
        var results: [Result<Void, FlagsError>] = []
        let firstCompleted = DispatchGroup()
        firstCompleted.enter()
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
                return { timeoutCancellationCount += 1 }
            }
        )
        defer {
            dataStore.resumeRead()
            dataStore.flush()
            repository.flush()
        }
        wait(for: [readStarted], timeout: 1)
        let listener = ClosureFlagsStateListener { state in
            if state == .ready {
                XCTAssertEqual(timeoutCancellationCount, 1)
                timeoutAction?()
                XCTAssertEqual(firstCompleted.wait(timeout: .now() + 1), .success)
            }
        }
        repository.state.addListener(listener)
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-A")) { result in
            XCTAssertEqual(repository.state.currentState, .ready)
            _results.mutate { $0.append(result) }
            firstCompleted.leave()
        }
        fetchCompletions[0](.failure(.invalidResponse))
        XCTAssertTrue(results.isEmpty)
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-B")) { _ in
            timeoutAction?()
        }
        fetchCompletions[1](.success(["fresh": .mockAny()]))

        XCTAssertEqual(firstCompleted.wait(timeout: .now() + 1), .success)
        guard case .failure(.invalidResponse) = try XCTUnwrap(results.first) else {
            return XCTFail("Expected the original fetch failure")
        }
        dataStore.resumeRead()
        dataStore.flush()
        try XCTUnwrap(timeoutAction)()
        XCTAssertEqual(results.count, 1)
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
        XCTAssertEqual(flagsRepository.flagAssignment(for: "test"), .mockAny())

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
        let dataStore = WriteObservingDataStore()
        let cacheWriteCompleted = expectation(description: "cache write completed")
        dataStore.onSetValue = {
            cacheWriteCompleted.fulfill()
        }
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(flags))
            },
            dateProvider: dateProvider,
            featureScope: FeatureScopeMock(dataStore: dataStore)
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

        wait(for: [cacheWriteCompleted], timeout: 1)

        let data = try XCTUnwrap(dataStore.value(forKey: .mockAny())?.data())
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

    func testSetEvaluationContext_whenCacheWriteIsBlocked_doesNotDelayReadyOrCompletion() {
        // Given
        let dataStore = BlockingWriteDataStore()
        let cacheWriteStarted = expectation(description: "cache write started")
        dataStore.onSetValueStarted = {
            cacheWriteStarted.fulfill()
        }
        defer {
            dataStore.resumeWrite()
        }

        let flagsRepository = FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["test": .mockAny()]))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore)
        )

        let completed = expectation(description: "completed")
        var stateInCompletion: FlagsClientState?

        // When
        DispatchQueue.global().async {
            flagsRepository.setEvaluationContext(.mockAny()) { _ in
                stateInCompletion = flagsRepository.state.currentState
                completed.fulfill()
            }
        }

        // Then
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(stateInCompletion, .ready)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
        XCTAssertFalse(dataStore.isWriteFinished)

        wait(for: [cacheWriteStarted], timeout: 1)
        dataStore.resumeWrite()
        XCTAssertTrue(dataStore.waitForWriteFinished(timeout: 1))
    }

    func testFlush_whenCacheWriteIsBlocked_waitsForCacheWrite() {
        // Given
        let dataStore = BlockingWriteDataStore()
        let cacheWriteStarted = expectation(description: "cache write started")
        dataStore.onSetValueStarted = {
            cacheWriteStarted.fulfill()
        }
        defer {
            dataStore.resumeWrite()
        }

        let flagsRepository = FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["test": .mockAny()]))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore)
        )

        let setContextCompleted = expectation(description: "set context completed")
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            setContextCompleted.fulfill()
        }
        wait(for: [setContextCompleted], timeout: 1)

        let flushSemaphore = DispatchSemaphore(value: 0)

        // When
        DispatchQueue.global().async {
            flagsRepository.flush()
            flushSemaphore.signal()
        }
        wait(for: [cacheWriteStarted], timeout: 1)

        // Then
        XCTAssertEqual(flushSemaphore.wait(timeout: .now() + 0.05), .timedOut)

        dataStore.resumeWrite()
        XCTAssertEqual(flushSemaphore.wait(timeout: .now() + 1), .success)
        XCTAssertTrue(dataStore.isWriteFinished)
    }

    func testReset_whenCacheWriteIsBlocked_doesNotLeaveStaleFlagsOnDisk() {
        // Given
        let clientName = "client"
        let dataStore = BlockingWriteDataStore()
        let cacheWriteStarted = expectation(description: "cache write started")
        let cacheRemoveCompleted = expectation(description: "cache remove completed")
        dataStore.onSetValueStarted = {
            cacheWriteStarted.fulfill()
        }
        dataStore.onRemoveValue = {
            cacheRemoveCompleted.fulfill()
        }
        defer {
            dataStore.resumeWrite()
        }

        let flagsRepository = FlagsRepository(
            clientName: clientName,
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["test": .mockAny()]))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore)
        )

        let completed = expectation(description: "completed")

        DispatchQueue.global().async {
            flagsRepository.setEvaluationContext(.mockAny()) { _ in
                completed.fulfill()
            }
        }
        wait(for: [completed, cacheWriteStarted], timeout: 1)

        let resetStarted = expectation(description: "reset started")
        let resetCompleted = expectation(description: "reset completed")

        // When
        DispatchQueue.global().async {
            resetStarted.fulfill()
            flagsRepository.reset()
            resetCompleted.fulfill()
        }
        wait(for: [resetStarted], timeout: 1)

        // Then
        XCTAssertFalse(dataStore.isWriteFinished)

        dataStore.resumeWrite()
        XCTAssertTrue(dataStore.waitForWriteFinished(timeout: 1))
        wait(for: [resetCompleted, cacheRemoveCompleted], timeout: 1)

        XCTAssertEqual(flagsRepository.state.currentState, .notReady)
        XCTAssertNil(flagsRepository.context)
        XCTAssertNil(flagsRepository.flagAssignment(for: "test"))
        XCTAssertNil(dataStore.value(forKey: clientName)?.data())
    }

    func testSetEvaluationContext_whenInitialDataStoreReadIsDelayed_startsFetchingAssignmentsWithoutWaitingForRead() {
        // Given
        let dataStore = DelayedReadDataStore()
        let readStarted = expectation(description: "initial data store read started")
        dataStore.onReadStarted = {
            readStarted.fulfill()
        }

        let fetchStarted = expectation(description: "fetch started")
        let flagsRepository = FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                fetchStarted.fulfill()
                completion(.success(["test": .mockAny()]))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore)
        )
        defer {
            dataStore.resumeRead()
            dataStore.flush()
        }
        wait(for: [readStarted], timeout: 1)

        let completed = expectation(description: "completed")

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { result in
            if case .failure(let error) = result {
                XCTFail("Expected success, got \(error)")
            }
            completed.fulfill()
        }

        // Then
        wait(for: [fetchStarted, completed], timeout: 1)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    func testInitialDataStoreRead_whenCompletesAfterSuccessfulContextUpdate_doesNotOverwriteFetchedFlags() throws {
        // Given
        let clientName = "client"
        let cachedContext = FlagsEvaluationContext(targetingKey: "cached-user", attributes: [:])
        let requestedContext = FlagsEvaluationContext(targetingKey: "fresh-user", attributes: [:])
        let cachedData = FlagsData(
            flags: ["cached": .mockAny()],
            context: cachedContext,
            date: .mockAny()
        )
        let dataStore = DelayedReadDataStore(
            storage: [
                clientName: .value(
                    try JSONEncoder().encode(cachedData),
                    dataStoreDefaultKeyVersion
                )
            ]
        )
        let readStarted = expectation(description: "initial data store read started")
        dataStore.onReadStarted = {
            readStarted.fulfill()
        }

        let flagsRepository = FlagsRepository(
            clientName: clientName,
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["fresh": .mockAny()]))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore)
        )
        defer {
            dataStore.resumeRead()
            dataStore.flush()
        }
        wait(for: [readStarted], timeout: 1)

        let completed = expectation(description: "completed")

        // When
        flagsRepository.setEvaluationContext(requestedContext) { result in
            if case .failure(let error) = result {
                XCTFail("Expected success, got \(error)")
            }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)

        dataStore.resumeRead()
        dataStore.flush()

        // Then
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
        XCTAssertEqual(flagsRepository.context, requestedContext)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "fresh"))
        XCTAssertNil(flagsRepository.flagAssignment(for: "cached"))
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
            let readStarted = expectation(description: "initial read started")
            dataStore.onReadStarted = { readStarted.fulfill() }
            var fetchResult: Result<[String: FlagAssignment], FlagsError> = .success(["fresh": .mockAny()])
            let repository = FlagsRepository(
                clientName: clientName,
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in completion(fetchResult) },
                dateProvider: DateProviderMock(),
                featureScope: FeatureScopeMock(dataStore: dataStore)
            )
            defer {
                dataStore.resumeRead()
                dataStore.flush()
                repository.flush()
            }
            wait(for: [readStarted], timeout: 1)

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
            let readStarted = expectation(description: "initial read started")
            dataStore.onReadStarted = { readStarted.fulfill() }
            var fetchResult: Result<[String: FlagAssignment], FlagsError> = .success(["fresh": .mockAny()])
            let repository = FlagsRepository(
                clientName: "client",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in completion(fetchResult) },
                dateProvider: DateProviderMock(),
                featureScope: FeatureScopeMock(dataStore: dataStore)
            )
            defer {
                dataStore.resumeRead()
                dataStore.flush()
                repository.flush()
            }
            wait(for: [readStarted], timeout: 1)
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

    func testPendingFailedContextUpdates_whenCacheReadIsSuperseded_completeWithoutWaitingForDisk() throws {
        for shouldReset in [false, true] {
            // Given
            let context = FlagsEvaluationContext(targetingKey: "user-A")
            let newerContext = FlagsEvaluationContext(targetingKey: "user-B")
            let cachedData = FlagsData(flags: ["cached": .mockAny()], context: context, date: .mockAny())
            let dataStore = DelayedReadDataStore(storage: [
                "client": .value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
            ])
            let readStarted = expectation(description: "initial read started")
            dataStore.onReadStarted = { readStarted.fulfill() }
            var fetchCompletions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
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
            wait(for: [readStarted], timeout: 1)

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

            // When
            if shouldReset {
                repository.reset()
            } else {
                repository.setEvaluationContext(newerContext) { result in
                    if case .failure(let error) = result {
                        XCTFail("Expected success, got \(error)")
                    }
                }
                fetchCompletions[2](.success(["fresh": .mockAny()]))
            }

            // Then
            XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
            XCTAssertEqual(completed.wait(timeout: .now() + 1), .success)
            XCTAssertEqual(callbackCount, 2)
            XCTAssertEqual(timeoutCancellationCount, 1)

            // A late disk read and an already-scheduled timeout must not complete requests again.
            dataStore.resumeRead()
            dataStore.flush()
            try XCTUnwrap(timeoutAction)()
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
            let readStarted = expectation(description: "initial read started")
            dataStore.onReadStarted = { readStarted.fulfill() }
            let repository = FlagsRepository(
                clientName: "client",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                    completion(.success(flags))
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
            wait(for: [readStarted], timeout: 1)
            let expectedContext = source == .fetch ? freshContext : cachedContext
            let getters: [() -> Void] = [
                { XCTAssertEqual(repository.context, source == .reset ? nil : expectedContext) },
                { XCTAssertEqual(repository.flagAssignment(for: "test"), source == .reset ? nil : flags["test"]) },
                { XCTAssertEqual(repository.flagAssignments(), source == .reset ? nil : flags) }
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
        let readStarted = expectation(description: "initial read started")
        dataStore.onReadStarted = { readStarted.fulfill() }
        var repository: FlagsRepository? = FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore)
        )
        weak var weakRepository = repository
        wait(for: [readStarted], timeout: 1)

        // When
        repository = nil

        // Then
        XCTAssertNil(weakRepository)
        dataStore.resumeRead()
        dataStore.flush()
    }

    func testInitialDataStoreRead_whenCompletesAfterReset_doesNotRestoreCachedFlags() throws {
        // Given
        let clientName = "client"
        let context = FlagsEvaluationContext.mockAny()
        let cachedData = FlagsData(flags: ["old": .mockAny()], context: context, date: .mockAny())
        let dataStore = DelayedReadDataStore(storage: [
            clientName: .value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
        ])
        let readStarted = expectation(description: "initial read started")
        dataStore.onReadStarted = { readStarted.fulfill() }
        let repository = FlagsRepository(
            clientName: clientName,
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.networkError(URLError(.notConnectedToInternet))))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore)
        )
        defer {
            dataStore.resumeRead()
            dataStore.flush()
        }
        wait(for: [readStarted], timeout: 1)

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

    func testInitialDataStoreRead_whenCompletesDuringReconcilingWithMatchingContext_servesCachedFlags() throws {
        // Given
        let clientName = "client"
        let requestedContext = FlagsEvaluationContext(targetingKey: "cached-user", attributes: [:])
        let cachedData = FlagsData(
            flags: ["cached": .mockAny()],
            context: requestedContext,
            date: .mockAny()
        )
        let dataStore = DelayedReadDataStore(
            storage: [
                clientName: .value(
                    try JSONEncoder().encode(cachedData),
                    dataStoreDefaultKeyVersion
                )
            ]
        )
        let readStarted = expectation(description: "initial data store read started")
        dataStore.onReadStarted = {
            readStarted.fulfill()
        }

        let fetchStarted = expectation(description: "fetch started")
        var fetchCompletion: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
        let flagsRepository = FlagsRepository(
            clientName: clientName,
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                fetchCompletion = completion
                fetchStarted.fulfill()
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore)
        )
        defer {
            dataStore.resumeRead()
            dataStore.flush()
        }
        wait(for: [readStarted], timeout: 1)

        let completed = expectation(description: "completed")

        // When
        flagsRepository.setEvaluationContext(requestedContext) { result in
            if case .failure(let error) = result {
                XCTFail("Expected success, got \(error)")
            }
            completed.fulfill()
        }
        wait(for: [fetchStarted], timeout: 1)

        dataStore.resumeRead()
        dataStore.flush()

        // Then
        XCTAssertEqual(flagsRepository.state.currentState, .reconciling)
        XCTAssertEqual(flagsRepository.context, requestedContext)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "cached"))
        XCTAssertNil(flagsRepository.flagAssignment(for: "fresh"))

        fetchCompletion?(.success(["fresh": .mockAny()]))
        wait(for: [completed], timeout: 1)

        XCTAssertEqual(flagsRepository.state.currentState, .ready)
        XCTAssertEqual(flagsRepository.context, requestedContext)
        XCTAssertNil(flagsRepository.flagAssignment(for: "cached"))
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "fresh"))
    }

    func testInitialDataStoreRead_whenCompletesAfterFailedContextUpdate_doesNotRestoreMismatchedCachedFlags() throws {
        // Given
        let clientName = "client"
        let cachedContext = FlagsEvaluationContext(targetingKey: "cached-user", attributes: [:])
        let requestedContext = FlagsEvaluationContext(targetingKey: "fresh-user", attributes: [:])
        let cachedData = FlagsData(
            flags: ["cached": .mockAny()],
            context: cachedContext,
            date: .mockAny()
        )
        let dataStore = DelayedReadDataStore(
            storage: [
                clientName: .value(
                    try JSONEncoder().encode(cachedData),
                    dataStoreDefaultKeyVersion
                )
            ]
        )
        let readStarted = expectation(description: "initial data store read started")
        dataStore.onReadStarted = {
            readStarted.fulfill()
        }

        let flagsRepository = FlagsRepository(
            clientName: clientName,
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.networkError(URLError(.notConnectedToInternet))))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore)
        )
        defer {
            dataStore.resumeRead()
            dataStore.flush()
        }
        wait(for: [readStarted], timeout: 1)

        let completed = expectation(description: "completed")
        var didComplete = false

        // When
        flagsRepository.setEvaluationContext(requestedContext) { result in
            didComplete = true
            if case .success = result {
                XCTFail("Expected failure")
            }
            completed.fulfill()
        }

        XCTAssertEqual(flagsRepository.state.currentState, .reconciling)
        XCTAssertFalse(didComplete)

        dataStore.resumeRead()
        dataStore.flush()
        wait(for: [completed], timeout: 1)

        // Then
        XCTAssertEqual(flagsRepository.state.currentState, .error)
        XCTAssertNil(flagsRepository.context)
        XCTAssertNil(flagsRepository.flagAssignment(for: "cached"))
    }

    func testInitialDataStoreRead_whenFetchFailsBeforeReadCompletes_dispatchesFailureCallbacksOffDataStoreQueue() {
        // Given
        let dataStore = DelayedReadDataStore()
        let readStarted = expectation(description: "initial data store read started")
        dataStore.onReadStarted = {
            readStarted.fulfill()
        }

        let flagsRepository = FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.networkError(URLError(.notConnectedToInternet))))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore)
        )
        defer {
            dataStore.resumeRead()
            dataStore.flush()
        }
        wait(for: [readStarted], timeout: 1)

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
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            wasCompletionCalledOnDataStoreQueue = dataStore.isOnReadQueue
            completed.fulfill()
        }
        XCTAssertEqual(flagsRepository.state.currentState, .reconciling)

        dataStore.resumeRead()

        // Then
        wait(for: [errorStateObserved, completed], timeout: 1)
        XCTAssertEqual(wasErrorStateNotifiedOnDataStoreQueue, false)
        XCTAssertEqual(wasCompletionCalledOnDataStoreQueue, false)
    }

    func testInitialDataStoreRead_whenCompletesAfterFailedContextUpdate_usesMatchingCachedFlags() throws {
        // Given
        let clientName = "client"
        let requestedContext = FlagsEvaluationContext(targetingKey: "cached-user", attributes: [:])
        let cachedData = FlagsData(
            flags: ["cached": .mockAny()],
            context: requestedContext,
            date: .mockAny()
        )
        let dataStore = DelayedReadDataStore(
            storage: [
                clientName: .value(
                    try JSONEncoder().encode(cachedData),
                    dataStoreDefaultKeyVersion
                )
            ]
        )
        let readStarted = expectation(description: "initial data store read started")
        dataStore.onReadStarted = {
            readStarted.fulfill()
        }

        let flagsRepository = FlagsRepository(
            clientName: clientName,
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.failure(.networkError(URLError(.notConnectedToInternet))))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore)
        )
        defer {
            dataStore.resumeRead()
            dataStore.flush()
        }
        wait(for: [readStarted], timeout: 1)

        let completed = expectation(description: "completed")
        var didComplete = false

        // When
        flagsRepository.setEvaluationContext(requestedContext) { result in
            didComplete = true
            if case .success = result {
                XCTFail("Expected failure")
            }
            completed.fulfill()
        }

        XCTAssertEqual(flagsRepository.state.currentState, .reconciling)
        XCTAssertFalse(didComplete)

        dataStore.resumeRead()
        dataStore.flush()
        wait(for: [completed], timeout: 1)

        // Then
        XCTAssertEqual(flagsRepository.state.currentState, .stale)
        XCTAssertEqual(flagsRepository.context, requestedContext)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "cached"))
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

    func testInitializationTimeoutReturnsFailureAndAllowsLateReadyState() throws {
        // Given
        var fetchCompletion: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
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
        try XCTUnwrap(fetchCompletion)(.success(["test": .mockAny()]))

        // Then
        XCTAssertEqual(callbackResults.count, 1)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "test"))
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
        var fetchCompletion: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
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
        try XCTUnwrap(fetchCompletion)(.success(["promotion": .mockRandom()]))

        // Then the requested context becomes readable
        XCTAssertEqual(flagsRepository.context, requestedContext)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "promotion"))
    }

    func testInitializationTimeoutDoesNotReplaceReadyStateFromANewerRequest() throws {
        // Given
        var fetchCompletions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
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

        flagsRepository.setEvaluationContext(.mockAny()) { firstResult = $0 }
        flagsRepository.setEvaluationContext(.mockRandom()) { _ in }
        XCTAssertEqual(fetchCompletions.count, 2)

        // When
        fetchCompletions[1](.success(["newer": .mockAny()]))
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
        try XCTUnwrap(timeoutAction)()

        // Then
        guard case .failure(.initializationTimedOut) = firstResult else {
            return XCTFail("Expected the first request to time out")
        }
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    func testInitializationSuccessClaimsCompletionBeforeReadyListeners() throws {
        // Given
        var fetchCompletion: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
        var timeoutAction: (() -> Void)?
        var callbackResult: Result<Void, FlagsError>?
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
        featureScope.dataStore.flush()
        let listener = ClosureFlagsStateListener { state in
            if state == .ready {
                timeoutAction?()
            }
        }
        flagsRepository.state.addListener(listener)
        flagsRepository.setEvaluationContext(.mockAny()) { callbackResult = $0 }

        // When
        try XCTUnwrap(fetchCompletion)(.success([:]))

        // Then
        XCTAssertNoThrow(try XCTUnwrap(callbackResult).get())
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
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
            var fetchCompletion: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
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
                    completion(.success([:]))
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
                completion(.success([:]))
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
                completion(.success([:]))
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
                completion(.success([:]))
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
                completion(.success(["test": .mockAny()]))
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
            completion(.success(["test": .mockAny()]))
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
        var capturedCompletion: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
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
        capturedCompletion?(.success(["test": .mockAny()]))
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    func testResetTransitionsToNotReady() {
        // Given — set context to reach ready state
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["test": .mockAny()]))
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
    }

    func testStateTransitionsToErrorOnFailureWithMismatchedCachedContext() {
        // Given — first set context successfully to populate cache with context A
        let contextA = FlagsEvaluationContext(targetingKey: "user-A", attributes: [:])
        let contextB = FlagsEvaluationContext(targetingKey: "user-B", attributes: [:])

        let fetcherMock = FlagAssignmentsFetcherMock { _, completion in
            completion(.success(["test": .mockAny()]))
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
            completion(.success(["test": .mockAny()]))
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
            completion(.success(["test": .mockAny()]))
        }
        let third = expectation(description: "third")
        flagsRepository.setEvaluationContext(.mockAny()) { _ in third.fulfill() }
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    // MARK: - Overlapping Requests

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
                    let readStarted = expectation(description: "cache read started")
                    dataStore.onReadStarted = { readStarted.fulfill() }
                    var completions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
                    let repository = FlagsRepository(
                        clientName: "client",
                        flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
                        dateProvider: DateProviderMock(),
                        featureScope: FeatureScopeMock(dataStore: dataStore),
                        initializationTimeout: nil
                    )
                    defer {
                        dataStore.resumeRead()
                        dataStore.flush()
                    }
                    wait(for: [readStarted], timeout: 1)
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

    func testOverlappingContextUpdates_whenOlderRequestFails_preservesNewerReconciliation() throws {
        let featureScope = FeatureScopeMock()
        let newerContext = FlagsEvaluationContext(targetingKey: "user-B")
        let cachedData = FlagsData(flags: ["cached": .mockAny()], context: newerContext, date: .mockAny())
        try featureScope.dataStoreMock.setValue(JSONEncoder().encode(cachedData), forKey: "client")
        var completions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        let repository = FlagsRepository(
            clientName: "client",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: nil
        )
        featureScope.dataStore.flush()
        var callbackCount = 0
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "user-A")) { _ in callbackCount += 1 }
        repository.setEvaluationContext(newerContext) { _ in callbackCount += 1 }

        completions[0](.failure(.invalidResponse))

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(repository.state.currentState, .reconciling)
        XCTAssertEqual(repository.context, newerContext)
        XCTAssertNotNil(repository.flagAssignment(for: "cached"))

        completions[1](.failure(.invalidResponse))
        XCTAssertEqual(callbackCount, 2)
        XCTAssertEqual(repository.state.currentState, .stale)
        XCTAssertEqual(repository.context, newerContext)
    }

    func testOverlappingContextUpdates_whenLatestRequestFails_olderSuccessCannotRestoreWrongContext() {
        for responseOrder in [[0, 1], [1, 0]] {
            let featureScope = FeatureScopeMock()
            var completions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
            let repository = FlagsRepository(
                clientName: "client",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in completions.append(completion) },
                dateProvider: DateProviderMock(),
                featureScope: featureScope,
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
                completions[index](index == 0 ? .success(["old": .mockAny()]) : .failure(.invalidResponse))
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
        var capturedCompletions: [(context: FlagsEvaluationContext, completion: (Result<[String: FlagAssignment], FlagsError>) -> Void)] = []
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
        capturedCompletions[1].completion(.success(flagsForB))

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
                completion(.success(["test": .mockAny()]))
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
}

private final class WriteObservingDataStore: DataStore, @unchecked Sendable {
    @ReadWriteLock
    private var storage: [String: DataStoreValueResult]

    var onSetValue: (() -> Void)?

    init(storage: [String: DataStoreValueResult] = [:]) {
        self.storage = storage
    }

    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        storage[key] = .value(value, version)
        onSetValue?()
    }

    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        callback(storage[key] ?? .noValue)
    }

    func value(forKey key: String) -> DataStoreValueResult? {
        storage[key]
    }

    func removeValue(forKey key: String) {
        storage[key] = nil
    }

    func clearAllData() {
        storage.removeAll()
    }

    func flush() {}
}

private final class BlockingWriteDataStore: DataStore, @unchecked Sendable {
    @ReadWriteLock
    private var storage: [String: DataStoreValueResult] = [:]

    @ReadWriteLock
    private var hasFinishedWrite = false

    private let writeSemaphore = DispatchSemaphore(value: 0)
    private let writeFinishedSemaphore = DispatchSemaphore(value: 0)

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
        writeFinishedSemaphore.signal()
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

    func waitForWriteFinished(timeout: TimeInterval) -> Bool {
        writeFinishedSemaphore.wait(timeout: .now() + timeout) == .success
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

    var onReadStarted: (() -> Void)?

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
            self.onReadStarted?()
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
