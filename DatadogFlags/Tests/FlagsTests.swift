/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@_spi(Internal)
@testable import DatadogFlags

final class FlagsTests: XCTestCase {
    func testDefaultConfiguration() {
        // Given
        let config = Flags.Configuration()

        // Then
        XCTAssertNil(config.customExposureEndpoint)
        XCTAssertNil(config.assignmentRequestFetch)
        XCTAssertEqual(config.assignmentRequestTimeout, 0)
        XCTAssertEqual(config.assignmentRequestRetryCount, 0)
    }

    func testLegacyInitializerKeepsAssignmentRequestDefaults() {
        let config = Flags.Configuration(
            gracefulModeEnabled: false,
            customFlagsEndpoint: nil,
            customFlagsHeaders: nil,
            customExposureEndpoint: nil,
            trackExposures: false,
            customEvaluationEndpoint: nil,
            trackEvaluations: false,
            evaluationFlushInterval: 20,
            rumIntegrationEnabled: false
        )

        XCTAssertNil(config.assignmentRequestFetch)
        XCTAssertEqual(config.assignmentRequestTimeout, 0)
        XCTAssertEqual(config.assignmentRequestRetryCount, 0)
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
        config.assignmentRequestTimeout = 2.5
        config.assignmentRequestRetryCount = 3
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
        XCTAssertEqual(flagAssignmentFetcher.assignmentRequestTimeout, Optional(2.5))
        XCTAssertEqual(flagAssignmentFetcher.assignmentRequestRetryCount, Optional(3))
        let requestBuilder = try XCTUnwrap(flags.requestBuilder as? ExposureRequestBuilder)
        XCTAssertEqual(requestBuilder.customIntakeURL, config.customExposureEndpoint)
    }

    func testInvalidAssignmentRequestConfigurationIsBounded() throws {
        let inputs: [(TimeInterval, Int, TimeInterval, Int)] = [
            (-.infinity, -1, 0, 0),
            (.nan, 11, 0, 10),
            (.greatestFiniteMagnitude, 1, 2_147_483.647, 1),
        ]

        for (timeout, retryCount, expectedTimeout, expectedRetryCount) in inputs {
            var configuration = Flags.Configuration()
            configuration.assignmentRequestTimeout = timeout
            configuration.assignmentRequestRetryCount = retryCount
            let core = FeatureRegistrationCoreMock()

            Flags.enable(with: configuration, in: core)

            let flags = try XCTUnwrap(core.get(feature: FlagsFeature.self))
            let fetcher = try XCTUnwrap(flags.flagAssignmentsFetcher as? FlagAssignmentsFetcher)
            XCTAssertEqual(fetcher.assignmentRequestTimeout, Optional(expectedTimeout))
            XCTAssertEqual(fetcher.assignmentRequestRetryCount, Optional(expectedRetryCount))
        }
    }

    func testZeroAssignmentRequestTimeoutAndRetryCountAreAccepted() throws {
        var configuration = Flags.Configuration()
        configuration.assignmentRequestTimeout = 0
        configuration.assignmentRequestRetryCount = 0
        let core = FeatureRegistrationCoreMock()

        Flags.enable(with: configuration, in: core)

        let flags = try XCTUnwrap(core.get(feature: FlagsFeature.self))
        let fetcher = try XCTUnwrap(flags.flagAssignmentsFetcher as? FlagAssignmentsFetcher)
        XCTAssertEqual(fetcher.assignmentRequestTimeout, Optional(0))
        XCTAssertEqual(fetcher.assignmentRequestRetryCount, Optional(0))
    }

    func testCustomAssignmentRequestFetchBypassesScalarPolicy() throws {
        // Given
        var fetchCount = 0
        let expectedError = URLError(.notConnectedToInternet)
        let customFetch = Flags.AssignmentRequestFetch { _, completion in
            fetchCount += 1
            completion(.failure(expectedError))
            return {}
        }
        var configuration = Flags.Configuration()
        configuration.assignmentRequestTimeout = 0.000001
        configuration.assignmentRequestRetryCount = 10
        configuration.assignmentRequestFetch = customFetch
        let core = SingleFeatureCoreMock<FlagsFeature>()
        var capturedResult: Result<[String: FlagAssignment], FlagsError>?

        // When
        Flags.enable(with: configuration, in: core)
        let feature = try XCTUnwrap(core.get(feature: FlagsFeature.self))
        feature.flagAssignmentsFetcher.flagAssignments(for: .mockAny()) { capturedResult = $0 }

        // Then
        XCTAssertEqual(fetchCount, 1, "scalar retries must not wrap a custom transport")
        let fetcher = try XCTUnwrap(feature.flagAssignmentsFetcher as? FlagAssignmentsFetcher)
        XCTAssertNil(fetcher.assignmentRequestTimeout)
        XCTAssertNil(fetcher.assignmentRequestRetryCount)
        guard
            case .failure(.networkError(let error)) = capturedResult,
            (error as? URLError)?.code == expectedError.code
        else {
            return XCTFail("Expected the custom transport failure without scalar policy")
        }
    }
}
