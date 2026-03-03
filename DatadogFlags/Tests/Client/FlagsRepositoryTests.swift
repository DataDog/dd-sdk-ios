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
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(flags))
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
        waitForExpectations(timeout: 0)

        XCTAssertNotNil(capturedResult)
        XCTAssertNoThrow(try capturedResult?.get())

        XCTAssertEqual(flagsRepository.context, .mockAny())
        XCTAssertEqual(flagsRepository.flagAssignment(for: "test"), .mockAny())

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
        XCTAssertEqual(flagsRepository.stateManager.currentState, .notReady)
        let completed = expectation(description: "completed")

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.stateManager.currentState, .ready)
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
        XCTAssertEqual(flagsRepository.stateManager.currentState, .notReady)
        let completed = expectation(description: "completed")

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.stateManager.currentState, .error)
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
        XCTAssertEqual(flagsRepository.stateManager.currentState, .ready)

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
        XCTAssertEqual(flagsRepository.stateManager.currentState, .stale)
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
        XCTAssertEqual(flagsRepository.stateManager.currentState, .notReady)

        // When — start the fetch (but don't complete it)
        flagsRepository.setEvaluationContext(.mockAny()) { _ in }

        // Then — state should be reconciling while fetch is in progress
        XCTAssertEqual(flagsRepository.stateManager.currentState, .reconciling)

        // Complete the fetch
        capturedCompletion?(.success(["test": .mockAny()]))
        XCTAssertEqual(flagsRepository.stateManager.currentState, .ready)
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
        XCTAssertEqual(flagsRepository.stateManager.currentState, .ready)

        // When
        flagsRepository.reset()

        // Then
        XCTAssertEqual(flagsRepository.stateManager.currentState, .notReady)
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
        let asyncStore = AsyncDataStoreMock()
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
        // The fix ensures waitForFlagsDataRead() is called before checking hadFlags.
        let completed = expectation(description: "completed")
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            completed.fulfill()
        }

        // Then — should be .stale (not .error) because cached flags exist on disk
        waitForExpectations(timeout: 1)
        XCTAssertEqual(flagsRepository.stateManager.currentState, .stale)
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
        XCTAssertEqual(flagsRepository.stateManager.currentState, .ready)

        // Reach stale state
        fetcherMock.flagAssignmentsStub = { _, completion in
            completion(.failure(.networkError(URLError(.timedOut))))
        }
        let second = expectation(description: "second")
        flagsRepository.setEvaluationContext(.mockAny()) { _ in second.fulfill() }
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.stateManager.currentState, .stale)

        // Recover to ready
        fetcherMock.flagAssignmentsStub = { _, completion in
            completion(.success(["test": .mockAny()]))
        }
        let third = expectation(description: "third")
        flagsRepository.setEvaluationContext(.mockAny()) { _ in third.fulfill() }
        waitForExpectations(timeout: 0)
        XCTAssertEqual(flagsRepository.stateManager.currentState, .ready)
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
            stateInCompletion = flagsRepository.stateManager.currentState
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
            stateInCompletion = flagsRepository.stateManager.currentState
            completed.fulfill()
        }

        // Then — state must already be .error when completion is called (no cached flags)
        // (dd-openfeature-provider-swift depends on this ordering)
        waitForExpectations(timeout: 0)
        XCTAssertEqual(stateInCompletion, .error)
    }
}

// MARK: - Helpers

/// A data store mock that dispatches callbacks asynchronously on a background queue,
/// matching the production `FeatureDataStore` behavior. This enables testing race conditions
/// where the disk read may not have completed before other operations begin.
private final class AsyncDataStoreMock: DataStore {
    private let queue = DispatchQueue(label: "test.async-data-store")
    private var storage: [String: DataStoreValueResult] = [:]

    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {
        storage[key] = .value(value, version)
    }

    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        let result = storage[key] ?? .noValue
        queue.async {
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
}
