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
        var calls = 0
        let cancel = client.onFirstFlags { [weak client] event in
            XCTAssertEqual(event.type.rawValue, "CONFIGURATION_CHANGED")
            XCTAssertEqual(event.flagsChanged, ["disk"])
            XCTAssertNotNil(client?.getBooleanDetails(key: "disk", defaultValue: false))
            calls += 1
        }
        XCTAssertEqual(calls, 1)
        cancel()
        cancel()
        client.onFirstFlags { _ in calls += 1 }
        XCTAssertEqual(calls, 2)
    }

    func testNestedNetworkCannotPublishReservedDiskEvent() throws {
        let store = FirstFlagsCallbackStore()
        var repository: FlagsRepository?
        var events: [FlagsClientEvent] = []
        var completed = false
        repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["network": .mockAny()]))
                XCTAssertTrue(events.isEmpty)
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store)
        )
        _ = repository?.onFirstFlags { event in
            XCTAssertTrue(completed)
            XCTAssertEqual(repository?.flagAssignments()?.keys.sorted(), ["network"])
            events.append(event)
        }
        repository?.setEvaluationContext(.mockAny()) { _ in
            _ = repository?.onFirstFlags { events.append($0) }
            XCTAssertTrue(events.isEmpty)
            completed = true
        }
        store.readCompletion?(.value(try JSONEncoder().encode(data(["disk"])), dataStoreDefaultKeyVersion))
        XCTAssertEqual(events.map(\.flagsChanged), [["disk"], ["disk"]])
        repository?.reset()
        _ = repository?.onFirstFlags { event in
            XCTAssertEqual(event.flagsChanged, ["disk"])
            XCTAssertNil(repository?.flagAssignments())
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
        var keys: [String]?
        _ = repository.onFirstFlags { keys = $0.flagsChanged }
        repository.setEvaluationContext(.mockAny()) { _ in }
        store.readCompletion?(.value(try JSONEncoder().encode(data([])), dataStoreDefaultKeyVersion))
        XCTAssertEqual(keys, [])
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
            var events: [FlagsClientEvent] = []
            var completed = false
            _ = repository.onFirstFlags { event in
                XCTAssertTrue(completed)
                events.append(event)
            }
            repository.setEvaluationContext(.mockAny()) { _ in }
            response?(.failure(.invalidResponse))
            XCTAssertTrue(events.isEmpty)
            repository.setEvaluationContext(.mockAny()) { _ in completed = true }
            response?(.success([:]))
            XCTAssertEqual(events.map(\.flagsChanged), [[]])
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
        var completed = false
        _ = repository.onFirstFlags { _ in
            XCTAssertTrue(completed)
            let reentered = self.expectation(description: "cross-thread registration and evaluation")
            DispatchQueue.global().async {
                _ = repository.onFirstFlags { event in
                    XCTAssertEqual(event.flagsChanged, ["network"])
                    XCTAssertNotNil(repository.flagAssignment(for: "network"))
                }
                reentered.fulfill()
            }
            self.wait(for: [reentered], timeout: 5)
            repository.reset()
        }
        repository.setEvaluationContext(.mockAny()) { _ in completed = true }
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
        var calls = 0
        _ = repository.onFirstFlags { _ in calls += 1 }
        repository.setEvaluationContext(.mockAny()) { _ in }
        timeout?()
        repository.reset()
        XCTAssertEqual(calls, 0)
        response?(.success([:]))
        XCTAssertEqual(calls, 1)
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
        let lock = NSLock()
        var events: [FlagsClientEvent] = []
        _ = repository.onFirstFlags { event in
            lock.lock()
            events.append(event)
            lock.unlock()
        }
        for _ in 0..<20 { repository.setEvaluationContext(.mockAny()) { _ in } }
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            responses[index](.success([String(index): .mockAny()]))
        }
        XCTAssertEqual(events.count, 1)
        _ = repository.onFirstFlags { XCTAssertEqual($0.flagsChanged, events.first?.flagsChanged) }
    }

    func testConcurrentInstallAndRegistrationRetainOneEvent() {
        let callbacks = FirstFlagsCallbacks()
        let lock = NSLock()
        var values: [[String]?] = []
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            if index % 2 == 0 {
                callbacks.reserve(keys: [String(index)])?()
            } else {
                _ = callbacks.register { event in
                    lock.lock()
                    values.append(event.flagsChanged)
                    lock.unlock()
                }
            }
        }
        XCTAssertEqual(values.count, 50)
        XCTAssertTrue(values.allSatisfy { $0 == values.first! })
    }

    func testCancellationWhileReservedAndDuplicateRegistrations() {
        let callbacks = FirstFlagsCallbacks()
        let publish = callbacks.reserve(keys: [])
        var calls = 0
        let callback: (FlagsClientEvent) -> Void = { _ in calls += 1 }
        let cancel = callbacks.register(callback)
        _ = callbacks.register(callback)
        cancel()
        cancel()
        publish?()
        publish?()
        XCTAssertEqual(calls, 1)
        _ = callbacks.register(callback)
        XCTAssertEqual(calls, 2)
    }

    func testCancelCopiedUnclaimedHandlerReleasesCaptureWhileEarlierHandlerBlocks() {
        let callbacks = FirstFlagsCallbacks()
        let entered = expectation(description: "first handler started")
        let finished = expectation(description: "publication finished")
        let release = DispatchSemaphore(value: 0)
        _ = callbacks.register { _ in
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
        }
        var probe: LifetimeProbe? = LifetimeProbe()
        weak var weakProbe = probe
        let cancel = callbacks.register { [probe] _ in
            withExtendedLifetime(probe) {}
            XCTFail("Cancelled handler must not start")
        }
        probe = nil
        let publish = callbacks.reserve(keys: [])
        DispatchQueue.global().async { publish?(); finished.fulfill() }
        wait(for: [entered], timeout: 5)
        cancel()
        XCTAssertNil(weakProbe)
        release.signal()
        wait(for: [finished], timeout: 5)
    }

    func testClaimedHandlerCanCancelItselfAndOtherThreadDoesNotWait() {
        let callbacks = FirstFlagsCallbacks()
        var cancel: (() -> Void)?
        let cancelled = expectation(description: "other thread cancellation")
        cancel = callbacks.register { _ in
            cancel?()
            DispatchQueue.global().async { cancel?(); cancelled.fulfill() }
            self.wait(for: [cancelled], timeout: 5)
        }
        callbacks.reserve(keys: [])?()
    }

    func testOwnerDestructionReleasesPendingCaptureWithRetainedHandle() {
        var callbacks: FirstFlagsCallbacks? = FirstFlagsCallbacks()
        var probe: LifetimeProbe? = LifetimeProbe()
        weak var weakProbe = probe
        weak var weakOwner = callbacks
        let cancel = callbacks!.register { [probe] _ in withExtendedLifetime(probe) {} }
        probe = nil
        XCTAssertNotNil(weakProbe)
        callbacks = nil
        XCTAssertNil(weakOwner)
        XCTAssertNil(weakProbe)
        cancel()
        cancel()
    }

    func testCaptureDestructionReentersWithoutLocks() {
        let callbacks = FirstFlagsCallbacks()
        var probe: LifetimeProbe? = LifetimeProbe()
        probe?.onDeinit = {
            let cancel = callbacks.register { _ in }
            cancel()
        }
        let cancel = callbacks.register { [probe] _ in withExtendedLifetime(probe) {} }
        probe = nil
        cancel()
    }

    func testDeliveryReleasesCaptureWithRetainedHandle() {
        let callbacks = FirstFlagsCallbacks()
        var probe: LifetimeProbe? = LifetimeProbe()
        weak var weakProbe = probe
        let cancel = callbacks.register { [probe] _ in withExtendedLifetime(probe) {} }
        probe = nil
        callbacks.reserve(keys: [])?()
        XCTAssertNil(weakProbe)
        cancel()
    }

    func testDefaultAndFallbackDoNotRetainOrInvokeCallbacks() {
        let clients: [any FlagsClientProtocol] = [
            ExternalFlagsClient(),
            FallbackFlagsClient(name: "test", core: SingleFeatureCoreMock<FlagsFeature>())
        ]
        for client in clients {
            var probe: LifetimeProbe? = LifetimeProbe()
            weak var weakProbe = probe
            let cancel = client.onFirstFlags { [probe] _ in
                withExtendedLifetime(probe) {}
                XCTFail("No event expected")
            }
            probe = nil
            XCTAssertNil(weakProbe)
            cancel()
            cancel()
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
        let cancel = repository!.onFirstFlags { [probe] _ in withExtendedLifetime(probe) {} }
        probe = nil
        repository = nil
        XCTAssertNil(weakRepository)
        XCTAssertNil(weakProbe)
        cancel()
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

private final class LifetimeProbe {
    var onDeinit: (() -> Void)?
    deinit { onDeinit?() }
}

private final class FirstFlagsCallbackStore: DataStore {
    var readCompletion: ((DataStoreValueResult) -> Void)?
    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) { readCompletion = callback }
    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {}
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
