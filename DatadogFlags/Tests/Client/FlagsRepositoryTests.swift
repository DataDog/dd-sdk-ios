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

    func testImmediateInitializationTimeoutCannotBeOverwrittenByReconciling() throws {
        // Given
        var fetchCompletion: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
        var stateAtCallback: FlagsClientState?
        var callbackResult: Result<Void, FlagsError>?
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                fetchCompletion = completion
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: 0,
            scheduleInitializationTimeout: { _, action in
                action()
                return {}
            }
        )

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { result in
            stateAtCallback = flagsRepository.state.currentState
            callbackResult = result
        }

        // Then
        XCTAssertEqual(stateAtCallback, .error)
        XCTAssertEqual(flagsRepository.state.currentState, .error)
        guard case .failure(.initializationTimedOut) = callbackResult else {
            return XCTFail("Expected initialization timeout")
        }

        // When
        try XCTUnwrap(fetchCompletion)(.success(["test": .mockAny()]))

        // Then
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
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

    func testInitializationTimeoutIsDisabledByDefault() {
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
            scheduleInitializationTimeout: { _, _ in
                scheduledTimeoutCount += 1
                return {}
            }
        )

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { _ in callbackCount += 1 }

        // Then
        XCTAssertEqual(scheduledTimeoutCount, 0)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
    }

    func testInitializationTimeoutRacingSuccessfulCompletionIsConsistent() throws {
        let iterations = 10_000
        let raceQueue = DispatchQueue(
            label: "com.datadog.flags.initialization-timeout-race",
            attributes: .concurrent
        )

        for iteration in 0..<iterations {
            // Given
            let iterationFeatureScope = FeatureScopeMock()
            var fetchCompletion: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
            var timeoutAction: (() -> Void)?
            let flagsRepository = FlagsRepository(
                clientName: "race-\(iteration)",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                    fetchCompletion = completion
                },
                dateProvider: DateProviderMock(),
                featureScope: iterationFeatureScope,
                initializationTimeout: 2.5,
                scheduleInitializationTimeout: { _, action in
                    timeoutAction = action
                    return {}
                }
            )

            let callbackLock = NSLock()
            var callbackCount = 0
            var callbackSucceeded = false
            var callbackTimedOut = false
            var stateAtCallback: FlagsClientState?
            flagsRepository.setEvaluationContext(.mockAny()) { result in
                callbackLock.lock()
                callbackCount += 1
                stateAtCallback = flagsRepository.state.currentState
                switch result {
                case .success:
                    callbackSucceeded = true
                case .failure(.initializationTimedOut):
                    callbackTimedOut = true
                case .failure:
                    break
                }
                callbackLock.unlock()
            }

            let start = DispatchSemaphore(value: 0)
            let finished = DispatchGroup()
            let completion = try XCTUnwrap(fetchCompletion)
            let timeout = try XCTUnwrap(timeoutAction)

            // When
            finished.enter()
            raceQueue.async {
                start.wait()
                completion(.success(["test": .mockAny()]))
                finished.leave()
            }
            finished.enter()
            raceQueue.async {
                start.wait()
                timeout()
                finished.leave()
            }
            start.signal()
            start.signal()

            // Then
            XCTAssertEqual(
                finished.wait(timeout: .now() + 2),
                .success,
                "Race did not finish at iteration \(iteration)"
            )

            callbackLock.lock()
            let observedCallbackCount = callbackCount
            let observedCallbackSucceeded = callbackSucceeded
            let observedCallbackTimedOut = callbackTimedOut
            let observedStateAtCallback = stateAtCallback
            callbackLock.unlock()

            XCTAssertEqual(observedCallbackCount, 1, "Iteration \(iteration)")
            XCTAssertNotEqual(observedCallbackSucceeded, observedCallbackTimedOut, "Iteration \(iteration)")
            if observedCallbackSucceeded {
                XCTAssertEqual(observedStateAtCallback, .ready, "Iteration \(iteration)")
            } else {
                // A timeout publishes error first, but the intentionally unblocked late success may
                // recover to ready before the callback reads the state.
                XCTAssertTrue(
                    observedStateAtCallback == .error || observedStateAtCallback == .ready,
                    "Iteration \(iteration)"
                )
            }
            XCTAssertEqual(flagsRepository.state.currentState, .ready, "Iteration \(iteration)")
        }
    }

    func testInitializationTimeoutCompletesWhileTheDiskReadIsStillPending() throws {
        // Given
        var timeoutAction: (() -> Void)?
        var fetchStartedCount = 0
        var callbackResult: Result<Void, FlagsError>?
        let pendingFeatureScope = FeatureScopeMock(dataStore: NeverRespondingDataStoreMock())
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, _ in
                fetchStartedCount += 1
            },
            dateProvider: DateProviderMock(),
            featureScope: pendingFeatureScope,
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, action in
                timeoutAction = action
                return {}
            }
        )

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { callbackResult = $0 }
        try XCTUnwrap(timeoutAction)()

        // Then
        XCTAssertEqual(fetchStartedCount, 0)
        guard case .failure(.initializationTimedOut) = callbackResult else {
            return XCTFail("Expected initialization timeout")
        }
        XCTAssertEqual(flagsRepository.state.currentState, .error)
    }

    func testLateDiskReadDoesNotRestoreFlagsForAnotherContextAfterTimeout() throws {
        // Given
        let cachedContext = FlagsEvaluationContext(targetingKey: "cached-user", attributes: [:])
        let requestedContext = FlagsEvaluationContext(targetingKey: "requested-user", attributes: [:])
        let cachedData = FlagsData(
            flags: ["test": .mockAny()],
            context: cachedContext,
            date: .mockAny()
        )
        let dataStore = ManuallyRespondingDataStoreMock(
            result: .value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
        )
        var timeoutAction: (() -> Void)?
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, _ in },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore),
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, action in
                timeoutAction = action
                return {}
            }
        )

        // When
        flagsRepository.setEvaluationContext(requestedContext) { _ in }
        try XCTUnwrap(timeoutAction)()
        dataStore.respond()

        // Then
        XCTAssertEqual(flagsRepository.state.currentState, .error)
        XCTAssertNil(flagsRepository.context)
        XCTAssertNil(flagsRepository.flagAssignment(for: "test"))
    }

    func testLateMatchingDiskReadReportsStaleAfterTimeout() throws {
        // Given
        let context = FlagsEvaluationContext(targetingKey: "cached-user", attributes: [:])
        let cachedData = FlagsData(flags: ["test": .mockAny()], context: context, date: .mockAny())
        let dataStore = ManuallyRespondingDataStoreMock(
            result: .value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
        )
        var timeoutAction: (() -> Void)?
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, _ in },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore),
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, action in
                timeoutAction = action
                return {}
            }
        )

        // When
        flagsRepository.setEvaluationContext(context) { _ in }
        try XCTUnwrap(timeoutAction)()
        dataStore.respond()

        // Then
        XCTAssertEqual(flagsRepository.state.currentState, .stale)
        XCTAssertEqual(flagsRepository.context, context)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "test"))
    }

    func testLateMatchingDiskReadIsCompleteBeforeStaleNotification() throws {
        // Given
        let context = FlagsEvaluationContext(targetingKey: "cached-user", attributes: [:])
        let cachedData = FlagsData(flags: ["test": .mockAny()], context: context, date: .mockAny())
        let dataStore = ManuallyRespondingDataStoreMock(
            result: .value(try JSONEncoder().encode(cachedData), dataStoreDefaultKeyVersion)
        )
        var timeoutAction: (() -> Void)?
        var lookupDuration: TimeInterval?
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, _ in },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: dataStore),
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, action in
                timeoutAction = action
                return {}
            }
        )
        let listener = BlockingStateListener { state in
            guard state == .stale else {
                return
            }
            let start = DispatchTime.now().uptimeNanoseconds
            _ = flagsRepository.flagAssignment(for: "test")
            lookupDuration = TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        }
        flagsRepository.state.addListener(listener)

        // When
        flagsRepository.setEvaluationContext(context) { _ in }
        try XCTUnwrap(timeoutAction)()
        dataStore.respond()

        // Then
        XCTAssertLessThan(try XCTUnwrap(lookupDuration), 0.05)
        withExtendedLifetime(listener) {}
    }

    func testInitializationTimeoutMillisecondsClampsInsteadOfTruncating() {
        XCTAssertEqual(FlagsRepository.initializationTimeoutMilliseconds(for: 0), 0)
        XCTAssertEqual(FlagsRepository.initializationTimeoutMilliseconds(for: -1), 0)
        XCTAssertEqual(FlagsRepository.initializationTimeoutMilliseconds(for: .nan), 0)
        XCTAssertEqual(FlagsRepository.initializationTimeoutMilliseconds(for: 0.25), 250)
        XCTAssertEqual(FlagsRepository.initializationTimeoutMilliseconds(for: 5), 5_000)
        XCTAssertEqual(FlagsRepository.initializationTimeoutMilliseconds(for: 86_400), 86_400_000)
        XCTAssertEqual(FlagsRepository.initializationTimeoutMilliseconds(for: .infinity), 0)
        XCTAssertEqual(
            FlagsRepository.initializationTimeoutMilliseconds(for: .greatestFiniteMagnitude),
            .max
        )
    }

    func testDefaultSchedulerRunsThenCancellationPreventsTheAction() {
        // Given
        let fired = expectation(description: "the timeout action ran")
        let cancelledFired = expectation(description: "a cancelled timeout must not run")
        cancelledFired.isInverted = true

        // When
        _ = FlagsRepository.scheduleInitializationTimeout(0.01) { fired.fulfill() }
        let cancelTimeout = FlagsRepository.scheduleInitializationTimeout(0.01) {
            cancelledFired.fulfill()
        }
        cancelTimeout()

        // Then
        waitForExpectations(timeout: 1)
    }

    func testStateListenerCannotTakeTheInitializationTimeoutFromTheFirstCaller() throws {
        // Given
        var timeoutAction: (() -> Void)?
        var firstResult: Result<Void, FlagsError>?
        var nestedResult: Result<Void, FlagsError>?
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
        var didStartNestedCall = false
        let listener = BlockingStateListener { state in
            guard state == .reconciling, !didStartNestedCall else {
                return
            }
            didStartNestedCall = true
            flagsRepository.setEvaluationContext(.mockRandom()) { nestedResult = $0 }
        }
        flagsRepository.state.addListener(listener)

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { firstResult = $0 }
        try XCTUnwrap(timeoutAction)()

        // Then
        guard case .failure(.initializationTimedOut) = firstResult else {
            return XCTFail("The first caller must own the initialization timeout")
        }
        XCTAssertNil(nestedResult)
        withExtendedLifetime(listener) {}
    }

    func testInitializationTimeoutAppliesAgainAfterReset() throws {
        // Given
        var timeoutActions: [() -> Void] = []
        var callbackResults: [Result<Void, FlagsError>] = []
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, _ in },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: 2.5,
            scheduleInitializationTimeout: { _, action in
                timeoutActions.append(action)
                return {}
            }
        )

        // When
        flagsRepository.setEvaluationContext(.mockAny()) { callbackResults.append($0) }
        try XCTUnwrap(timeoutActions.first)()
        flagsRepository.reset()
        flagsRepository.setEvaluationContext(.mockRandom()) { callbackResults.append($0) }

        // Then
        XCTAssertEqual(timeoutActions.count, 2)
        guard timeoutActions.count == 2 else {
            return
        }
        timeoutActions[1]()
        XCTAssertEqual(callbackResults.count, 2)
        for result in callbackResults {
            guard case .failure(.initializationTimedOut) = result else {
                return XCTFail("Expected initialization timeout")
            }
        }
    }

    func testSupersededInitializationTimeoutDoesNotOverrideANewerSuccess() throws {
        // Given
        let contextA = FlagsEvaluationContext(targetingKey: "user-A", attributes: [:])
        let contextB = FlagsEvaluationContext(targetingKey: "user-B", attributes: [:])
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

        // When
        flagsRepository.setEvaluationContext(contextA) { firstResult = $0 }
        flagsRepository.setEvaluationContext(contextB) { _ in }
        fetchCompletions[1](.success(["flag-b": .mockAny()]))
        try XCTUnwrap(timeoutAction)()

        // Then
        guard case .failure(.initializationTimedOut) = firstResult else {
            return XCTFail("Expected the first caller to time out")
        }
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
        XCTAssertEqual(flagsRepository.context, contextB)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "flag-b"))
    }

    func testSupersededLateSuccessDoesNotReplaceANewerContext() throws {
        // Given
        let contextA = FlagsEvaluationContext(targetingKey: "user-A", attributes: [:])
        let contextB = FlagsEvaluationContext(targetingKey: "user-B", attributes: [:])
        var fetchCompletions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        var timeoutAction: (() -> Void)?
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

        // When
        flagsRepository.setEvaluationContext(contextA) { _ in }
        try XCTUnwrap(timeoutAction)()
        flagsRepository.setEvaluationContext(contextB) { _ in }
        fetchCompletions[1](.success(["flag-b": .mockAny()]))
        fetchCompletions[0](.success(["flag-a": .mockAny()]))

        // Then
        XCTAssertEqual(flagsRepository.state.currentState, .ready)
        XCTAssertEqual(flagsRepository.context, contextB)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "flag-b"))
        XCTAssertNil(flagsRepository.flagAssignment(for: "flag-a"))
    }

    func testOrdinaryOverlappingSuccessPublishesBeforeCompletion() {
        // Given
        let contextA = FlagsEvaluationContext(targetingKey: "user-A", attributes: [:])
        let contextB = FlagsEvaluationContext(targetingKey: "user-B", attributes: [:])
        var fetchCompletions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        var firstResult: Result<Void, FlagsError>?
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                fetchCompletions.append(completion)
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: nil
        )

        // When
        flagsRepository.setEvaluationContext(contextA) { firstResult = $0 }
        flagsRepository.setEvaluationContext(contextB) { _ in }
        fetchCompletions[0](.success(["flag-a": .mockAny()]))

        // Then
        guard case .success = firstResult else {
            return XCTFail("Expected the published ordinary request to succeed")
        }
        XCTAssertEqual(flagsRepository.context, contextA)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "flag-a"))
    }

    func testInitializationTimeoutDiscardsFlagsCachedForAnotherContext() throws {
        // Given
        let cachedContext = FlagsEvaluationContext(targetingKey: "cached-user", attributes: [:])
        let requestedContext = FlagsEvaluationContext(targetingKey: "requested-user", attributes: [:])
        let cachedData = FlagsData(
            flags: ["test": .mockAny()],
            context: cachedContext,
            date: .mockAny()
        )
        try featureScope.dataStoreMock.setValue(
            JSONEncoder().encode(cachedData),
            forKey: .mockAny()
        )
        var timeoutAction: (() -> Void)?
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

        // When
        flagsRepository.setEvaluationContext(requestedContext) { _ in }
        try XCTUnwrap(timeoutAction)()

        // Then
        XCTAssertEqual(flagsRepository.state.currentState, .error)
        XCTAssertNil(flagsRepository.context)
        XCTAssertNil(flagsRepository.flagAssignment(for: "test"))
    }

    func testInitializationTimeoutWithMatchingCachedFlagsReportsStale() throws {
        // Given
        let context = FlagsEvaluationContext(targetingKey: "cached-user", attributes: [:])
        let cachedData = FlagsData(
            flags: ["test": .mockAny()],
            context: context,
            date: .mockAny()
        )
        try featureScope.dataStoreMock.setValue(
            JSONEncoder().encode(cachedData),
            forKey: .mockAny()
        )
        var timeoutAction: (() -> Void)?
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

        // When
        flagsRepository.setEvaluationContext(context) { _ in }
        try XCTUnwrap(timeoutAction)()

        // Then
        XCTAssertEqual(flagsRepository.state.currentState, .stale)
        XCTAssertNotNil(flagsRepository.flagAssignment(for: "test"))
    }

    func testBlockedTimeoutCallbackDoesNotBlockLateReadyState() throws {
        // Given
        var fetchCompletion: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
        var timeoutAction: (() -> Void)?
        let callbackStarted = DispatchSemaphore(value: 0)
        let releaseCallback = DispatchSemaphore(value: 0)
        let readyPublished = expectation(description: "late ready state published")
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
        let listener = BlockingStateListener { state in
            if state == .ready {
                readyPublished.fulfill()
            }
        }
        flagsRepository.state.addListener(listener)
        flagsRepository.setEvaluationContext(.mockAny()) { _ in
            callbackStarted.signal()
            releaseCallback.wait()
        }

        // When
        DispatchQueue.global().async {
            timeoutAction?()
        }
        XCTAssertEqual(callbackStarted.wait(timeout: .now() + 1), .success)
        DispatchQueue.global().async {
            fetchCompletion?(.success(["test": .mockAny()]))
        }

        // Then
        wait(for: [readyPublished], timeout: 0.25)
        releaseCallback.signal()
        withExtendedLifetime(listener) {}
    }

    func testBlockedReadyListenerDoesNotDelaySuccessfulCompletion() {
        // Given
        let listenerStarted = DispatchSemaphore(value: 0)
        let releaseListener = DispatchSemaphore(value: 0)
        let completionDelivered = DispatchSemaphore(value: 0)
        let updateFinished = DispatchSemaphore(value: 0)
        let flagsRepository = FlagsRepository(
            clientName: .mockAny(),
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["test": .mockAny()]))
            },
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            initializationTimeout: 2.5
        )
        let listener = BlockingStateListener { state in
            if state == .ready {
                listenerStarted.signal()
                releaseListener.wait()
            }
        }
        flagsRepository.state.addListener(listener)

        // When
        DispatchQueue.global().async {
            flagsRepository.setEvaluationContext(.mockAny()) { _ in
                completionDelivered.signal()
            }
            updateFinished.signal()
        }
        XCTAssertEqual(listenerStarted.wait(timeout: .now() + 1), .success)
        let completionResult = completionDelivered.wait(timeout: .now() + 0.25)
        releaseListener.signal()

        // Then
        XCTAssertEqual(completionResult, .success)
        XCTAssertEqual(updateFinished.wait(timeout: .now() + 1), .success)
        withExtendedLifetime(listener) {}
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

private final class BlockingStateListener: FlagsStateListener {
    private let onChange: (FlagsClientState) -> Void

    init(onChange: @escaping (FlagsClientState) -> Void) {
        self.onChange = onChange
    }

    func flagsStateDidChange(_ newState: FlagsClientState) {
        onChange(newState)
    }
}

private final class NeverRespondingDataStoreMock: DataStore {
    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {}
    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {}
    func removeValue(forKey key: String) {}
    func clearAllData() {}
    func flush() {}
}

private final class ManuallyRespondingDataStoreMock: DataStore {
    private let result: DataStoreValueResult
    private var callback: ((DataStoreValueResult) -> Void)?

    init(result: DataStoreValueResult) {
        self.result = result
    }

    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {}

    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        self.callback = callback
    }

    func respond() {
        callback?(result)
        callback = nil
    }

    func removeValue(forKey key: String) {}
    func clearAllData() {}
    func flush() {}
}
