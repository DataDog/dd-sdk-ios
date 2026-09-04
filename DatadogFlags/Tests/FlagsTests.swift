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
        XCTAssertNil(config.assignmentRequestFetch)
        XCTAssertEqual(config.assignmentRequestTimeout, 0)
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
        config.customExposureEndpoint = .mockRandom()
        config.assignmentRequestFetch = .init { _, _ in {} }
        config.assignmentRequestTimeout = 1.5
        let core = FeatureRegistrationCoreMock()

        // When
        Flags.enable(with: config, in: core)

        // Then
        let flags = try XCTUnwrap(core.get(feature: FlagsFeature.self))
        let flagAssignmentFetcher = try XCTUnwrap(flags.flagAssignmentsFetcher as? FlagAssignmentsFetcher)
        XCTAssertEqual(flags.performanceOverride?.maxObjectsInFile, 50)
        XCTAssertEqual(flagAssignmentFetcher.customEndpoint, config.customFlagsEndpoint)
        XCTAssertEqual(flagAssignmentFetcher.customHeaders, config.customFlagsHeaders)
        XCTAssertNotNil(config.assignmentRequestFetch)
        XCTAssertEqual(config.assignmentRequestTimeout, 1.5)
        let requestBuilder = try XCTUnwrap(flags.requestBuilder as? ExposureRequestBuilder)
        XCTAssertEqual(requestBuilder.customIntakeURL, config.customExposureEndpoint)
    }

    func testZeroAssignmentRequestTimeoutIsAccepted() {
        var configuration = Flags.Configuration()
        configuration.assignmentRequestTimeout = 0
        let core = FeatureRegistrationCoreMock()

        Flags.enable(with: configuration, in: core)

        XCTAssertNotNil(core.get(feature: FlagsFeature.self))
    }

    func testCustomAssignmentRequestFetchBypassesScalarTimeout() throws {
        // Given
        let fetchCount = FlagsTestsLockedBox(0)
        let expectedError = URLError(.notConnectedToInternet)
        let customFetch = Flags.AssignmentRequestFetch { _, completion in
            fetchCount.mutate { $0 += 1 }
            completion(.failure(expectedError))
            return {}
        }
        var configuration = Flags.Configuration()
        configuration.assignmentRequestTimeout = 0.000001
        configuration.assignmentRequestFetch = customFetch
        let core = SingleFeatureCoreMock<FlagsFeature>()
        let capturedErrorCode = FlagsTestsLockedBox<URLError.Code?>(nil)
        let completion = expectation(description: "custom transport completed")

        // When
        Flags.enable(with: configuration, in: core)
        let feature = try XCTUnwrap(core.get(feature: FlagsFeature.self))
        feature.flagAssignmentsFetcher.flagAssignments(for: .mockAny()) { result in
            if case .failure(.networkError(let error)) = result {
                capturedErrorCode.value = (error as? URLError)?.code
            }
            completion.fulfill()
        }
        wait(for: [completion], timeout: 1)

        // Then
        XCTAssertEqual(fetchCount.value, 1)
        XCTAssertEqual(capturedErrorCode.value, expectedError.code)
    }
}

private final class FlagsTestsLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }

    @discardableResult
    func mutate<Result>(_ mutation: (inout Value) -> Result) -> Result {
        lock.withLock { mutation(&storedValue) }
    }
}
