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

#if !os(watchOS)
@testable import Example
@testable import DatadogLogs
#endif

/// Covers integration scenarios for flag evaluation logging.
final class FlagsEvaluationIntegrationTests: XCTestCase {
    private enum Fixtures {
        static let flagsData = FlagsData(
            flags: [
                "test-flag": .init(
                    allocationKey: "allocation-123",
                    variationKey: "variation-123",
                    variation: .boolean(true),
                    reason: "TARGETING_MATCH",
                    doLog: true
                )
            ],
            context: .init(
                targetingKey: "user-123",
                attributes: [:]
            ),
            date: .mockAny()
        )
    }

    // MARK: - EVALLOG.4: Shutdown Flush

    /// EVALLOG.4: Evaluations are flushed when SDK shuts down via flushAndTearDown()
    func testGivenPendingEvaluations_whenSDKShutsDown_itFlushes() throws {
        // Given
        let core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
        Flags.enable(with: .init(trackEvaluations: true), in: core)

        let featureScope = core.scope(for: FlagsFeature.self)
        featureScope.flagsDataStore.setFlagsData(Fixtures.flagsData, forClientNamed: FlagsClient.defaultName)
        featureScope.dataStore.flush()

        let client = FlagsClient.create(in: core)

        // When
        _ = client.getBooleanValue(key: "test-flag", defaultValue: false)

        // Then
        try core.flushAndTearDown()

        let events = core.waitAndReturnEvents(
            ofFeature: FlagsEvaluationFeature.name,
            ofType: FlagEvaluationEvent.self
        )

        XCTAssertEqual(events.count, 1, "Should have flushed pending evaluations on shutdown")
        XCTAssertEqual(events.first?.flag.key, "test-flag")
    }

    func testNetworkFirstConfigurationDecodesPersistsAndNotifiesOnlyOnceAcrossReset() throws {
        let core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
        defer { try? core.flushAndTearDown() }
        Flags.enable(in: core)
        let scope = core.scope(for: FlagsFeature.self)
        let response = try JSONEncoder().encode(FlagAssignmentsResponse(flags: Fixtures.flagsData.flags))
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: scope,
            fetch: { request, completion in
                XCTAssertEqual(request.httpMethod, "POST")
                completion(.success(response))
            }
        )
        let first = expectation(description: "First decoded network configuration")
        var events: [FlagsClientEvent] = []
        var completionCalled = false
        var repository: FlagsRepository?
        repository = FlagsRepository(
            clientName: FlagsClient.defaultName,
            flagAssignmentsFetcher: fetcher,
            dateProvider: SystemDateProvider(),
            featureScope: scope,
            onFirstFlags: { event in
                XCTAssertTrue(completionCalled)
                XCTAssertEqual(repository?.state.currentState, .ready)
                XCTAssertEqual(repository?.flagAssignments()?.keys.sorted(), ["test-flag"])
                events.append(event)
                first.fulfill()
            }
        )
        scope.dataStore.flush()
        XCTAssertTrue(events.isEmpty)
        repository?.setEvaluationContext(Fixtures.flagsData.context) { result in
            if case .failure = result { XCTFail("Expected successful configuration") }
            completionCalled = true
        }
        waitForExpectations(timeout: 5)
        XCTAssertEqual(events, [FlagsClientEvent(type: .configurationChanged, flagsChanged: ["test-flag"])])
        scope.dataStore.flush()

