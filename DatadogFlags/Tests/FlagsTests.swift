/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogFlags

final class FlagsTests: XCTestCase {
    func testDefaultConfiguration() {
        // Given
        let config = Flags.Configuration()

        // Then
        XCTAssertNil(config.customExposureEndpoint)
        XCTAssertEqual(config.initializationTimeout, 5)
        XCTAssertEqual(config.assignmentProtection, .disabled)
        XCTAssertNil(config.assignmentAuthorization)
    }

    func testConfigurationInitializerSetsInitializationTimeout() {
        // When
        let configured = Flags.Configuration(initializationTimeout: 2.5)
        let disabled = Flags.Configuration(initializationTimeout: nil)

        // Then
        XCTAssertEqual(configured.initializationTimeout, 2.5)
        XCTAssertNil(disabled.initializationTimeout)
    }

    func testAuthorizationInfersSignedAndAuthorizedProtectionForSourceCompatibility() {
        let authorization = Flags.AssignmentAuthorization(
            bearerToken: "header.payload.signature",
            expiresAt: .distantFuture
        )

        let config = Flags.Configuration(assignmentAuthorization: authorization)

        XCTAssertEqual(config.assignmentProtection, .signedAndAuthorized)
        XCTAssertEqual(config.assignmentAuthorization, authorization)
    }

    func testExplicitSignedProtectionDoesNotRequireAuthorization() {
        let config = Flags.Configuration(assignmentProtection: .signed)

        XCTAssertEqual(config.assignmentProtection, .signed)
        XCTAssertNil(config.assignmentAuthorization)
    }

    func testExplicitSignedProtectionRejectsAuthorizationWithoutDowngradeOrCrash() {
        let core = FeatureRegistrationCoreMock()
        let config = Flags.Configuration(
            assignmentProtection: .signed,
            assignmentAuthorization: .init(
                bearerToken: "header.payload.signature",
                expiresAt: .distantFuture
            )
        )

        XCTAssertThrowsError(try Flags.enableOrThrow(with: config, in: core))
        XCTAssertNil(core.get(feature: FlagsFeature.self))
    }

    func testWhenNotEnabled() {
        // Given
        let core = FeatureRegistrationCoreMock()

        // When / Then
        XCTAssertNil(core.get(feature: FlagsFeature.self))
    }

    func testWhenEnabled() {
        // Given
        let core = FeatureRegistrationCoreMock()

        // When
        Flags.enable(in: core)

        // Then
        XCTAssertNotNil(core.get(feature: FlagsFeature.self))
    }

    func testCustomConfiguration() throws {
        // Given
        var config = Flags.Configuration()
        config.customFlagsEndpoint = .mockRandom()
        config.customFlagsHeaders = .mockRandom()
        config.initializationTimeout = 2.5
        config.assignmentProtection = .signed
        config.customExposureEndpoint = .mockRandom()
        let core = FeatureRegistrationCoreMock()

        // When
        Flags.enable(with: config, in: core)

        // Then
        let flags = try XCTUnwrap(core.get(feature: FlagsFeature.self))
        let flagAssignmentFetcher = try XCTUnwrap(flags.flagAssignmentsFetcher as? FlagAssignmentsFetcher)
        XCTAssertEqual(flags.performanceOverride?.maxObjectsInFile, 50)
        XCTAssertEqual(flagAssignmentFetcher.customEndpoint, config.customFlagsEndpoint)
        XCTAssertEqual(flagAssignmentFetcher.customHeaders, config.customFlagsHeaders)
        XCTAssertEqual(flags.initializationTimeout, config.initializationTimeout)
        XCTAssertEqual(flags.assignmentProtection, .signed)
        let requestBuilder = try XCTUnwrap(flags.requestBuilder as? ExposureRequestBuilder)
        XCTAssertEqual(requestBuilder.customIntakeURL, config.customExposureEndpoint)
    }
}
