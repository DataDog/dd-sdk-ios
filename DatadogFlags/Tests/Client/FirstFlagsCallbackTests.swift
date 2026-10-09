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

final class FirstFlagsCallbackTests: XCTestCase {
    private func data(_ keys: [String]) -> FlagsData {
        FlagsData(flags: Dictionary(uniqueKeysWithValues: keys.map { ($0, FlagAssignment.mockAny()) }), context: .mockAny(), date: .mockAny())
    }

    func testSynchronousDiskReplayThroughPublicClient() throws {
        let scope = FeatureScopeMock()
        scope.dataStore.setValue(try JSONEncoder().encode(data(["disk"])), forKey: "test")
        let core = SingleFeatureCoreMock<FlagsFeature>()
        core.featureScopeOverride = scope
        Flags.enable(in: core)
        let client = FlagsClient.create(name: "test", in: core)
        let calls = ReadWriteLock(wrappedValue: 0)
        let subscription = client.onFirstFlags { event in
            XCTAssertEqual(event.type.rawValue, "CONFIGURATION_CHANGED")
            XCTAssertEqual(event.flagsChanged, ["disk"])
            XCTAssertNotNil(FlagsClient.shared(named: "test", in: core).getBooleanDetails(key: "disk", defaultValue: false))
            calls.mutate { $0 += 1 }
        }
        XCTAssertEqual(calls.wrappedValue, 1)
        subscription.cancel()
        subscription.cancel()
        client.onFirstFlags { _ in calls.mutate { $0 += 1 } }
        XCTAssertEqual(calls.wrappedValue, 2)
    }

