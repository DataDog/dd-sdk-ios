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

final class FirstFlagsTests: XCTestCase {
    private func data(_ keys: [String], context: String = "first") -> FlagsData {
        FlagsData(
            flags: Dictionary(uniqueKeysWithValues: keys.map { ($0, FlagAssignment.mockAny()) }),
            context: FlagsEvaluationContext(targetingKey: context),
            date: .mockAny()
        )
    }

    private func client(_ repository: FlagsRepository) -> FlagsClient {
        FlagsClient(
            repository: repository,
            exposureLogger: ExposureLoggerMock(),
            evaluationLogger: EvaluationLoggerMock(),
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )
    }

    func testSynchronousCacheWaitsForClientAndPreservesFirstSnapshot() throws {
        let scope = FeatureScopeMock()
        try scope.dataStore.setValue(JSONEncoder().encode(data(["z", "a"])), forKey: "test")
        var deliveries: [() -> Void] = []
        var events: [FlagsClientEvent] = []
        var snapshots: [FlagsData] = []
        let notification = FirstFlagsNotification(callback: { _, event, snapshot in
            events.append(event)
            snapshots.append(snapshot)
        }, schedule: { deliveries.append($0) })
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["network": .mockAny()]))
            },
            dateProvider: DateProviderMock(),
            featureScope: scope,
            firstFlags: notification
        )
        XCTAssertTrue(deliveries.isEmpty)
        let client = client(repository)
        notification.activate(client: client)
        XCTAssertEqual(deliveries.count, 1)
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "second")) { _ in }
        deliveries[0]()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .configurationChanged)
        XCTAssertEqual(events[0].providerName, "Datadog")
        XCTAssertEqual(events[0].flagsChanged, ["a", "z"])
        XCTAssertNil(events[0].errorCode)
        XCTAssertNil(events[0].message)
        XCTAssertTrue(events[0].metadata.isEmpty)
        XCTAssertEqual(snapshots[0], data(["z", "a"]))
        XCTAssertEqual(repository.context?.targetingKey, "second")
        XCTAssertTrue(scope.eventsWritten.isEmpty)
    }

    func testEmptyCacheIsAnInstallation() throws {
        let scope = FeatureScopeMock()
        try scope.dataStore.setValue(JSONEncoder().encode(data([])), forKey: "test")
        var events: [FlagsClientEvent] = []
        let notification = FirstFlagsNotification(callback: { _, event, _ in events.append(event) }, schedule: { $0() })
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: scope,
            firstFlags: notification
        )
        let client = client(repository)
        notification.activate(client: client)
        XCTAssertEqual(events.map(\.flagsChanged), [[]])
        XCTAssertEqual(repository.state.currentState, .notReady)
    }

    func testMissingAndInvalidCacheWaitForNetworkIncludingEmptyNetwork() throws {
        for cached in [Data?.none, Data("invalid".utf8)] {
            let scope = FeatureScopeMock()
            if let cached { scope.dataStore.setValue(cached, forKey: "test") }
            var events: [FlagsClientEvent] = []
            let notification = FirstFlagsNotification(callback: { _, event, _ in events.append(event) }, schedule: { $0() })
            let repository = FlagsRepository(
                clientName: "test",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                    completion(.success([:]))
                },
                dateProvider: DateProviderMock(),
                featureScope: scope,
                firstFlags: notification
            )
            let client = client(repository)
            notification.activate(client: client)
            XCTAssertTrue(events.isEmpty)
            repository.setEvaluationContext(.mockAny()) { _ in }
            XCTAssertEqual(events.map(\.flagsChanged), [[]])
        }
    }

    func testObsoleteNetworkSuccessCannotInstallOrClaim() {
        var completions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        var events: [FlagsClientEvent] = []
        let notification = FirstFlagsNotification(callback: { _, event, _ in events.append(event) }, schedule: { $0() })
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completions.append(completion)
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            firstFlags: notification
        )
        let client = client(repository)
        notification.activate(client: client)
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "old")) { _ in }
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "new")) { _ in }
        completions[0](.success(["obsolete": .mockAny()]))
        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(repository.flagAssignments())
        completions[1](.success(["accepted": .mockAny()]))
        completions[0](.success(["obsolete": .mockAny()]))
        XCTAssertEqual(events.map(\.flagsChanged), [["accepted"]])
        XCTAssertEqual(repository.context?.targetingKey, "new")
    }

    func testResetRejectsPendingDiskAndNetworkAndDoesNotRearm() throws {
        let store = FirstFlagsControlledStore()
        var completions: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        var events: [FlagsClientEvent] = []
        let notification = FirstFlagsNotification(callback: { _, event, _ in events.append(event) }, schedule: { $0() })
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completions.append(completion)
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store),
            firstFlags: notification
        )
        let client = client(repository)
        notification.activate(client: client)
        repository.reset()
        store.readCompletion?(.value(try JSONEncoder().encode(data(["rejected"])), dataStoreDefaultKeyVersion))
        XCTAssertTrue(events.isEmpty)
        repository.setEvaluationContext(.mockAny()) { _ in }
        repository.reset()
        completions[0](.success(["rejected-network": .mockAny()]))
        XCTAssertTrue(events.isEmpty)
        repository.setEvaluationContext(.mockAny()) { _ in }
        completions[1](.success(["accepted": .mockAny()]))
        repository.reset()
        repository.setEvaluationContext(.mockAny()) { _ in }
        completions[2](.success(["later": .mockAny()]))
        XCTAssertEqual(events.map(\.flagsChanged), [["accepted"]])
    }

    func testCallbackCanReadReenterAndThrowWithoutBreakingCompletion() {
        enum CallbackError: Error { case expected }
        var calls = 0
        var completions = 0
        let notification = FirstFlagsNotification(callback: { client, _, _ in
            calls += 1
            XCTAssertTrue(client.getBooleanValue(key: "flag", defaultValue: false))
            client.setEvaluationContext(.mockAny()) { _ in completions += 1 }
            throw CallbackError.expected
        }, schedule: { $0() })
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success([
                    "flag": FlagAssignment(
                        allocationKey: "a",
                        variationKey: "v",
                        variation: .boolean(true),
                        reason: "TARGETING_MATCH",
                        doLog: false
                    )
                ]))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            firstFlags: notification
        )
        let client = client(repository)
        notification.activate(client: client)
        repository.setEvaluationContext(.mockAny()) { _ in completions += 1 }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(completions, 2)
    }

    func testPendingDeliveryDoesNotRetainReleasedClient() {
        var deliveries: [() -> Void] = []
        let notification = FirstFlagsNotification(
            callback: { _, _, _ in XCTFail("Released client") },
            schedule: { deliveries.append($0) }
        )
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            firstFlags: notification
        )
        var client: FlagsClient? = client(repository)
        weak var weakClient = client
        notification.activate(client: client!)
        notification.claim(data: data(["first"]))
        notification.installed()
        client = nil
        XCTAssertNil(weakClient)
        XCTAssertEqual(deliveries.count, 1)
        deliveries[0]()
    }

    func testPublicFactoryRegistersBeforeCallbackAndIgnoresDuplicateHook() throws {
        let scope = FeatureScopeMock()
        let cached = data(["cached"])
        scope.dataStore.setValue(try JSONEncoder().encode(cached), forKey: "test")
        let core = SingleFeatureCoreMock<FlagsFeature>()
        core.featureScopeOverride = scope
        Flags.enable(in: core)
        let called = expectation(description: "first flags")
        let client = FlagsClient.create(name: "test", in: core, onFirstFlags: { client, event in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertIdentical(client, FlagsClient.shared(named: "test", in: core))
            XCTAssertEqual(event.flagsChanged, ["cached"])
            XCTAssertEqual(client.snapshot()?.assignments.keys.sorted(), ["cached"])
            called.fulfill()
        })
        let duplicate = FlagsClient.create(name: "test", in: core, onFirstFlags: { _, _ in
            XCTFail("Duplicate construction must not register another hook")
        })
        XCTAssertIdentical(client, duplicate)
        waitForExpectations(timeout: 5)
    }

    func testInternalFactoryProvidesMatchingFirstSnapshot() throws {
        let scope = FeatureScopeMock()
        let cached = data(["cached"], context: "cached-user")
        scope.dataStore.setValue(try JSONEncoder().encode(cached), forKey: "test")
        let core = SingleFeatureCoreMock<FlagsFeature>()
        core.featureScopeOverride = scope
        Flags.enable(in: core)
        let called = expectation(description: "snapshot")
        FlagsClient.create(name: "test", in: core, onFirstFlagsSnapshot: { client, context, flags in
            XCTAssertIdentical(client, FlagsClient.shared(named: "test", in: core))
            XCTAssertEqual(context, cached.context)
            XCTAssertEqual(flags, cached.flags)
            called.fulfill()
        })
        waitForExpectations(timeout: 5)
    }

    func testTimeoutAndFirstInstallationAreIndependent() {
        for timeoutFirst in [true, false] {
            var timeout: (() -> Void)?
            var response: ((Result<[String: FlagAssignment], FlagsError>) -> Void)?
            var deliveries: [() -> Void] = []
            var events: [FlagsClientEvent] = []
            var completions = 0
            let notification = FirstFlagsNotification(
                callback: { _, event, _ in events.append(event) },
                schedule: { deliveries.append($0) }
            )
            let repository = FlagsRepository(
                clientName: "test",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in response = completion },
                dateProvider: DateProviderMock(),
                featureScope: FeatureScopeMock(),
                firstFlags: notification,
                scheduleInitializationTimeout: { _, action in
                    timeout = action
                    return {}
                }
            )
            let client = client(repository)
            notification.activate(client: client)
            repository.setEvaluationContext(.mockAny()) { _ in completions += 1 }
            if timeoutFirst { timeout?() }
            response?(.success(["first": .mockAny()]))
            if !timeoutFirst { timeout?() }
            XCTAssertEqual(completions, 1)
            XCTAssertEqual(deliveries.count, 1)
            deliveries[0]()
            XCTAssertEqual(events.map(\.flagsChanged), [["first"]])
            XCTAssertEqual(repository.state.currentState, .ready)
        }
    }

    func testTimeoutReentrantContextRejectsOldInstallation() {
        var timeout: (() -> Void)?
        var responses: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        var events: [FlagsClientEvent] = []
        let notification = FirstFlagsNotification(callback: { _, event, _ in events.append(event) }, schedule: { $0() })
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in responses.append(completion) },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            firstFlags: notification,
            scheduleInitializationTimeout: { _, action in
                timeout = action
                return {}
            }
        )
        let client = client(repository)
        notification.activate(client: client)
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "old")) { _ in
            repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "new")) { _ in }
        }
        timeout?()
        responses[0](.success(["old": .mockAny()]))
        XCTAssertTrue(events.isEmpty)
        responses[1](.success(["new": .mockAny()]))
        XCTAssertEqual(events.map(\.flagsChanged), [["new"]])
        XCTAssertEqual(repository.context?.targetingKey, "new")
    }

    func testOlderSuccessDoesNotReplaceNewContext() {
        var responses: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in responses.append(completion) },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock()
        )
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "old")) { _ in }
        repository.setEvaluationContext(FlagsEvaluationContext(targetingKey: "new")) { _ in }
        responses[1](.success(["new": .mockAny()]))
        responses[0](.success(["old": .mockAny()]))
        XCTAssertEqual(repository.context?.targetingKey, "new")
        XCTAssertEqual(repository.flagAssignments()?.keys.sorted(), ["new"])
    }

    func testDelayedDiskInstallsBeforeQueuedNetworkWithoutWaitingForCompletion() throws {
        let store = FirstFlagsControlledStore()
        var deliveries: [() -> Void] = []
        var events: [FlagsClientEvent] = []
        let notification = FirstFlagsNotification(
            callback: { _, event, _ in events.append(event) },
            schedule: { deliveries.append($0) }
        )
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                completion(.success(["network": .mockAny()]))
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store),
            firstFlags: notification
        )
        let client = client(repository)
        notification.activate(client: client)
        repository.setEvaluationContext(.mockAny()) { _ in
            // Disk delivery is already available even while the network completion is on the stack.
            XCTAssertEqual(deliveries.count, 1)
            deliveries[0]()
            XCTAssertEqual(events.map(\.flagsChanged), [["disk"]])
        }
        XCTAssertTrue(deliveries.isEmpty)
        store.readCompletion?(.value(try JSONEncoder().encode(data(["disk"])), dataStoreDefaultKeyVersion))
        XCTAssertEqual(events.map(\.flagsChanged), [["disk"]])
        XCTAssertEqual(repository.flagAssignments()?.keys.sorted(), ["network"])
    }

    func testResetRejectsLateDiskInstallation() throws {
        let store = FirstFlagsControlledStore()
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store)
        )
        repository.reset()
        store.readCompletion?(.value(try JSONEncoder().encode(data(["old"])), dataStoreDefaultKeyVersion))
        XCTAssertNil(repository.flagAssignments())
        XCTAssertNil(repository.context)
    }

    func testConcurrentInstallClaimsScheduleOnce() {
        var deliveries: [() -> Void] = []
        var events: [FlagsClientEvent] = []
        let notification = FirstFlagsNotification(
            callback: { _, event, _ in events.append(event) },
            schedule: { deliveries.append($0) }
        )
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            firstFlags: notification
        )
        let client = client(repository)
        notification.activate(client: client)
        DispatchQueue.concurrentPerform(iterations: 50) { index in
            notification.claim(data: data([String(index)]))
            notification.installed()
        }
        XCTAssertEqual(deliveries.count, 1)
        deliveries[0]()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].flagsChanged?.count, 1)
    }
}

private final class FirstFlagsControlledStore: DataStore {
    var readCompletion: ((DataStoreValueResult) -> Void)?
    func value(forKey key: String, callback: @escaping (DataStoreValueResult) -> Void) { readCompletion = callback }
    func setValue(_ value: Data, forKey key: String, version: DataStoreKeyVersion) {}
    func removeValue(forKey key: String) {}
    func clearAllData() {}
    func flush() {}
}
