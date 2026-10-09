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
@testable import DatadogRUM

/// Covers integration scenarios between Flags and RUM features.
final class FlagsRUMIntegrationTests: XCTestCase {
    private enum Fixtures {
        static let flagsData = FlagsData(
            flags: [
                "string-flag": .init(
                    allocationKey: "allocation-123",
                    variationKey: "variation-123",
                    variation: .string("red"),
                    reason: "TARGETING_MATCH",
                    doLog: true
                ),
                "boolean-flag": .init(
                    allocationKey: "allocation-124",
                    variationKey: "variation-124",
                    variation: .boolean(true),
                    reason: "TARGETING_MATCH",
                    doLog: true
                )
            ],
            context: .init(
                targetingKey: "user-123",
                attributes: ["foo": .string("bar")]
            ),
            date: .mockAny()
        )
    }

    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()

        core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))

        RUM.enable(with: .init(applicationID: "test-app-id"), in: core)
        Flags.enable(in: core)

        let featureScope = core.scope(for: FlagsFeature.self)
        featureScope.flagsDataStore.setFlagsData(Fixtures.flagsData, forClientNamed: FlagsClient.defaultName)
        featureScope.dataStore.flush()
    }

    override func tearDownWithError() throws {
        let featureScope = core.scope(for: FlagsFeature.self)
        featureScope.dataStore.clearAllData()

        try core.flushAndTearDown()
        core = nil

        super.tearDown()
    }

    func testFirstFlagsOnlyTracksTheFlagExplicitlyEvaluatedByTheHandler() throws {
        let core = self.core!
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "first-flags", name: "First Flags")
        let client = FlagsClient.create(in: core)
        let delivered = expectation(description: "first flags")
        client.onFirstFlags { event in
            XCTAssertEqual(event.flagsChanged?.sorted(), ["boolean-flag", "string-flag"])
            XCTAssertEqual(FlagsClient.shared(in: core).getBooleanValue(key: "boolean-flag", defaultValue: false), true)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 5)
        client.onFirstFlags { _ in }
        core.flush()
        monitor.stopView(key: "first-flags")
        let session = try XCTUnwrap(RUMSessionMatcher.groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers()).first)
        let view = try XCTUnwrap(session.views.first { $0.name == "First Flags" })
        let flags = try XCTUnwrap(view.latestViewEvent?.featureFlags?.featureFlagsInfo)
        XCTAssertEqual(flags.count, 1)
        XCTAssertNotNil(flags["boolean-flag"])
        XCTAssertNil(flags["string-flag"])
    }

    func testWhenFlagIsEvaluated_itAddsFeatureFlagToRUMView() throws {
        // Given
        let monitor = RUMMonitor.shared(in: core)
        let client = FlagsClient.create(in: core)

        // When
        monitor.startView(key: "test-view", name: "Test View")

        let featureScope = core.scope(for: FlagsFeature.self)
        featureScope.dataStore.flush()

        let boolValue = client.getBooleanValue(key: "boolean-flag", defaultValue: false)
        let stringValue = client.getStringValue(key: "string-flag", defaultValue: "blue")

        core.flush()

        monitor.stopView(key: "test-view")

        // Then
        let session = try XCTUnwrap(
            RUMSessionMatcher.groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers()).first
        )
        let view = try XCTUnwrap(session.views.first { $0.name == "Test View" })
        let featureFlags = try XCTUnwrap(
            view.latestViewEvent?.featureFlags?.featureFlagsInfo,
            "View should have feature flags"
        )

        XCTAssertEqual(featureFlags.count, 2)
        XCTAssertEqual((featureFlags["boolean-flag"] as? AnyCodable)?.value as? String, "variation-124")
        XCTAssertEqual((featureFlags["string-flag"] as? AnyCodable)?.value as? String, "variation-123")
    }
}