        // A new public client reads the configuration written by the real repository/data store.
        let restored = expectation(description: "Persisted configuration")
        let client = FlagsClient.create(in: core) { event in
            XCTAssertEqual(event.flagsChanged, ["test-flag"])
            restored.fulfill()
        }
        waitForExpectations(timeout: 5)
        XCTAssertTrue(client.getBooleanValue(key: "test-flag", defaultValue: false))
        repository?.reset()
        let refreshed = expectation(description: "Refresh after reset")
        repository?.setEvaluationContext(Fixtures.flagsData.context) { result in
            if case .failure = result { XCTFail("Expected successful configuration") }
            refreshed.fulfill()
        }
        waitForExpectations(timeout: 5)
        XCTAssertEqual(events.count, 1)
    }

    #if !os(watchOS)
    func testExampleFlagKeyRequiresExplicitNonblankOptIn() {
        XCTAssertNil(Environment.readFlagKey(from: [:]))
        XCTAssertNil(Environment.readFlagKey(from: ["DD_FLAG_KEY": ""]))
        XCTAssertNil(Environment.readFlagKey(from: ["DD_FLAG_KEY": " \n\t"]))
        XCTAssertEqual(Environment.readFlagKey(from: ["DD_FLAG_KEY": " test-flag "]), "test-flag")
    }

    func testFirstCachedFlagsHandsOffRegisteredClientToExampleAndLogsOneEvaluation() throws {
        let core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
        defer { try? core.flushAndTearDown() }
        Flags.enable(with: .init(trackEvaluations: true), in: core)
        Logs.enable(in: core)
        let logger = Logger.create(in: core)
        let scope = core.scope(for: FlagsFeature.self)
        scope.flagsDataStore.setFlagsData(Fixtures.flagsData, forClientNamed: FlagsClient.defaultName)
        scope.dataStore.flush()
        let delivered = expectation(description: "Application handoff")
        var createdClient: FlagsClientProtocol?

        createdClient = FlagsClient.create(in: core) { event in
            DispatchQueue.main.async {
                let registeredClient = FlagsClient.shared(in: core)
                XCTAssertIdentical(registeredClient, createdClient)
                XCTAssertEqual(event.type, .configurationChanged)
                XCTAssertEqual(event.flagsChanged, ["test-flag"])
                XCTAssertEqual(registeredClient.state.currentState, .notReady)
                XCTAssertTrue(core.waitAndReturnEvents(ofFeature: FlagsFeature.name, ofType: ExposureEvent.self).isEmpty)
                ExampleAppDelegate.logFirstFlags(event, flagKey: "test-flag", client: registeredClient, logger: logger)
                delivered.fulfill()
            }
        }
        waitForExpectations(timeout: 5)
        core.flush()

        let messages = core.waitAndReturnEvents(ofFeature: LogsFeature.name, ofType: LogEvent.self).map(\.message)
        XCTAssertEqual(messages, ["First flags keys: [\"test-flag\"]", "First flags: test-flag = true"])
        XCTAssertEqual(core.waitAndReturnEvents(ofFeature: FlagsFeature.name, ofType: ExposureEvent.self).count, 1)
        try core.flushAndTearDown()
        let evaluations = core.waitAndReturnEvents(ofFeature: FlagsEvaluationFeature.name, ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(evaluations.count, 1)
        XCTAssertEqual(evaluations.first?.flag.key, "test-flag")
    }

    func testEmptyCachedFlagsReachExampleAsEmptyKeysAndUseFallback() throws {
        let core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
        defer { try? core.flushAndTearDown() }
        Flags.enable(in: core)
        Logs.enable(in: core)
        let logger = Logger.create(in: core)
        let scope = core.scope(for: FlagsFeature.self)
        scope.flagsDataStore.setFlagsData(
            FlagsData(flags: [:], context: Fixtures.flagsData.context, date: Fixtures.flagsData.date),
            forClientNamed: FlagsClient.defaultName
        )
        scope.dataStore.flush()
        let delivered = expectation(description: "Empty cache handoff")
        FlagsClient.create(in: core) { event in
            DispatchQueue.main.async {
                XCTAssertEqual(event.flagsChanged, [])
                ExampleAppDelegate.logFirstFlags(event, flagKey: "missing", client: FlagsClient.shared(in: core), logger: logger)
                delivered.fulfill()
            }
        }
        waitForExpectations(timeout: 5)
        core.flush()
        let messages = core.waitAndReturnEvents(ofFeature: LogsFeature.name, ofType: LogEvent.self).map(\.message)
        XCTAssertEqual(messages, ["First flags keys: []", "First flags: missing could not be evaluated; using false."])
    }
    #endif
}
