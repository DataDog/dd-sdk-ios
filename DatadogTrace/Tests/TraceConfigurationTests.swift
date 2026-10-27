/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogTrace

class TraceConfigurationTests: XCTestCase {
    func testDefaultConfiguration() {
        // When
        let config = Trace.Configuration()

        // Then
        XCTAssertEqual(config.sampleRate, 100)
        XCTAssertNil(config.service)
        XCTAssertNil(config.tags)
        XCTAssertNil(config.urlSessionTracking)
        XCTAssertTrue(config.bundleWithRumEnabled)
        XCTAssertFalse(config.networkInfoEnabled)
        XCTAssertNil(config.eventMapper)
        XCTAssertNil(config.customEndpoint)
        XCTAssertNil(config.customStatsEndpoint)
        XCTAssertFalse(config.featureFlags[.clientSideStats])
    }

    func testFeatureFlagsSubscriptFallsBackToDefaults() {
        // When
        let emptyFlags: Trace.Configuration.FeatureFlags = [:]
        let overriddenFlags: Trace.Configuration.FeatureFlags = [.clientSideStats: true]

        // Then
        XCTAssertFalse(emptyFlags[.clientSideStats], "should fall back to `.defaults` when not set")
        XCTAssertTrue(overriddenFlags[.clientSideStats], "should use the explicitly set value")
    }

    func testCustomStatsEndpointInitParameter() {
        // Given
        let endpoint = URL(string: "https://stats.example.com")!

        // When
        let config = Trace.Configuration(customStatsEndpoint: endpoint)

        // Then
        XCTAssertEqual(config.customStatsEndpoint, endpoint)
        XCTAssertNil(config.customEndpoint, "customEndpoint should remain independent of customStatsEndpoint")
    }

    func testDefaultURLSessionTrackingConfiguration() {
        // When
        let tracking = Trace.Configuration.URLSessionTracking(
            firstPartyHostsTracing: .trace(hosts: [])
        )

        // Then
        XCTAssertEqual(tracking.redactedStatusCodes, [404])
    }
}
