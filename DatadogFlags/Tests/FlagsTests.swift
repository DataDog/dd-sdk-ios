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
    }

    func testConfigurationInitializerSetsInitializationTimeout() {
        // When
        let configured = Flags.Configuration(initializationTimeout: 2.5)
        let disabled = Flags.Configuration(initializationTimeout: nil)

        // Then
        XCTAssertEqual(configured.initializationTimeout, 2.5)
        XCTAssertNil(disabled.initializationTimeout)
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
        let requestBuilder = try XCTUnwrap(flags.requestBuilder as? ExposureRequestBuilder)
        XCTAssertEqual(requestBuilder.customIntakeURL, config.customExposureEndpoint)
    }

    func testSigningFeatureStopInvalidatesRetainedClientAndFetcher() throws {
        for mode in [Flags.ResponseSigningMode.observe, .required] {
            let core = DatadogCoreProxy()
            var didStop = false
            defer { if !didStop { try? core.flushAndTearDown() } }
            Flags.enable(with: .init(trackEvaluations: false, responseSigning: .init(mode: mode)), in: core)
            // Keep only the fetcher/client, not a copy of the feature that owns the lifetime marker.
            let fetcher = try XCTUnwrap(
                core.get(feature: FlagsFeature.self)?.flagAssignmentsFetcher as? FlagAssignmentsFetcher
            )
            let retainedClient = FlagsClient.create(in: core)
            let scoped = expectation(description: "scope established")
            fetcher.resolveResponseSigningCacheScope { scope in
                XCTAssertNotNil(scope)
                scoped.fulfill()
            }
            wait(for: [scoped], timeout: 2)
            try core.flushAndTearDown()
            didStop = true
            XCTAssertNil(fetcher.responseSigningCacheScope)
            XCTAssertNil(fetcher.updateResponseSigningCacheScope(core.context))
            XCTAssertFalse(retainedClient.getBooleanValue(key: "flag", defaultValue: false))
            let rejected = expectation(description: "retained client cannot fetch after stop")
            retainedClient.setEvaluationContext(.init(targetingKey: "after-stop")) { result in
                guard case .failure(.clientNotInitialized) = result else {
                    XCTFail("retained client restarted a stopped signing feature")
                    rejected.fulfill()
                    return
                }
                rejected.fulfill()
            }
            wait(for: [rejected], timeout: 2)
        }
    }

    func testFlushFlushesRegisteredClients() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)
        let flags = try XCTUnwrap(core.get(feature: FlagsFeature.self))
        let repository = FlagsRepositoryMock()
        let client = FlagsClient(
            repository: repository,
            exposureLogger: ExposureLoggerMock(),
            evaluationLogger: EvaluationLoggerMock(),
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )
        flags.clientRegistry.register(client, named: "client")

        // When
        flags.flush()

        // Then
        XCTAssertEqual(repository.flushCallsCount, 1)
    }
}
