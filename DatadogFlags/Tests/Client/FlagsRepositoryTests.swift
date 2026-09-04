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

    // MARK: - Latest-call-wins cancellation

    func testNewerContextCancelsTheSupersededRequest() {
        let fetcher = FlagAssignmentsFetcherMock { _, _ in }   // never completes
        let repository = makeRepository(fetcher: fetcher)

        repository.setEvaluationContext(.mockAny()) { _ in }
        XCTAssertEqual(fetcher.cancellationCount.value, 0)

        repository.setEvaluationContext(.mockRandom()) { _ in }

        XCTAssertEqual(
            fetcher.cancellationCount.value,
            1,
            "a newer context update must cancel the request it supersedes"
        )
    }

    func testResetCancelsTheInFlightRequest() {
        let fetcher = FlagAssignmentsFetcherMock { _, _ in }
        let repository = makeRepository(fetcher: fetcher)

        repository.setEvaluationContext(.mockAny()) { _ in }
        repository.reset()

        XCTAssertEqual(
            fetcher.cancellationCount.value,
            1,
            "reset() must cancel the in-flight assignment request"
        )
    }

    func testCompletedRequestIsNotCancelledByTheNextContext() {
        let fetcher = FlagAssignmentsFetcherMock { _, completion in
            completion(.success(["test": FlagAssignment.mockAny()]))
        }
        let repository = makeRepository(fetcher: fetcher)

        repository.setEvaluationContext(.mockAny()) { _ in }
        repository.setEvaluationContext(.mockRandom()) { _ in }

        XCTAssertEqual(
            fetcher.cancellationCount.value,
            0,
            "a request that already finished must not be cancelled"
        )
    }

    // MARK: - reset() ordering against the asynchronous data store

    // `reset()` must queue its removal in the same order as the generation change. The data store
    // is asynchronous in production, so a removal queued before the lock can be followed by a
    // write from the generation it invalidates, which restores the assignments on next launch.
    func testResetDuringSuccessfulWriteLeavesNoPersistedAssignments() {
        let fetchCompletion = ThreadSafeBox<((Result<[String: FlagAssignment], FlagsError>) -> Void)?>(nil)
        let fetcher = FlagAssignmentsFetcherMock { _, completion in
            fetchCompletion.value = completion
        }
        let resetRequested = DispatchSemaphore(value: 0)
        let resetReachedRepository = DispatchSemaphore(value: 0)
        let dateProvider = HookedDateProvider()
        let repository = makeRepository(fetcher: fetcher, dateProvider: dateProvider)

        repository.setEvaluationContext(.mockAny()) { _ in }

        // `now` is read while the success path holds `requestLock`, so this runs reset() at exactly
        // the moment Sameeran's scenario describes.
        dateProvider.onNow = {
            DispatchQueue.global().async {
                resetRequested.signal()
                repository.reset()
                resetReachedRepository.signal()
            }
            _ = resetRequested.wait(timeout: .now() + 1)
            // Give reset() time to queue a removal if it does so before taking the lock.
            Thread.sleep(forTimeInterval: 0.05)
        }

        fetchCompletion.value?(.success(["test": FlagAssignment.mockAny()]))
        _ = resetReachedRepository.wait(timeout: .now() + 2)

        XCTAssertNil(
            featureScope.dataStoreMock.storage[.mockAny()],
            "reset() must win: no assignments may remain persisted after it"
        )
        XCTAssertNil(repository.flagAssignments(), "in-memory assignments must be cleared too")
    }

    // MARK: - Superseded callers converge on the winner

    /// A superseded context update must still answer its caller. Cancelling the request without
    /// answering leaves a completion handler uncalled, and leaves `await setEvaluationContext(_:)`
    /// suspended forever on a continuation that never resumes.
    func testSupersededCallerIsAnsweredByTheWinner() {
        let transportCompletion = ThreadSafeBox<Flags.AssignmentRequestFetch.Completion?>(nil)
        let realFetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: featureScope,
            fetch: { _, completion in
                transportCompletion.value = completion
                return {}
            },
            assignmentRequestRetryCount: 0
        )
        let repository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: realFetcher,
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let supersededResult = ThreadSafeBox<Result<Void, FlagsError>?>(nil)
        let winnerResult = ThreadSafeBox<Result<Void, FlagsError>?>(nil)
        // Both callers, and neither one twice: a second call resumes a continuation twice.
        let answered = expectation(description: "the winner answers both callers")
        answered.expectedFulfillmentCount = 2
        answered.assertForOverFulfill = true

        repository.setEvaluationContext(.mockAny()) {
            supersededResult.value = $0
            answered.fulfill()
        }
        let supersededTransport = transportCompletion.value
        repository.setEvaluationContext(.mockRandom()) {
            winnerResult.value = $0
            answered.fulfill()
        }

        // The superseded request was cancelled, so its transport answer reaches no one. The
        // fetcher delivers on one serial queue, so the winner's answer proves this one had its
        // turn first.
        supersededTransport?(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
        transportCompletion.value?(.success(mockFlagAssignmentsFetchResponse(statusCode: 200)))
        waitForExpectations(timeout: 5)

        XCTAssertEqual(
            supersededResult.value?.isSuccess,
            winnerResult.value?.isSuccess,
            "a superseded caller must be answered by the winner, not silently dropped"
        )
    }

    func testSupersededCallerReceivesTheWinnersFailure() {
        let fetches = FetchCompletionRecorder()
        let repository = makeRepository(fetcher: fetches.fetcher)
        let supersededResult = ThreadSafeBox<Result<Void, FlagsError>?>(nil)

        repository.setEvaluationContext(.mockAny()) { supersededResult.value = $0 }
        repository.setEvaluationContext(.mockRandom()) { _ in }
        fetches.answer(1, with: .failure(.invalidResponse))

        guard case .failure(.invalidResponse)? = supersededResult.value else {
            XCTFail("a superseded caller must receive the winner's result, whatever it is")
            return
        }
    }

    func testEveryPendingCallerIsAnsweredExactlyOnce() {
        let fetches = FetchCompletionRecorder()
        let repository = makeRepository(fetcher: fetches.fetcher)
        let callbackCounts = ThreadSafeBox([0, 0, 0])

        for caller in 0..<3 {
            repository.setEvaluationContext(.mockRandom()) { _ in
                callbackCounts.mutate { $0[caller] += 1 }
            }
        }

        fetches.answer(2, with: .success(["test": .mockAny()]))
        // The superseded transports answer late, as real ones can. They must answer no one:
        // a second call into the same completion handler resumes a continuation twice and traps.
        fetches.answer(0, with: .success(["stale": .mockAny()]))
        fetches.answer(1, with: .failure(.invalidResponse))

        XCTAssertEqual(callbackCounts.value, [1, 1, 1], "every caller must be answered exactly once")
    }

    func testResetAnswersPendingCallers() {
        let fetcher = FlagAssignmentsFetcherMock { _, _ in }   // never completes
        let repository = makeRepository(fetcher: fetcher)
        let result = ThreadSafeBox<Result<Void, FlagsError>?>(nil)

        repository.setEvaluationContext(.mockAny()) { result.value = $0 }
        repository.reset()

        XCTAssertEqual(
            result.value?.isSuccess,
            true,
            "reset() cancels the request that would answer the caller, so it must answer it"
        )
    }

    func testDeallocatedRepositoryCancelsTheInFlightRequest() {
        let fetcher = FlagAssignmentsFetcherMock { _, _ in }   // never completes
        var repository: FlagsRepository? = makeRepository(fetcher: fetcher)

        repository?.setEvaluationContext(.mockAny()) { _ in }
        XCTAssertEqual(fetcher.cancellationCount.value, 0)

        repository = nil

        XCTAssertEqual(
            fetcher.cancellationCount.value,
            1,
            "nothing consumes the result once the repository is gone, so the request must stop"
        )
    }

    func testDeallocatedRepositoryAnswersCallersWaitingOnTheDiskRead() {
        // A caller that arrives before the disk read finishes waits in `diskReadState`, not in
        // the request pool. Deallocation must answer it too.
        let featureScope = FeatureScopeMock(dataStore: NeverReadingDataStore())
        let fetcher = FlagAssignmentsFetcherMock { _, _ in }
        let result = ThreadSafeBox<Result<Void, FlagsError>?>(nil)
        var repository: FlagsRepository? = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: fetcher,
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )

        repository?.setEvaluationContext(.mockAny()) { result.value = $0 }
        XCTAssertNil(result.value, "the disk read has not finished, so no request has started")

        repository = nil

        guard case .failure(.clientNotInitialized)? = result.value else {
            XCTFail("a caller waiting on the disk read must be answered when the client goes away")
            return
        }
    }

    func testDeallocatedRepositoryAnswersPendingCallers() {
        let fetcher = FlagAssignmentsFetcherMock { _, _ in }   // never completes
        let result = ThreadSafeBox<Result<Void, FlagsError>?>(nil)
        var repository: FlagsRepository? = makeRepository(fetcher: fetcher)

        repository?.setEvaluationContext(.mockAny()) { result.value = $0 }
        XCTAssertNil(result.value, "the request is still in flight")

        repository = nil

        guard case .failure(.clientNotInitialized)? = result.value else {
            XCTFail("a deallocated repository must answer the callers that nothing else can answer")
            return
        }
    }

    /// The realistic form of the same hazard: a listener starts new work from its own callback.
    func testResetStartedByAListenerIsNotOverwrittenByTheInterruptedDelivery() {
        let fetcher = FlagAssignmentsFetcherMock { _, _ in }   // never completes
        let repository = makeRepository(fetcher: fetcher)
        let observedStates = ThreadSafeBox<[FlagsClientState]>([])
        var hasReset = false
        let changer = BlockingStateListener { state in
            guard state == .reconciling, !hasReset else {
                return
            }
            hasReset = true
            repository.reset()
        }
        let observer = BlockingStateListener { state in
            observedStates.mutate { $0.append(state) }
        }
        repository.state.addListener(changer)
        repository.state.addListener(observer)
        observedStates.mutate { $0.removeAll() }

        repository.setEvaluationContext(.mockAny()) { _ in }

        XCTAssertEqual(
            observedStates.value.last,
            repository.state.currentState,
            "a listener's last callback must equal currentState, got \(observedStates.value)"
        )
    }

    private func makeRepository(
        fetcher: FlagAssignmentsFetcherMock,
        dateProvider: any DateProvider = DateProviderMock()
    ) -> FlagsRepository {
        FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: fetcher,
            dateProvider: dateProvider,
            featureScope: featureScope
        )
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
        // The fix ensures waitForFlagsDataRead() is called before checking hadFlags.
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
        guard capturedCompletions.count == 2 else {
            return XCTFail("Expected two in-flight requests")
        }

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

    func testOverlappingContextUpdatesLaterSuccessIsNotOverwrittenByEarlierSuccess() {
        var capturedCompletions: [(
            context: FlagsEvaluationContext,
            completion: (Result<[String: FlagAssignment], FlagsError>) -> Void
        )] = []
        let fetcherMock = FlagAssignmentsFetcherMock { context, completion in
            capturedCompletions.append((context, completion))
        }
        let contextA = FlagsEvaluationContext(targetingKey: "user-A", attributes: [:])
        let contextB = FlagsEvaluationContext(targetingKey: "user-B", attributes: [:])
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: fetcherMock,
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let completedA = expectation(description: "request A completed")
        let completedB = expectation(description: "request B completed")

        flagsRepository.setEvaluationContext(contextA) { _ in completedA.fulfill() }
        flagsRepository.setEvaluationContext(contextB) { _ in completedB.fulfill() }

        guard capturedCompletions.count == 2 else {
            return XCTFail("Expected two in-flight requests")
        }
        capturedCompletions[1].completion(.success(["new": .mockAny()]))
        capturedCompletions[0].completion(.success(["old": .mockAny()]))

        waitForExpectations(timeout: 1)
        XCTAssertEqual(flagsRepository.context, contextB)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "new"))
        XCTAssertNil(flagsRepository.flagAssignment(for: "old"))
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    func testResetSupersedesInflightContextUpdate() {
        var capturedCompletion: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                capturedCompletion = completion
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let completed = expectation(description: "request completed")
        var capturedResult: Result<Void, FlagsError>?

        flagsRepository.setEvaluationContext(.mockAny()) { result in
            capturedResult = result
            completed.fulfill()
        }
        flagsRepository.reset()
        capturedCompletion?(.success(["old": .mockAny()]))

        waitForExpectations(timeout: 1)
        XCTAssertNoThrow(try capturedResult?.get())
        XCTAssertNil(flagsRepository.context)
        XCTAssertNil(flagsRepository.flagAssignment(for: "old"))
        XCTAssertEqual(flagsRepository.state.currentState, .notReady)
        featureScope.dataStore.flush()
        XCTAssertTrue(featureScope.dataStoreMock.storage.isEmpty)
    }

    func testStateListenerIsNotNotifiedWhileHoldingTheRequestLock() {
        let otherThreadFinished = DispatchSemaphore(value: 0)
        let otherThreadEnteredRepository = ThreadSafeBox(false)
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["test": FlagAssignment.mockAny()]))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope
        )
        let listener = BlockingStateListener { state in
            guard state == .reconciling else {
                return
            }
            DispatchQueue.global().async {
                flagsRepository.reset()
                otherThreadEnteredRepository.value = true
                otherThreadFinished.signal()
            }
            _ = otherThreadFinished.wait(timeout: .now() + 1)
        }
        flagsRepository.state.addListener(listener)

        flagsRepository.setEvaluationContext(.mockAny()) { _ in }

        XCTAssertTrue(
            otherThreadEnteredRepository.value,
            "a state listener must not be notified while the repository holds its request lock"
        )
        withExtendedLifetime(listener) {}
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

