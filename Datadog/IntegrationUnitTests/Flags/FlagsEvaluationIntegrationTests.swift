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

    func testFirstFlagsFromPersistentStoreLogsOnlyExplicitEvaluation() throws {
        let core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
        defer { try? core.flushAndTearDown() }
        Flags.enable(with: .init(trackEvaluations: true), in: core)
        let scope = core.scope(for: FlagsFeature.self)
        scope.flagsDataStore.setFlagsData(Fixtures.flagsData, forClientNamed: FlagsClient.defaultName)
        scope.dataStore.flush()
        let client = FlagsClient.create(in: core)
        let delivered = expectation(description: "first flags")
        client.onFirstFlags { [weak client] event in
            XCTAssertEqual(event.flagsChanged, ["test-flag"])
            XCTAssertEqual(client?.getBooleanDetails(key: "test-flag", defaultValue: false).value, true)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 5)
        client.onFirstFlags { XCTAssertEqual($0.flagsChanged, ["test-flag"]) }
        try core.flushAndTearDown()
        let events = core.waitAndReturnEvents(ofFeature: FlagsEvaluationFeature.name, ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.evaluationCount, 1)
        XCTAssertEqual(events.first?.flag.key, "test-flag")
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
}
