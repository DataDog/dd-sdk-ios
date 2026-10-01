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
        FlagsData(
            flags: Dictionary(uniqueKeysWithValues: keys.map { ($0, FlagAssignment(allocationKey: "allocation", variationKey: "variation", variation: .boolean(true), reason: "TARGETING_MATCH", doLog: false)) }),
            context: .mockAny(),
            date: .mockAny()
        )
    }

    func testOrdinaryCreationClosureCanRunBeforeFactoryReturns() throws {
        let scope = FeatureScopeMock()
        scope.dataStore.setValue(try JSONEncoder().encode(data(["cached"])), forKey: "test")
        let core = SingleFeatureCoreMock<FlagsFeature>()
        core.featureScopeOverride = scope
        Flags.enable(in: core)
        var factoryReturned = false
        var events: [FlagsClientEvent] = []

        let client = FlagsClient.create(name: "test", in: core) { callbackClient, event in
            XCTAssertFalse(factoryReturned)
            XCTAssertIdentical(callbackClient, FlagsClient.shared(named: "test", in: core))
            XCTAssertIdentical(callbackClient, FlagsClient.create(name: "test", in: core))
            XCTAssertTrue(callbackClient.getBooleanValue(key: "cached", defaultValue: false))
            XCTAssertEqual(callbackClient.state.currentState, .notReady)
            events.append(event)
        }
        factoryReturned = true

        XCTAssertEqual(events, [FlagsClientEvent(type: .configurationChanged, flagsChanged: ["cached"])])
        XCTAssertIdentical(client, FlagsClient.shared(named: "test", in: core))
        XCTAssertIdentical(client, FlagsClient.create(name: "test", in: core))
        XCTAssertIdentical(client, FlagsClient.create(name: "test", in: core, onFirstFlags: nil))
        FlagsClient.create(name: "test", in: core) { _, _ in XCTFail("Duplicate callback") }
        XCTAssertTrue(scope.eventsWritten.isEmpty)
    }

    func testDelayedCacheCallbackSuppliesRegisteredUsableClientWithoutMainQueueHandoff() throws {
        for keys in [["cached"], []] {
            let store = FirstFlagsCallbackStore()
            let scope = FeatureScopeMock(dataStore: store)
            let core = SingleFeatureCoreMock<FlagsFeature>()
            core.featureScopeOverride = scope
            Flags.enable(in: core)
            let notified = expectation(description: "Delayed cache callback")
            let client = FlagsClient.create(name: "test", in: core) { client, event in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertIdentical(client, FlagsClient.shared(named: "test", in: core))
                XCTAssertEqual(event.flagsChanged, keys)
                XCTAssertEqual(client.getBooleanValue(key: "cached", defaultValue: false), !keys.isEmpty)
                XCTAssertEqual(client.state.currentState, .notReady)
                notified.fulfill()
            }
            XCTAssertIdentical(client, FlagsClient.shared(named: "test", in: core))
            let encoded = try JSONEncoder().encode(data(keys))
            DispatchQueue.global().async {
                store.readCompletion?(.value(encoded, dataStoreDefaultKeyVersion))
            }
            waitForExpectations(timeout: 5)
        }
    }

    func testEmptyCacheNotifiesWithoutChangingReadiness() throws {
        let scope = FeatureScopeMock()
        scope.dataStore.setValue(try JSONEncoder().encode(data([])), forKey: "test")
        var events: [FlagsClientEvent] = []
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: scope,
            onFirstFlags: { events.append($0) }
        )

        XCTAssertEqual(events.map(\.flagsChanged), [[]])
        XCTAssertEqual(repository.state.currentState, .notReady)
    }

    func testMissingOrInvalidCacheAndFailedNetworkWaitForAcceptedEmptyNetwork() {
        for cached in [Data?.none, Data("invalid".utf8)] {
            let scope = FeatureScopeMock()
            if let cached { scope.dataStore.setValue(cached, forKey: "test") }
            var response: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
            var events: [FlagsClientEvent] = []
            var completionCalled = false
            let repository = FlagsRepository(
                clientName: "test",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in response = completion },
                dateProvider: DateProviderMock(),
                featureScope: scope,
                onFirstFlags: {
                    XCTAssertTrue(completionCalled)
                    events.append($0)
                }
            )
            XCTAssertTrue(events.isEmpty)
            repository.setEvaluationContext(.mockAny()) { _ in }
            response?(.failure(.invalidResponse))
            XCTAssertTrue(events.isEmpty)
            repository.setEvaluationContext(.mockAny()) { _ in completionCalled = true }
            response?(.success([:]))
            XCTAssertEqual(events.map(\.flagsChanged), [[]])
            XCTAssertEqual(repository.state.currentState, .ready)
        }
    }

    func testDelayedDiskNotifiesBeforeQueuedNetworkAndRetainsFirstKeys() throws {
        let store = FirstFlagsCallbackStore()
        var events: [FlagsClientEvent] = []
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                XCTAssertEqual(events.map(\.flagsChanged), [["disk"]])
                completion(.success(["network": .mockAny()]))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store),
            onFirstFlags: { events.append($0) }
        )
        repository.setEvaluationContext(.mockAny()) { _ in }
        XCTAssertTrue(events.isEmpty)
        store.readCompletion?(.value(try JSONEncoder().encode(data(["disk"])), dataStoreDefaultKeyVersion))

        XCTAssertEqual(events.map(\.flagsChanged), [["disk"]])
        XCTAssertEqual(repository.flagAssignments()?.keys.sorted(), ["network"])
    }

    func testCallbackCanReadAndReenterAndResetDoesNotRearm() {
        var repository: FlagsRepository?
        var calls = 0
        repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["network": .mockAny()]))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            onFirstFlags: { event in
                guard let repository else {
                    XCTFail("Repository should exist before network installation")
                    return
                }
                calls += 1
                XCTAssertEqual(event.flagsChanged, ["network"])
                XCTAssertEqual(repository.flagAssignments()?.keys.sorted(), ["network"])
                repository.reset()
                repository.setEvaluationContext(.mockAny()) { _ in }
            }
        )
        repository?.setEvaluationContext(.mockAny()) { _ in }
        repository?.reset()
        repository?.setEvaluationContext(.mockAny()) { _ in }

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(repository?.state.currentState, .ready)
    }

    func testConcurrentAcceptedNetworkInstallsNotifyOnce() {
        var responses: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        let lock = NSLock()
        var events: [FlagsClientEvent] = []
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in responses.append(completion) },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            initializationTimeout: nil,
            onFirstFlags: { event in
                lock.lock()
                events.append(event)
                lock.unlock()
            }
        )
        for _ in 0..<20 { repository.setEvaluationContext(.mockAny()) { _ in } }
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            responses[index](.success([String(index): .mockAny()]))
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.flagsChanged?.count, 1)
    }
}

private final class FirstFlagsCallbackStore: DataStore {
    var readCompletion: ((DataStoreValueResult) -> Void)?
    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) { readCompletion = callback }
    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {}
    func removeValue(forKey key: String) {}
    func clearAllData() {}
    func flush() {}
}