/// Data store whose read never calls back, so the repository stays in its pre-read state.
private final class NeverReadingDataStore: DataStore {
    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {}
    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {}
    func removeValue(forKey key: String) {}
    func clearAllData() {}
    func flush() {}
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

/// Holds every fetch completion the repository hands out, so a test can decide which request
/// answers, and in which order.
private final class FetchCompletionRecorder {
    typealias Completion = (Result<[String: FlagAssignment], FlagsError>) -> Void

    private let completions = ThreadSafeBox<[Completion]>([])
    let fetcher: FlagAssignmentsFetcherMock

    init() {
        let completions = self.completions
        fetcher = FlagAssignmentsFetcherMock { _, completion in
            completions.mutate { $0.append(completion) }
        }
    }

    func answer(_ index: Int, with result: Result<[String: FlagAssignment], FlagsError>) {
        completions.value[index](result)
    }
}

private final class BlockingStateListener: FlagsStateListener {
    private let onChange: (FlagsClientState) -> Void

    init(onChange: @escaping (FlagsClientState) -> Void) {
        self.onChange = onChange
    }

    func flagsStateDidChange(_ newState: FlagsClientState) {
        onChange(newState)
    }
}

/// Date provider that runs a hook when `now` is read, so a test can act while the repository
/// holds `requestLock`.
private final class HookedDateProvider: DateProvider, @unchecked Sendable {
    var onNow: (() -> Void)?

    var now: Date {
        onNow?()
        return Date()
    }
}
