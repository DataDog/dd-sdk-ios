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
        XCTAssertEqual(ClientStatsFeature.name, "tracing-client-stats")
    }

    func testWhenStatsComputationEnabledWithCustomDateProvider_thenStatsFeatureUsesItForFlushTiming() throws {
        let core = FeatureRegistrationPassthroughCoreMock()
        let dateProvider = RelativeDateProvider(using: Date(timeIntervalSince1970: 0))

        config.statsComputationEnabled = true
        config.dateProvider = dateProvider

        Trace.enable(with: config, in: core)

        let stats = try XCTUnwrap(core.get(feature: ClientStatsFeature.self))
        stats.concentrator.add(SpanSnapshot.mockWith(
            startTime: 20_000_000_000,
            duration: 5_000_000_000,
            isTopLevel: true
        ))

        stats.flushStats(force: false)

        XCTAssertTrue(core.exportedBuckets.isEmpty)
    }
}

private final class FeatureRegistrationPassthroughCoreMock: DatadogCoreProtocol, FeatureScope {
    private let writer = FileWriterMock()
    private let contextValue: DatadogContext
    private var registeredFeatures: [DatadogFeature] = []

    init(context: DatadogContext = .mockAny()) {
        self.contextValue = context
    }

    func register<T>(feature: T) throws where T: DatadogFeature {
        registeredFeatures.append(feature)
    }

    func feature<T>(named name: String, type: T.Type) -> T? {
        registeredFeatures.first { $0 is T } as? T
    }

    func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature {
        self
    }

    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { }

    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { }

    func mostRecentModifiedFileAt(before: Date) throws -> Date? {
        nil
    }

    func eventWriteContext(bypassConsent: Bool, _ block: @escaping (DatadogContext, Writer) -> Void) {
        block(contextValue, writer)
    }

    func context(_ block: @escaping (DatadogContext) -> Void) {
        block(contextValue)
    }

    var dataStore: DataStore { NOPDataStore() }
    var telemetry: Telemetry { NOPTelemetry() }

    func set(anonymousId: String?) { }

    var exportedBuckets: [ExportedBucket] {
        writer.events(ofType: ExportedBucket.self)
    }
}
