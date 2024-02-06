/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import OpenTelemetryApi
@testable import DatadogInternal
@testable import DatadogTrace

class TraceTests: XCTestCase {
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

    func testWhenNotEnabled_thenTracerIsNotAvailable() {
        // When
        XCTAssertNil(core.get(feature: TraceFeature.self))

        // Then
        XCTAssertTrue(Tracer.shared(in: core) is DDNoopTracer)
    }

    func testWhenEnabledInNOPCore_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // When
        Trace.enable(with: config, in: NOPDatadogCore())

        // Then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Datadog SDK must be initialized before calling `Trace.enable(with:)`."
        )
    }

    func testWhenEnabled_thenTracerIsAvailable() {
        // When
        Trace.enable(with: config, in: core)
        XCTAssertNotNil(core.get(feature: TraceFeature.self))

        // Then
        XCTAssertTrue(Tracer.shared(in: core) is DatadogTracer)
    }

    // MARK: - Configuration Tests

    func testWhenEnabledWithDefaultConfiguration() throws {
        // When
        Trace.enable(in: core)

        // Then
        let tracer = Tracer.shared(in: core).dd
        let trace = try XCTUnwrap(core.get(feature: TraceFeature.self))
        XCTAssertEqual(tracer.sampler.samplingRate, 100)
        XCTAssertNil(tracer.spanEventBuilder.service)
        XCTAssertNil(tracer.loggingIntegration.service)
        XCTAssertTrue(tracer.tags.isEmpty)
        XCTAssertNil(core.get(feature: NetworkInstrumentationFeature.self))
        XCTAssertEqual(tracer.spanEventBuilder.networkInfoEnabled, false)
        XCTAssertNil(tracer.spanEventBuilder.eventsMapper)
        XCTAssertNil((trace.requestBuilder as? TracingRequestBuilder)?.customIntakeURL)
    }

    func testWhenEnabledWithSampleRate() {
        // Given
        let random: Float = .mockRandom(min: 0, max: 100)
        config.sampleRate = random

        // When
        Trace.enable(with: config, in: core)

        // Then
        let tracer = Tracer.shared(in: core).dd
        XCTAssertEqual(tracer.sampler.samplingRate, random, accuracy: 0.001)
    }

    func testWhenEnabledWithService() {
        // Given
        let random: String = .mockRandom()
        config.service = random

        // When
        Trace.enable(with: config, in: core)

        // Then
        let tracer = Tracer.shared(in: core).dd
        XCTAssertEqual(tracer.spanEventBuilder.service, random)
        XCTAssertEqual(tracer.loggingIntegration.service, random)
    }

    func testWhenEnabledWithTags() {
        // Given
        let random = mockRandomAttributes()
        config.tags = random

        // When
        Trace.enable(with: config, in: core)

        // Then
        let tracer = Tracer.shared(in: core).dd
        DDAssertDictionariesEqual(tracer.tags, random)
    }

    func testWhenEnabledWithURLSessionTracking() throws {
        // Given
        // swiftlint:disable opening_brace
        oneOf([
            { self.config.urlSessionTracking = .init(
                firstPartyHostsTracing: .trace(hosts: ["example.com"])
            ) },
            { self.config.urlSessionTracking = .init(
                firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: ["example.com": [.datadog, .b3]])
            ) },
        ])
        // swiftlint:enable opening_brace

        // When
        Trace.enable(with: config, in: core)

        // Then
        let networkInstrumentation = try XCTUnwrap(
            core.get(feature: NetworkInstrumentationFeature.self),
            "It should enable `NetworkInstrumentationFeature`"
        )
        let tracingHandler = try XCTUnwrap(
            networkInstrumentation.handlers.firstElement(of: TracingURLSessionHandler.self),
            "It should register `TracingURLSessionHandler` to `NetworkInstrumentationFeature`"
        )
        XCTAssertEqual(tracingHandler.tracingSampler.samplingRate, 20)
    }

    func testWhenEnabledWithURLSessionTrackingAndCustomSampleRate() throws {
        // Given
        let random: Float = .mockRandom(min: 0, max: 100)
        // swiftlint:disable opening_brace
        oneOf([
            { self.config.urlSessionTracking = .init(
                firstPartyHostsTracing: .trace(hosts: ["example.com"], sampleRate: random)
            ) },
            { self.config.urlSessionTracking = .init(
                firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: ["example.com": [.datadog, .b3]], sampleRate: random)
            ) },
        ])
        // swiftlint:enable opening_brace

        // When
        Trace.enable(with: config, in: core)

        // Then
        let networkInstrumentation = try XCTUnwrap(
            core.get(feature: NetworkInstrumentationFeature.self),
            "It should enable `NetworkInstrumentationFeature`"
        )
        let tracingHandler = try XCTUnwrap(
            networkInstrumentation.handlers.firstElement(of: TracingURLSessionHandler.self),
            "It should register `TracingURLSessionHandler` to `NetworkInstrumentationFeature`"
        )
        XCTAssertEqual(tracingHandler.tracingSampler.samplingRate, random, accuracy: 0.001)
    }

    func testWhenEnabledWithBundleWithRUM() throws {
        // Given
        let random: Bool = .mockRandom()
        config.bundleWithRumEnabled = random

        // When
        Trace.enable(with: config, in: core)

        // Then
        let tracer = Tracer.shared(in: core).dd
        XCTAssertEqual(tracer.spanEventBuilder.bundleWithRUM, random)
    }

    func testWhenEnabledWithSendNetworkInfo() {
        // Given
        let random: Bool = .mockRandom()
        config.networkInfoEnabled = random

        // When
        Trace.enable(with: config, in: core)

        // Then
        let tracer = Tracer.shared(in: core).dd
        XCTAssertEqual(tracer.spanEventBuilder.networkInfoEnabled, random)
        XCTAssertEqual(tracer.loggingIntegration.networkInfoEnabled, random)
    }

    func testWhenEnabledWithEventMapper() {
        // Given
        let random: Bool = .mockRandom()
        config.networkInfoEnabled = random

        // When
        Trace.enable(with: config, in: core)

        // Then
        let tracer = Tracer.shared(in: core).dd
        XCTAssertEqual(tracer.spanEventBuilder.networkInfoEnabled, random)
        XCTAssertEqual(tracer.loggingIntegration.networkInfoEnabled, random)
    }

    func testWhenEnabledWithCustomEndpoint() throws {
        // Given
        let random: URL = .mockRandom()
        config.customEndpoint = random

        // When
        Trace.enable(with: config, in: core)

        // Then
        let trace = try XCTUnwrap(core.get(feature: TraceFeature.self))
        XCTAssertEqual((trace.requestBuilder as? TracingRequestBuilder)?.customIntakeURL, random)
    }

    func testWhenEnabledWithDebugSDKArgument() throws {
        // Given
        let random: Float = .mockRandom(min: 0, max: 100)
        config.sampleRate = random
        // swiftlint:disable opening_brace
        oneOf([
            { self.config.urlSessionTracking = .init(firstPartyHostsTracing: .trace(hosts: [], sampleRate: random)) },
            { self.config.urlSessionTracking = .init(firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: [:], sampleRate: random)) },
        ])
        // swiftlint:enable opening_brace
        config.debugSDK = true

        // When
        Trace.enable(with: config, in: core)

        // Then
        let tracer = try XCTUnwrap(Tracer.shared(in: core) as? DatadogTracer)
        let networkInstrumentation = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let tracingHandler = try XCTUnwrap(networkInstrumentation.handlers.firstElement(of: TracingURLSessionHandler.self))
        XCTAssertEqual(tracer.sampler.samplingRate, 100)
        XCTAssertEqual(tracingHandler.tracingSampler.samplingRate, 100)
    }

    func testWhenEnabledWithNoDebugSDKArgument() throws {
        // Given
        let random: Float = .mockRandom(min: 0, max: 100)
        config.sampleRate = random
        // swiftlint:disable opening_brace
        oneOf([
            { self.config.urlSessionTracking = .init(firstPartyHostsTracing: .trace(hosts: [], sampleRate: random)) },
            { self.config.urlSessionTracking = .init(firstPartyHostsTracing: .traceWithHeaders(hostsWithHeaders: [:], sampleRate: random)) },
        ])
        // swiftlint:enable opening_brace
        config.debugSDK = false

        // When
        Trace.enable(with: config, in: core)

        // Then
        let tracer = try XCTUnwrap(Tracer.shared(in: core) as? DatadogTracer)
        let networkInstrumentation = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let tracingHandler = try XCTUnwrap(networkInstrumentation.handlers.firstElement(of: TracingURLSessionHandler.self))
        XCTAssertEqual(tracer.sampler.samplingRate, random)
        XCTAssertEqual(tracingHandler.tracingSampler.samplingRate, random)
    }
}
