/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogFlags

final class FlagsTests: XCTestCase {
    func testDefaultConfiguration() {
        // Given
        let config = Flags.Configuration()

        // Then
        XCTAssertNil(config.customExposureEndpoint)
        XCTAssertEqual(config.initializationTimeout, 5)
        XCTAssertNil(config.flagSelection)
    }

    func testConfigurationInitializerSetsInitializationTimeout() {
        // When
        let configured = Flags.Configuration(initializationTimeout: 2.5)
        let disabled = Flags.Configuration(initializationTimeout: nil)

        // Then
        XCTAssertEqual(configured.initializationTimeout, 2.5)
        XCTAssertNil(disabled.initializationTimeout)
    }

    func testInitializerWithoutFlagSelectionKeepsEveryValue() throws {
        // Given
        let flagsEndpoint = try XCTUnwrap(URL(string: "https://flags.example.com"))
        let exposureEndpoint = try XCTUnwrap(URL(string: "https://exposures.example.com"))
        let evaluationEndpoint = try XCTUnwrap(URL(string: "https://evaluations.example.com"))

        // When
        // A reference by full name never fills in default arguments, so it binds only to the 10-parameter initializer.
        let makeConfiguration: (Bool, URL?, [String: String]?, TimeInterval?, URL?, Bool, URL?, Bool, TimeInterval, Bool) -> Flags.Configuration =
            Flags.Configuration.init(gracefulModeEnabled:customFlagsEndpoint:customFlagsHeaders:initializationTimeout:customExposureEndpoint:trackExposures:customEvaluationEndpoint:trackEvaluations:evaluationFlushInterval:rumIntegrationEnabled:)
        let config = makeConfiguration(false, flagsEndpoint, ["key": "value"], 2.5, exposureEndpoint, false, evaluationEndpoint, false, 30, false)

        // Then
        XCTAssertFalse(config.gracefulModeEnabled)
        XCTAssertEqual(config.customFlagsEndpoint, flagsEndpoint)
        XCTAssertEqual(config.customFlagsHeaders, ["key": "value"])
        XCTAssertEqual(config.initializationTimeout, 2.5)
        XCTAssertEqual(config.customExposureEndpoint, exposureEndpoint)
        XCTAssertFalse(config.trackExposures)
        XCTAssertEqual(config.customEvaluationEndpoint, evaluationEndpoint)
        XCTAssertFalse(config.trackEvaluations)
        XCTAssertEqual(config.evaluationFlushInterval, 30)
        XCTAssertFalse(config.rumIntegrationEnabled)
        XCTAssertNil(config.flagSelection)
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
        config.flagSelection = .init(tags: [" mobile ", "mobile"], keyPatterns: ["checkout.*"])
        let core = FeatureRegistrationCoreMock()

        // When
        Flags.enable(with: config, in: core)

        // Then
        let flags = try XCTUnwrap(core.get(feature: FlagsFeature.self))
        let flagAssignmentFetcher = try XCTUnwrap(flags.flagAssignmentsFetcher as? FlagAssignmentsFetcher)
        XCTAssertEqual(flags.performanceOverride?.maxObjectsInFile, 50)
        XCTAssertEqual(flagAssignmentFetcher.customEndpoint, config.customFlagsEndpoint)
        XCTAssertEqual(flagAssignmentFetcher.customHeaders, config.customFlagsHeaders)
        let expectedFlagSelection = CanonicalFlagSelection(tags: ["mobile"], keyPatterns: ["checkout.*"])
        XCTAssertEqual(flags.flagSelection, expectedFlagSelection)
        XCTAssertEqual(flagAssignmentFetcher.flagSelection, expectedFlagSelection)
        XCTAssertEqual(flags.initializationTimeout, config.initializationTimeout)
        let requestBuilder = try XCTUnwrap(flags.requestBuilder as? ExposureRequestBuilder)
        XCTAssertEqual(requestBuilder.customIntakeURL, config.customExposureEndpoint)
    }

    func testDroppedFlagSelectionIsReportedOnceWhenTheFeatureIsEnabledAndIsNotSent() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let featureScope = FeatureScopeMock()

        // When
        let flags = FlagsFeature(
            configuration: .init(trackEvaluations: false, flagSelection: .init(tags: (1...32).map { "v\($0)" })),
            featureScope: featureScope,
            core: FeatureRegistrationCoreMock()
        )

        // Then
        // Fetches and clients use this resolved value, so they send no selection and do not report the drop again.
        XCTAssertNil(flags.flagSelection)
        XCTAssertNil(try XCTUnwrap(flags.flagAssignmentsFetcher as? FlagAssignmentsFetcher).flagSelection)
        XCTAssertEqual(dd.logger.errorMessages.count, 1)
        XCTAssertEqual(featureScope.telemetryMock.messages.count, 1)
    }

    func testResponseProtectionIsNotSetByDefault() {
        XCTAssertNil(Flags.Configuration().responseProtection)
        XCTAssertNil(FlagsFeature(configuration: .init(trackEvaluations: false), featureScope: FeatureScopeMock(), core: FeatureRegistrationCoreMock()).responseProtection)
    }

    func testEnablingWithRequiredTLSPinningUsesThePolicy() throws {
        // Given
        let core = FeatureRegistrationCoreMock()
        var config = Flags.Configuration(trackEvaluations: false)
        config.responseProtection = .tlsPinning(
            mode: .required,
            profile: .init(
                origin: URL(string: "https://\(TLSPinningFixtures.host)")!,
                pinTarget: .leaf,
                spkiSHA256Pins: [TLSPinningFixtures.pinP256, TLSPinningFixtures.pinP384]
            )
        )

        // When
        Flags.enable(with: config, in: core)

        // Then
        let feature = try XCTUnwrap(core.get(feature: FlagsFeature.self))
        guard case .tlsPinning(let policy)? = feature.responseProtection else {
            return XCTFail("Expected a TLS pinning policy, got \(String(describing: feature.responseProtection))")
        }
        XCTAssertEqual(policy.host, TLSPinningFixtures.host)
        let fetcher = try XCTUnwrap(feature.flagAssignmentsFetcher as? FlagAssignmentsFetcher)
        XCTAssertEqual(fetcher.responseProtection, feature.responseProtection)
    }

    func testEnablingWithAnInvalidRequiredPolicyReportsTheErrorAndFailsClosed() throws {
        // Given
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }
        let core = FeatureRegistrationCoreMock()
        var config = Flags.Configuration(trackEvaluations: false)
        config.customFlagsEndpoint = URL(string: "https://proxy.example.com/assignments")
        config.responseProtection = .tlsPinning(
            mode: .required,
            profile: .init(
                origin: URL(string: "https://\(TLSPinningFixtures.host)")!,
                pinTarget: .leaf,
                spkiSHA256Pins: [TLSPinningFixtures.pinP256, TLSPinningFixtures.pinP384]
            )
        )

        // When
        Flags.enable(with: config, in: core)

        // Then
        // The feature stays enabled, so clients can be created without crashing, but no assignment is fetched.
        let feature = try XCTUnwrap(core.get(feature: FlagsFeature.self))
        XCTAssertEqual(feature.responseProtection, .misconfigured)
        XCTAssertEqual(dd.logger.errorMessages.count, 1)
        XCTAssertTrue(try XCTUnwrap(printFunction.printedMessage).contains("customFlagsEndpoint"))
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
