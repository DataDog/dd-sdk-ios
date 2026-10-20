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
        let published = expectation(description: "disk event published")
        client.onFirstFlags { _ in published.fulfill() }
        wait(for: [published], timeout: 5)
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

    func testDiskAndNetworkWinnerKeysFollowAcceptedInstallation() throws {
        for diskFirst in [true, false] {
            let store = FirstFlagsCallbackStore()
            var response: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
            let repository = FlagsRepository(
                clientName: "test",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in response = completion },
                dateProvider: DateProviderMock(),
                featureScope: FeatureScopeMock(dataStore: store),
                initializationTimeout: nil
            )
            let delivered = expectation(description: "accepted winner delivered")
            let events = ReadWriteLock<[[String]]>(wrappedValue: [])
            _ = repository.onFirstFlags { event in
                events.mutate { $0.append(event.flagsChanged) }
                delivered.fulfill()
            }
            repository.setEvaluationContext(.mockAny()) { _ in }
            let encoded = try JSONEncoder().encode(data(["disk"]))
            if diskFirst {
                store.readCompletion?(.value(encoded, dataStoreDefaultKeyVersion))
                response?(.success(.init(flags: ["network": .mockAny()])))
            } else {
                response?(.success(.init(flags: ["network": .mockAny()])))
                store.readCompletion?(.value(encoded, dataStoreDefaultKeyVersion))
            }
            wait(for: [delivered], timeout: 5)
            XCTAssertEqual(events.wrappedValue, [[diskFirst ? "disk" : "network"]])
            XCTAssertEqual(repository.flagAssignments()?.keys.sorted(), ["network"])
            repository.reset()
            _ = repository.onFirstFlags { event in
                XCTAssertEqual(event.flagsChanged, [diskFirst ? "disk" : "network"])
            }
        }
    }

    func testObfuscatedWinnerKeysPreservePlaintextLookupAndReplay() throws {
        let metadata = Data(#"{"scheme":"flag-key-sha256-v1","salt":"000102030405060708090a0b0c0d0e0f"}"#.utf8)
        let obfuscation = try JSONDecoder().decode(FlagKeyObfuscation.self, from: metadata)
        let diskKey = obfuscation.lookupKey(for: "disk")
        let networkKey = obfuscation.lookupKey(for: "network")
        for diskFirst in [true, false] {
            let store = FirstFlagsCallbackStore()
            var response: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
            let repository = FlagsRepository(
                clientName: "test",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in response = completion },
                dateProvider: DateProviderMock(),
                featureScope: FeatureScopeMock(context: .mockWith(source: "ios"), dataStore: store),
                initializationTimeout: nil
            )
            let delivered = expectation(description: "obfuscated winner delivered")
            let events = ReadWriteLock<[[String]]>(wrappedValue: [])
            _ = repository.onFirstFlags { event in
                events.mutate { $0.append(event.flagsChanged) }
                delivered.fulfill()
            }
            repository.setEvaluationContext(.mockAny()) { _ in }
            let disk = FlagsData(flags: [diskKey: .mockAny()], context: .mockAny(), date: .mockAny(), obfuscation: obfuscation)
            let encoded = try JSONEncoder().encode(disk)
            let network = FlagAssignmentsResponse(flags: [networkKey: .mockAny()], obfuscation: obfuscation)
            if diskFirst {
                store.readCompletion?(.value(encoded, 2))
                XCTAssertEqual(repository.flagAssignment(for: "disk")?.reason, "CACHED")
                response?(.success(network))
            } else {
                response?(.success(network))
                store.readCompletion?(.value(encoded, 2))
            }
            wait(for: [delivered], timeout: 5)
            XCTAssertEqual(events.wrappedValue, [[diskFirst ? diskKey : networkKey]])
            XCTAssertNotNil(repository.flagAssignment(for: "network"))
            XCTAssertNil(repository.flagAssignments(), "Legacy inventory must not expose encoded assignments")
            repository.reset()
            _ = repository.onFirstFlags { event in
                XCTAssertEqual(event.flagsChanged, [diskFirst ? diskKey : networkKey])
            }
        }
    }

    func testDiskDoesNotWaitForAsynchronousNetworkResponse() throws {
        let store = FirstFlagsCallbackStore()
        var response: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in
                response = completion
            },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store)
        )
        let keys = ReadWriteLock<[String]?>(wrappedValue: nil)
        let delivered = expectation(description: "empty disk installation delivered")
        _ = repository.onFirstFlags {
            keys.wrappedValue = $0.flagsChanged
            delivered.fulfill()
        }
        repository.setEvaluationContext(.mockAny()) { _ in }
        store.readCompletion?(.value(try JSONEncoder().encode(data([])), dataStoreDefaultKeyVersion))
        wait(for: [delivered], timeout: 5)
        XCTAssertEqual(keys.wrappedValue, [])
        XCTAssertNotNil(response)
        response?(.success(.init(flags: ["later": .mockAny()])))
        _ = repository.onFirstFlags { XCTAssertEqual($0.flagsChanged, []) }
    }

    func testBlockedDiskHandlerDoesNotBlockStorageAndCanDrainIt() throws {
        let store = FirstFlagsCallbackStore()
        let storage = DispatchQueue(label: "test.first-flags.storage")
        let storageKey = DispatchSpecificKey<Bool>()
        storage.setSpecific(key: storageKey, value: true)
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock(),
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store)
        )
        let entered = expectation(description: "handler entered")
        let drained = expectation(description: "handler drained storage")
        let progressed = expectation(description: "storage progressed during handler")
        let finished = expectation(description: "handler finished")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        _ = repository.onFirstFlags { event in
            // Guard prevents the regression from trapping the test runner on same-queue sync.
            guard DispatchQueue.getSpecific(key: storageKey) == nil else {
                XCTFail("Disk handler must not execute on storage")
                entered.fulfill()
                finished.fulfill()
                return
            }
            XCTAssertEqual(event.flagsChanged, ["disk"])
            storage.sync { drained.fulfill() }
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            finished.fulfill()
        }
        let encoded = try JSONEncoder().encode(data(["disk"]))
        storage.async { store.readCompletion?(.value(encoded, dataStoreDefaultKeyVersion)) }
        wait(for: [entered, drained], timeout: 2)
        storage.async { progressed.fulfill() }
        wait(for: [progressed], timeout: 2)
        release.signal()
        wait(for: [finished], timeout: 2)
    }

    func testFirstFlagsDoesNotWaitForBlockedContextCompletion() throws {
        for networkSuccess in [true, false] {
            let store = FirstFlagsCallbackStore()
            var response: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
            let repository = FlagsRepository(
                clientName: "test",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in response = completion },
                dateProvider: DateProviderMock(),
                featureScope: FeatureScopeMock(dataStore: store),
                initializationTimeout: nil
            )
            let entered = expectation(description: "context completion entered")
            let finished = expectation(description: "context completion finished")
            let delivered = expectation(description: "firstFlags while completion cannot return")
            let release = DispatchSemaphore(value: 0)
            defer { release.signal() }
            _ = repository.onFirstFlags { event in
                XCTAssertEqual(event.flagsChanged, [networkSuccess ? "network" : "disk"])
                delivered.fulfill()
            }
            repository.setEvaluationContext(.mockAny()) { _ in
                entered.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                finished.fulfill()
            }
            if networkSuccess {
                let success = response!
                DispatchQueue.global().async { success(.success(.init(flags: ["network": .mockAny()]))) }
            } else {
                response?(.failure(.invalidResponse))
                store.readCompletion?(.value(try JSONEncoder().encode(data(["disk"])), dataStoreDefaultKeyVersion))
            }
            wait(for: [entered, delivered], timeout: 2)
            release.signal()
            wait(for: [finished], timeout: 2)
        }
    }

    func testFallbackOnlyCacheReservesWhenItBecomesActive() throws {
        for failureAfterActivation in [true, false] {
            let store = FirstFlagsCallbackStore()
            var responses: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
            let repository = FlagsRepository(
                clientName: "test",
                flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in responses.append(completion) },
                dateProvider: DateProviderMock(),
                featureScope: FeatureScopeMock(dataStore: store),
                initializationTimeout: nil
            )
            let delivered = expectation(description: "fallback becomes active")
            let events = ReadWriteLock<[[String]]>(wrappedValue: [])
            _ = repository.onFirstFlags { event in
                events.mutate { $0.append(event.flagsChanged) }
                delivered.fulfill()
            }
            repository.setEvaluationContext(.init(targetingKey: "different")) { _ in }
            store.readCompletion?(.value(try JSONEncoder().encode(data(["cached"])), dataStoreDefaultKeyVersion))
            XCTAssertNil(repository.flagAssignments())
            XCTAssertTrue(events.wrappedValue.isEmpty)
            // A matching request activates the fallback; a failed response must not emit again.
            repository.setEvaluationContext(.mockAny()) { _ in }
            if failureAfterActivation { responses.last?(.failure(.invalidResponse)) }
            wait(for: [delivered], timeout: 5)
            XCTAssertEqual(events.wrappedValue, [["cached"]])
            XCTAssertEqual(repository.flagAssignment(for: "cached")?.reason, "CACHED")
            responses[0](.success(.init(flags: ["obsolete": .mockAny()])))
            XCTAssertEqual(repository.flagAssignments()?.keys.sorted(), ["cached"])
            _ = repository.onFirstFlags { XCTAssertEqual($0.flagsChanged, ["cached"]) }
        }
    }

    func testFallbackOnlyDiskCannotReserveBeforeAcceptedNetwork() throws {
        let store = FirstFlagsCallbackStore()
        var response: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in response = completion },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store),
            initializationTimeout: nil
        )
        let delivered = expectation(description: "network accepted instead of mismatched fallback")
        _ = repository.onFirstFlags { event in
            XCTAssertEqual(event.flagsChanged, ["network"])
            delivered.fulfill()
        }
        repository.setEvaluationContext(.init(targetingKey: "different")) { _ in }
        store.readCompletion?(.value(try JSONEncoder().encode(data(["fallback"])), dataStoreDefaultKeyVersion))
        response?(.success(.init(flags: ["network": .mockAny()])))
        wait(for: [delivered], timeout: 5)
    }

    func testFirstFlagsDoesNotWaitForBlockedReadyListener() {
        let store = FirstFlagsCallbackStore()
        var response: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in response = completion },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store),
            initializationTimeout: nil
        )
        let entered = expectation(description: "ready listener entered")
        let finished = expectation(description: "ready listener finished")
        let delivered = expectation(description: "firstFlags independent of ready listener")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let listener = FirstFlagsStateListener { state in
            guard state == .ready else {
                return
            }
            entered.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            finished.fulfill()
        }
        repository.state.addListener(listener)
        let access = ReadWriteLock(wrappedValue: repository)
        _ = repository.onFirstFlags { event in
            XCTAssertEqual(access.wrappedValue.state.currentState, .ready)
            XCTAssertEqual(access.wrappedValue.flagAssignments()?.keys.sorted(), event.flagsChanged)
            delivered.fulfill()
        }
        repository.setEvaluationContext(.mockAny()) { _ in }
        let success = response!
        DispatchQueue.global().async { success(.success(.init(flags: ["network": .mockAny()]))) }
        wait(for: [entered, delivered], timeout: 2)
        release.signal()
        wait(for: [finished], timeout: 2)
        withExtendedLifetime(listener) {}
    }

    func testRejectedSuccessCannotReserveBeforeLatestRequest() {
        let store = FirstFlagsCallbackStore()
        var responses: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in responses.append(completion) },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(dataStore: store),
            initializationTimeout: nil
        )
        let delivered = expectation(description: "latest accepted success")
        let events = ReadWriteLock<[[String]]>(wrappedValue: [])
        _ = repository.onFirstFlags { event in
            events.mutate { $0.append(event.flagsChanged) }
            delivered.fulfill()
        }
        repository.setEvaluationContext(.init(targetingKey: "obsolete")) { _ in }
        repository.setEvaluationContext(.init(targetingKey: "latest")) { _ in }
        responses[0](.success(.init(flags: ["obsolete": .mockAny()])))
        XCTAssertTrue(events.wrappedValue.isEmpty)
        responses[1](.success(.init(flags: ["latest": .mockAny()])))
        wait(for: [delivered], timeout: 5)
        XCTAssertEqual(events.wrappedValue, [["latest"]])
        XCTAssertEqual(repository.flagAssignments()?.keys.sorted(), ["latest"])
    }

    func testMissingInvalidAndFailedLoadsWaitForSuccessfulEmptyNetwork() {
        for cached in [Data?.none, Data("invalid".utf8)] {
            let scope = FeatureScopeMock()
            if let cached { scope.dataStore.setValue(cached, forKey: "test") }
            var response: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
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
            let delivered = expectation(description: "network event delivered")
            _ = repository.onFirstFlags { event in
                events.mutate { $0.append(event) }
                delivered.fulfill()
            }
            repository.setEvaluationContext(.mockAny()) { _ in }
            response?(.failure(.invalidResponse))
            XCTAssertTrue(events.wrappedValue.isEmpty)
            repository.setEvaluationContext(.mockAny()) { result in
                if case .failure(let error) = result { XCTFail("Unexpected failure: \(error)") }
            }
            response?(.success(.init(flags: [:])))
            wait(for: [delivered], timeout: 5)
            XCTAssertEqual(events.wrappedValue.map(\.flagsChanged), [[]])
        }
    }

    func testNetworkCallbackCanResetAndRegisterFromAnotherThreadWithoutTrailingWrites() {
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in completion(.success(.init(flags: ["network": .mockAny()]))) },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            initializationTimeout: nil
        )
        let repositoryAccess = ReadWriteLock(wrappedValue: repository)
        let delivered = expectation(description: "network handler completed")
        _ = repositoryAccess.wrappedValue.onFirstFlags { _ in
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
            delivered.fulfill()
        }
        repository.setEvaluationContext(.mockAny()) { result in
            if case .failure(let error) = result { XCTFail("Unexpected failure: \(error)") }
        }
        wait(for: [delivered], timeout: 5)
        XCTAssertEqual(repository.state.currentState, .notReady)
        XCTAssertNil(repository.flagAssignments())
        _ = repository.onFirstFlags { XCTAssertEqual($0.flagsChanged, ["network"]) }
    }

    func testTimeoutAndResetDoNotCompleteOrCancelFirstFlags() {
        var timeout: (() -> Void)?
        var response: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in response = completion },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            initializationTimeout: 1,
            scheduleInitializationTimeout: { _, action in timeout = action; return {} }
        )
        let calls = ReadWriteLock(wrappedValue: 0)
        let delivered = expectation(description: "network event after timeout")
        _ = repository.onFirstFlags { _ in
            calls.mutate { $0 += 1 }
            delivered.fulfill()
        }
        repository.setEvaluationContext(.mockAny()) { _ in }
        timeout?()
        repository.reset()
        XCTAssertEqual(calls.wrappedValue, 0)
        response?(.success(.init(flags: ["obsolete": .mockAny()])))
        XCTAssertEqual(calls.wrappedValue, 0)
        repository.setEvaluationContext(.mockAny()) { _ in }
        response?(.success(.init(flags: [:])))
        wait(for: [delivered], timeout: 5)
        XCTAssertEqual(calls.wrappedValue, 1)
    }

    func testFailedUpdatesPreserveFirstEventWithoutReplayIO() {
        for error in [FlagsError.invalidResponse, .networkError(NSError(domain: "test", code: 1))] {
            for sameContext in [false, true] {
                let store = FirstFlagsCallbackStore()
                var response: ((Result<FlagAssignmentsResponse, FlagsError>) -> Void)?
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
                let delivered = expectation(description: "first network installation")
                _ = repository.onFirstFlags { event in
                    events.mutate { $0.append(event) }
                    delivered.fulfill()
                }
                XCTAssertTrue(events.wrappedValue.isEmpty)
                let context = FlagsEvaluationContext(targetingKey: "first")
                repository.setEvaluationContext(context) { result in
                    if case .failure(let error) = result { XCTFail("Unexpected failure: \(error)") }
                }
                response?(.success(.init(flags: ["first": .mockAny()])))
                wait(for: [delivered], timeout: 5)
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
                repository.flush()
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
        var responses: [(Result<FlagAssignmentsResponse, FlagsError>) -> Void] = []
        let repository = FlagsRepository(
            clientName: "test",
            flagAssignmentsFetcher: FlagAssignmentsFetcherMock { _, completion in responses.append(completion) },
            dateProvider: DateProviderMock(),
            featureScope: FeatureScopeMock(),
            initializationTimeout: nil
        )
        let delivered = expectation(description: "winning installation published")
        let events = ReadWriteLock<[FlagsClientEvent]>(wrappedValue: [])
        _ = repository.onFirstFlags { event in
            events.mutate { $0.append(event) }
            delivered.fulfill()
        }
        for _ in 0..<20 { repository.setEvaluationContext(.mockAny()) { _ in } }
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            responses[index](.success(.init(flags: [String(index): .mockAny()])))
        }
        wait(for: [delivered], timeout: 5)
        XCTAssertEqual(events.wrappedValue.count, 1)
        _ = repository.onFirstFlags { XCTAssertEqual($0.flagsChanged, events.wrappedValue.first?.flagsChanged) }
    }

    func testConcurrentInstallAndRegistrationRetainOneEvent() {
        let callbacks = ReadWriteLock(wrappedValue: FirstFlagsCallbacks())
        let values = ReadWriteLock<[[String]]>(wrappedValue: [])
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

    func testConcurrentCancellationAndPublicationClaimsAtMostOnce() {
        for _ in 0..<100 {
            let callbacks = ReadWriteLock(wrappedValue: FirstFlagsCallbacks())
            let calls = ReadWriteLock(wrappedValue: 0)
            let subscription = callbacks.wrappedValue.register { _ in calls.mutate { $0 += 1 } }
            let publish = callbacks.wrappedValue.reserve(keys: ["flag"])
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 { subscription.cancel() } else { publish?() }
            }
            XCTAssertTrue((0...1).contains(calls.wrappedValue))
            let settled = calls.wrappedValue
            subscription.cancel()
            publish?()
            XCTAssertEqual(calls.wrappedValue, settled)
            let replayed = ReadWriteLock(wrappedValue: false)
            _ = callbacks.wrappedValue.register { _ in replayed.wrappedValue = true }
            XCTAssertTrue(replayed.wrappedValue)
        }
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

    func testFallbackCompletesEachRegistrationImmediatelyWithoutRetainingCaptures() {
        let client = FallbackFlagsClient(name: "test", core: SingleFeatureCoreMock<FlagsFeature>())
        let calls = ReadWriteLock(wrappedValue: 0)
        for index in 1...3 {
            var probe: LifetimeProbe? = LifetimeProbe()
            weak var weakProbe = probe
            let returned = ReadWriteLock(wrappedValue: false)
            let subscription = client.onFirstFlags { [probe] event in
                XCTAssertFalse(returned.wrappedValue)
                XCTAssertEqual(event.type, .configurationChanged)
                XCTAssertEqual(event.type.rawValue, "CONFIGURATION_CHANGED")
                XCTAssertEqual(event.flagsChanged, [])
                withExtendedLifetime(probe) {}
                calls.mutate { $0 += 1 }
            }
            returned.wrappedValue = true
            XCTAssertEqual(calls.wrappedValue, index)
            probe = nil
            XCTAssertNil(weakProbe)
            subscription.cancel()
            subscription.cancel()
            XCTAssertEqual(calls.wrappedValue, index)
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

    func testCompatibilityDefaultDoesNotDeliverOrRetainCaptures() {
        let client: any FlagsClientProtocol = CompatibilityFlagsClient()
        var probe: LifetimeProbe? = LifetimeProbe()
        weak var weakProbe = probe
        let subscription = client.onFirstFlags { [probe] _ in
            withExtendedLifetime(probe) {}
            XCTFail("Compatibility default must never deliver an event")
        }
        probe = nil
        XCTAssertNil(weakProbe, "The default must not retain the listener even while its token is retained")
        DispatchQueue.concurrentPerform(iterations: 100) { _ in subscription.cancel() }
        subscription.cancel()
        withExtendedLifetime(client) {}
    }

    func testEventValueSemanticsPreserveEmptyAndInputOrder() {
        var keys = ["b", "a", "b"]
        let event = FlagsClientEvent(type: .configurationChanged, flagsChanged: keys)
        keys.removeAll()
        XCTAssertEqual(event.flagsChanged, ["b", "a", "b"])
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

private final class FirstFlagsStateListener: FlagsStateListener {
    private let callback: (FlagsClientState) -> Void
    init(_ callback: @escaping (FlagsClientState) -> Void) { self.callback = callback }
    func flagsStateDidChange(_ newState: FlagsClientState) { callback(newState) }
}

/// Intentionally omits onFirstFlags to exercise the public compatibility default through the protocol.
private final class CompatibilityFlagsClient: FlagsClientProtocol {
    func setEvaluationContext(_ context: FlagsEvaluationContext, completion: @escaping (Result<Void, FlagsError>) -> Void) {
        completion(.success(()))
    }

    func getDetails<T>(key: String, defaultValue: T) -> FlagDetails<T> where T: Equatable, T: FlagValue {
        FlagDetails(key: key, value: defaultValue)
    }
}
