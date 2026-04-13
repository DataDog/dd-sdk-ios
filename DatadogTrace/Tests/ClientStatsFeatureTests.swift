/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal
@testable import DatadogTrace

class ClientStatsFeatureTests: XCTestCase {
    private var core: FeatureRegistrationCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional
    private var config: Trace.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        core = FeatureRegistrationCoreMock()
        config = Trace.Configuration()
    }

    override func tearDown() {
        core = nil
        config = nil
        XCTAssertEqual(FeatureRegistrationCoreMock.referenceCount, 0)
    }

    // MARK: - Registration

    func testWhenStatsComputationDisabled_thenClientStatsFeatureIsNotRegistered() {
        // Given
        config.statsComputationEnabled = false

        // When
        Trace.enable(with: config, in: core)

        // Then
        XCTAssertNil(core.get(feature: ClientStatsFeature.self))
    }

    func testWhenStatsComputationEnabled_thenClientStatsFeatureIsRegistered() {
        // Given
        config.statsComputationEnabled = true

        // When
        Trace.enable(with: config, in: core)

        // Then
        XCTAssertNotNil(core.get(feature: ClientStatsFeature.self))
    }

    func testWhenStatsComputationEnabled_thenTraceFeatureIsAlsoRegistered() {
        // Given
        config.statsComputationEnabled = true

        // When
        Trace.enable(with: config, in: core)

        // Then
        XCTAssertNotNil(core.get(feature: TraceFeature.self))
        XCTAssertNotNil(core.get(feature: ClientStatsFeature.self))
    }

    func testWhenDefaultConfiguration_thenStatsComputationIsDisabled() {
        // Given
        let defaultConfig = Trace.Configuration()

        // Then
        XCTAssertFalse(defaultConfig.statsComputationEnabled)
    }

    // MARK: - Request Builder

    func testWhenStatsComputationEnabled_thenRequestBuilderUsesStatsEndpoint() throws {
        // Given
        config.statsComputationEnabled = true

        // When
        Trace.enable(with: config, in: core)

        // Then
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        XCTAssertTrue(stats.requestBuilder is StatsRequestBuilder)
    }

    func testWhenStatsComputationEnabledWithCustomEndpoint_thenRequestBuilderUsesCustomURL() throws {
        // Given
        let customURL: URL = .mockRandom()
        config.statsComputationEnabled = true
        config.customEndpoint = customURL

        // When
        Trace.enable(with: config, in: core)

        // Then
        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        let requestBuilder = try XCTUnwrap(stats.requestBuilder as? StatsRequestBuilder)
        XCTAssertEqual(requestBuilder.customIntakeURL, customURL)
    }

    // MARK: - Feature Name

    func testFeatureName() {
        XCTAssertEqual(ClientStatsFeature.name, "client-stats")
    }
}