    func testNestedNetworkCannotPublishReservedDiskEvent() throws {
        let store = FirstFlagsCallbackStore()
        let repository = ReadWriteLock<FlagsRepository?>(wrappedValue: nil)
        let events = ReadWriteLock<[FlagsClientEvent]>(wrappedValue: [])
        let completed = ReadWriteLock(wrappedValue: false)
        repository.wrappedValue = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["network": .mockAny()]))
                XCTAssertTrue(events.wrappedValue.isEmpty)
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store)
        )
        _ = repository.wrappedValue?.onFirstFlags { event in
            XCTAssertTrue(completed.wrappedValue)
            XCTAssertEqual(repository.wrappedValue?.flagAssignments()?.keys.sorted(), ["network"])
            events.mutate { $0.append(event) }
        }
        repository.wrappedValue?.setEvaluationContext(.mockAny()) { result in
            if case .failure(let error) = result { XCTFail("Unexpected failure: \(error)") }
            _ = repository.wrappedValue?.onFirstFlags { event in events.mutate { $0.append(event) } }
            XCTAssertTrue(events.wrappedValue.isEmpty)
            completed.wrappedValue = true
        }
        store.readCompletion?(.value(try JSONEncoder().encode(data(["disk"])), dataStoreDefaultKeyVersion))
        XCTAssertEqual(events.wrappedValue.map(\.flagsChanged), [["disk"], ["disk"]])
        repository.wrappedValue?.reset()
        _ = repository.wrappedValue?.onFirstFlags { event in
            XCTAssertEqual(event.flagsChanged, ["disk"])
            XCTAssertNil(repository.wrappedValue?.flagAssignments())
        }
    }

    func testDiskDoesNotWaitForAsynchronousNetworkResponse() throws {
        let store = FirstFlagsCallbackStore()
        var response: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                response = completion
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store)
        )
        let keys = ReadWriteLock<[String]?>(wrappedValue: nil)
        _ = repository.onFirstFlags { keys.wrappedValue = $0.flagsChanged }
        repository.setEvaluationContext(.mockAny()) { _ in }
        store.readCompletion?(.value(try JSONEncoder().encode(data([])), dataStoreDefaultKeyVersion))
        XCTAssertEqual(keys.wrappedValue, [])
        XCTAssertNotNil(response)
        response?(.success(["later": .mockAny()]))
        _ = repository.onFirstFlags { XCTAssertEqual($0.flagsChanged, []) }
    }

    func testMissingInvalidAndFailedLoadsWaitForSuccessfulEmptyNetwork() {
        for cached in [Data?.none, Data("invalid".utf8)] {
            let scope = FeatureScopeMock()
            if let cached { scope.dataStore.setValue(cached, forKey: "test") }
            var response: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
            let repository = FlagsRepository(
                clientName: "test",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                    response = completion
                },
                dateProvider: DateProviderMock(),
                featureScope: scope,
                initializationTimeout: nil
            )
            let events = ReadWriteLock<[FlagsClientEvent]>(wrappedValue: [])
            let completed = ReadWriteLock(wrappedValue: false)
            _ = repository.onFirstFlags { event in
                XCTAssertTrue(completed.wrappedValue)
                events.mutate { $0.append(event) }
            }
            repository.setEvaluationContext(.mockAny()) { _ in }
            response?(.failure(.invalidResponse))
            XCTAssertTrue(events.wrappedValue.isEmpty)
            repository.setEvaluationContext(.mockAny()) { result in
                if case .failure(let error) = result { XCTFail("Unexpected failure: \(error)") }
                completed.wrappedValue = true
            }
            response?(.success([:]))
            XCTAssertEqual(events.wrappedValue.map(\.flagsChanged), [[]])
        }
    }

    func testNetworkCallbackCanResetAndRegisterFromAnotherThreadWithoutTrailingWrites() {
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in completion(.success(["network": .mockAny()])) },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            initializationTimeout: nil
        )
        let repositoryAccess = ReadWriteLock(wrappedValue: repository)
        let completed = ReadWriteLock(wrappedValue: false)
        _ = repositoryAccess.wrappedValue.onFirstFlags { _ in
            XCTAssertTrue(completed.wrappedValue)
            let reentered = self.expectation(description: "cross-thread registration and evaluation")
            DispatchQueue.global().async {
                _ = repositoryAccess.wrappedValue.onFirstFlags { event in
                    XCTAssertEqual(event.flagsChanged, ["network"])
                    XCTAssertNotNil(repositoryAccess.wrappedValue.flagAssignment(for: "network"))
                }
                reentered.fulfill()
            }
            self.wait(for: [reentered], timeout: 5)
            repositoryAccess.wrappedValue.reset()
        }
        repository.setEvaluationContext(.mockAny()) { result in
            if case .failure(let error) = result { XCTFail("Unexpected failure: \(error)") }
            completed.wrappedValue = true
        }
        XCTAssertEqual(repository.state.currentState, .notReady)
        XCTAssertNil(repository.flagAssignments())
        _ = repository.onFirstFlags { XCTAssertEqual($0.flagsChanged, ["network"]) }
    }

    func testTimeoutAndResetDoNotCompleteOrCancelFirstFlags() {
        var timeout: (() -> Void)?
        var response: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in response = completion },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            initializationTimeout: 1,
            scheduleInitializationTimeout: { _, action in timeout = action; return {} }
        )
        let calls = ReadWriteLock(wrappedValue: 0)
        _ = repository.onFirstFlags { _ in calls.mutate { $0 += 1 } }
        repository.setEvaluationContext(.mockAny()) { _ in }
        timeout?()
        repository.reset()
        XCTAssertEqual(calls.wrappedValue, 0)
        response?(.success([:]))
        XCTAssertEqual(calls.wrappedValue, 1)
    }

    func testFailedUpdatesPreserveFirstEventWithoutReplayIO() {
        for error in [FlagsError.invalidResponse, .networkError(NSError(domain: "test", code: 1))] {
            for sameContext in [false, true] {
                let store = FirstFlagsCallbackStore()
                var response: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
                var fetches = 0
                let repository = FlagsRepository(
                    clientName: "test",
                    flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                        fetches += 1
                        response = completion
                    },
                    dateProvider: DateProviderMock(),
                    featureScope: FeatureScopeMock(dataStore: store),
                    initializationTimeout: nil
                )
                store.readCompletion?(.noValue)
                let events = ReadWriteLock<[FlagsClientEvent]>(wrappedValue: [])
                _ = repository.onFirstFlags { event in events.mutate { $0.append(event) } }
                XCTAssertTrue(events.wrappedValue.isEmpty)
                let context = FlagsEvaluationContext(targetingKey: "first")
                repository.setEvaluationContext(context) { result in
                    if case .failure(let error) = result { XCTFail("Unexpected failure: \(error)") }
                }
                response?(.success(["first": .mockAny()]))
                XCTAssertEqual(events.wrappedValue.count, 1)
                let first = events.wrappedValue[0]
                var failed = false
                repository.setEvaluationContext(sameContext ? context : .init(targetingKey: "second")) { result in
                    if case .failure = result { failed = true } else { XCTFail("Expected failure") }
                }
                response?(.failure(error))
                XCTAssertTrue(failed)
                XCTAssertEqual(repository.state.currentState, sameContext ? .stale : .error)
                XCTAssertEqual(repository.flagAssignments() != nil, sameContext)
                XCTAssertEqual(events.wrappedValue.count, 1)
                let reads = store.reads
                let writes = store.writes
                let fetchCount = fetches
                _ = repository.onFirstFlags { event in events.mutate { $0.append(event) } }
                XCTAssertEqual(events.wrappedValue.count, 2)
                XCTAssertEqual(events.wrappedValue[1].type, first.type)
                XCTAssertEqual(events.wrappedValue[1].flagsChanged, first.flagsChanged)
                XCTAssertEqual(store.reads, reads)
                XCTAssertEqual(store.writes, writes)
                XCTAssertEqual(fetches, fetchCount)
            }
        }
    }

    func testLateReplayCanOvertakePendingRegistration() {
        let callbacks = ReadWriteLock(wrappedValue: FirstFlagsCallbacks())
        let order = ReadWriteLock<[String]>(wrappedValue: [])
        _ = callbacks.wrappedValue.register { _ in
            order.mutate { $0.append("first") }
            _ = callbacks.wrappedValue.register { _ in order.mutate { $0.append("late") } }
        }
        _ = callbacks.wrappedValue.register { _ in order.mutate { $0.append("second") } }
        callbacks.wrappedValue.reserve(keys: ["flag"])?()
        XCTAssertEqual(order.wrappedValue, ["first", "late", "second"])
    }

    func testConcurrentNetworkInstallationsPublishOnlyOneFirstEvent() {
        var responses: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in responses.append(completion) },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            initializationTimeout: nil
        )
        let events = ReadWriteLock<[FlagsClientEvent]>(wrappedValue: [])
        _ = repository.onFirstFlags { event in
            events.mutate { $0.append(event) }
        }
        for _ in 0..<20 { repository.setEvaluationContext(.mockAny()) { _ in } }
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            responses[index](.success([String(index): .mockAny()]))
        }
        XCTAssertEqual(events.wrappedValue.count, 1)
        _ = repository.onFirstFlags { XCTAssertEqual($0.flagsChanged, events.wrappedValue.first?.flagsChanged) }
    }

    func testConcurrentInstallAndRegistrationRetainOneEvent() {
        let callbacks = ReadWriteLock(wrappedValue: FirstFlagsCallbacks())
        let values = ReadWriteLock<[[String]?]>(wrappedValue: [])
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            if index % 2 == 0 {
                callbacks.wrappedValue.reserve(keys: [String(index)])?()
            } else {
                _ = callbacks.wrappedValue.register { event in
                    values.mutate { $0.append(event.flagsChanged) }
                }
            }
        }
        XCTAssertEqual(values.wrappedValue.count, 50)
        XCTAssertTrue(values.wrappedValue.allSatisfy { $0 == values.wrappedValue.first! })
    }

    func testCancellationWhileReservedAndDuplicateRegistrations() {
        let callbacks = ReadWriteLock(wrappedValue: FirstFlagsCallbacks())
        let publish = callbacks.wrappedValue.reserve(keys: [])
        let calls = ReadWriteLock(wrappedValue: 0)
        let callback: FlagsClientEventListener = { _ in calls.mutate { $0 += 1 } }
        let subscription = callbacks.wrappedValue.register(callback)
        _ = callbacks.wrappedValue.register(callback)
        subscription.cancel()
        subscription.cancel()
        publish?()
        publish?()
        XCTAssertEqual(calls.wrappedValue, 1)
        _ = callbacks.wrappedValue.register(callback)
        XCTAssertEqual(calls.wrappedValue, 2)
    }

    func testCancelCopiedUnclaimedHandlerReleasesCaptureWhileEarlierHandlerBlocks() {
        let callbacks = ReadWriteLock(wrappedValue: FirstFlagsCallbacks())
        let entered = expectation(description: "first handler started")
        let finished = expectation(description: "publication finished")
        let release = DispatchSemaphore(value: 0)
        _ = callbacks.wrappedValue.register { _ in
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
        }
        var probe: LifetimeProbe? = LifetimeProbe()
        weak var weakProbe = probe
        let subscription = callbacks.wrappedValue.register { [probe] _ in
            withExtendedLifetime(probe) {}
            XCTFail("Cancelled handler must not start")
        }
        probe = nil
        let publish = callbacks.wrappedValue.reserve(keys: [])
        DispatchQueue.global().async { publish?(); finished.fulfill() }
        wait(for: [entered], timeout: 5)
        subscription.cancel()
        XCTAssertNil(weakProbe)
        release.signal()
        wait(for: [finished], timeout: 5)
    }

    func testClaimedHandlerCanCancelItselfAndOtherThreadDoesNotWait() {
        let callbacks = ReadWriteLock(wrappedValue: FirstFlagsCallbacks())
        let subscription = ReadWriteLock<(any FlagsSubscription)?>(wrappedValue: nil)
        let cancelled = expectation(description: "other thread cancellation")
        subscription.wrappedValue = callbacks.wrappedValue.register { _ in
            subscription.wrappedValue?.cancel()
            DispatchQueue.global().async { subscription.wrappedValue?.cancel(); cancelled.fulfill() }
            self.wait(for: [cancelled], timeout: 5)
        }
        callbacks.wrappedValue.reserve(keys: [])?()
    }

    func testOwnerDestructionReleasesPendingCaptureWithRetainedHandle() {
        var callbacks: FirstFlagsCallbacks? = FirstFlagsCallbacks()
        var probe: LifetimeProbe? = LifetimeProbe()
        weak var weakProbe = probe
        weak var weakOwner = callbacks
        let subscription = callbacks!.register { [probe] _ in withExtendedLifetime(probe) {} }
        probe = nil
        XCTAssertNotNil(weakProbe)
        callbacks = nil
        XCTAssertNil(weakOwner)
        XCTAssertNil(weakProbe)
        subscription.cancel()
        subscription.cancel()
    }

    func testCaptureDestructionReentersWithoutLocks() {
        let callbacks = ReadWriteLock(wrappedValue: FirstFlagsCallbacks())
        var probe: LifetimeProbe? = LifetimeProbe(onDeinit: {
            let subscription = callbacks.wrappedValue.register { _ in }
            subscription.cancel()
        })
        let subscription = callbacks.wrappedValue.register { [probe] _ in withExtendedLifetime(probe) {} }
        probe = nil
        subscription.cancel()
    }

    func testDeliveryReleasesCaptureWithRetainedHandle() {
        let callbacks = ReadWriteLock(wrappedValue: FirstFlagsCallbacks())
        var probe: LifetimeProbe? = LifetimeProbe()
        weak var weakProbe = probe
        let subscription = callbacks.wrappedValue.register { [probe] _ in withExtendedLifetime(probe) {} }
        probe = nil
        callbacks.wrappedValue.reserve(keys: [])?()
        XCTAssertNil(weakProbe)
        subscription.cancel()
    }

    func testDefaultAndFallbackDoNotRetainOrInvokeCallbacks() {
        let clients: [any FlagsClientProtocol] = [
            ExternalFlagsClient(),
            FallbackFlagsClient(name: "test", core: SingleFeatureCoreMock<FlagsFeature>())
        ]
        for client in clients {
            var probe: LifetimeProbe? = LifetimeProbe()
            weak var weakProbe = probe
            let subscription = client.onFirstFlags { [probe] _ in
                withExtendedLifetime(probe) {}
                XCTFail("No event expected")
            }
            probe = nil
            XCTAssertNil(weakProbe)
            subscription.cancel()
            subscription.cancel()
        }
    }

    func testRepositoryDestructionReleasesPendingCaptureWithRetainedHandle() {
        let store = FirstFlagsCallbackStore()
        var repository: FlagsRepository? = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store)
        )
        var probe: LifetimeProbe? = LifetimeProbe()
        weak var weakProbe = probe
        weak var weakRepository = repository
        let subscription = repository!.onFirstFlags { [probe] _ in withExtendedLifetime(probe) {} }
        probe = nil
        repository = nil
        XCTAssertNil(weakRepository)
        XCTAssertNil(weakProbe)
        subscription.cancel()
    }

    func testDiscardedSubscriptionStillDeliversPendingListener() {
        let callbacks = ReadWriteLock(wrappedValue: FirstFlagsCallbacks())
        let calls = ReadWriteLock(wrappedValue: 0)
        _ = callbacks.wrappedValue.register { _ in calls.mutate { $0 += 1 } }
        callbacks.wrappedValue.reserve(keys: [])?()
        XCTAssertEqual(calls.wrappedValue, 1)
    }

    func testEventValueSemanticsPreserveNilEmptyAndInputOrder() {
        var keys = ["b", "a", "b"]
        let event = FlagsClientEvent(type: .configurationChanged, flagsChanged: keys)
        keys.removeAll()
        XCTAssertEqual(event.flagsChanged, ["b", "a", "b"])
        XCTAssertNil(FlagsClientEvent(type: .configurationChanged).flagsChanged)
        XCTAssertEqual(FlagsClientEvent(type: .configurationChanged, flagsChanged: []).flagsChanged, [])
    }
}

private final class LifetimeProbe: Sendable {
    let onDeinit: (@Sendable () -> Void)?
    init(onDeinit: (@Sendable () -> Void)? = nil) { self.onDeinit = onDeinit }
    deinit { onDeinit?() }
}

private final class FirstFlagsCallbackStore: DataStore {
    var readCompletion: ((DataStoreValueResult) -> Void)?
    var reads = 0
    var writes = 0
    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) {
        reads += 1
        readCompletion = callback
    }
    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) { writes += 1 }
    func removeValue(forKey key: String) {}
    func clearAllData() {}
    func flush() {}
}

private final class ExternalFlagsClient: FlagsClientProtocol {
    func setEvaluationContext(_ context: FlagsEvaluationContext, completion: @escaping (Result<Void, FlagsError>) -> Void) {}
    func getDetails<T>(key: String, defaultValue: T) -> FlagDetails<T> where T: Equatable, T: FlagValue {
        FlagDetails(key: key, value: defaultValue, error: .providerNotReady)
    }
}
