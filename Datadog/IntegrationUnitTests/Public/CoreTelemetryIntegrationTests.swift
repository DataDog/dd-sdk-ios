/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogCore
import DatadogInternal
@testable import DatadogRUM
import TestUtilities

class CoreTelemetryIntegrationTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        core = DatadogCoreProxy()
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
    }

    func testGivenRUMEnabled_telemetryEventsAreSent() throws {
        // Given
        var config = RUM.Configuration(applicationID: .mockAny())
        config.telemetrySampleRate = .maxSampleRate
        RUM.enable(with: config, in: core)

        // When
        core.telemetry.debug("Debug Telemetry", attributes: ["debug.attribute": 42])
        #sourceLocation(file: "File.swift", line: 42)
        core.telemetry.error("Error Telemetry")
        #sourceLocation()
        core.telemetry.metric(name: "Metric Name", attributes: ["metric.attribute": 42], sampleRate: 100)
        core.telemetry.stopMethodCalled(
            core.telemetry.startMethodCalled(operationName: .mockRandom(), callerClass: .mockRandom(), headSampleRate: 100),
            tailSampleRate: 100
        )

        // Then
        let debugEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryDebugEvent.self)
        let errorEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryErrorEvent.self)

        XCTAssertEqual(debugEvents.count, 3) // metrics are transported as debug events
        XCTAssertEqual(errorEvents.count, 1)

        let debug = debugEvents[0]
        XCTAssertEqual(debug.telemetry.message, "Debug Telemetry")
        DDAssertReflectionEqual(debug.telemetry.telemetryInfo, ["debug.attribute": 42])

        let error = errorEvents[0]
        XCTAssertEqual(error.telemetry.message, "Error Telemetry")
        XCTAssertEqual(error.telemetry.error?.kind, "\(moduleName())/File.swift")
        XCTAssertEqual(error.telemetry.error?.stack, "\(moduleName())/File.swift:42")

        let metric = debugEvents[1]
        XCTAssertEqual(metric.telemetry.message, "[Mobile Metric] Metric Name")

        let metricAttribute = try XCTUnwrap(metric.telemetry.telemetryInfo["metric.attribute"] as? Int)
        XCTAssertEqual(metricAttribute, 42)

        let methodCalledMetric = debugEvents[2]
        XCTAssertEqual(methodCalledMetric.telemetry.message, "[Mobile Metric] Method Called")
    }

    func testGivenRUMEnabled_whenNoViewIsActive_telemetryEventsAreLinkedToSession() throws {
        // Given
        var config = RUM.Configuration(applicationID: "rum-app-id")
        config.telemetrySampleRate = .maxSampleRate
        RUM.enable(with: config, in: core)

        // When
        RUMMonitor.shared(in: core).startView(key: "View")
        RUMMonitor.shared(in: core).stopView(key: "View")

        // Then
        core.telemetry.debug("Debug Telemetry")
        core.telemetry.error("Error Telemetry")
        core.telemetry.metric(name: "Metric Name", attributes: [:], sampleRate: 100)
        core.telemetry.stopMethodCalled(
            core.telemetry.startMethodCalled(operationName: .mockRandom(), callerClass: .mockRandom(), headSampleRate: 100),
            tailSampleRate: 100
        )

        let debugEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryDebugEvent.self)
        let errorEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryErrorEvent.self)

        let debug = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "Debug Telemetry" }))
        XCTAssertEqual(debug.application?.id, "rum-app-id")
        XCTAssertNotNil(debug.session?.id)
        XCTAssertNil(debug.view?.id)
        XCTAssertNil(debug.action?.id)

        let error = try XCTUnwrap(errorEvents.first)
        XCTAssertEqual(error.application?.id, "rum-app-id")
        XCTAssertNotNil(error.session?.id)
        XCTAssertNil(error.view?.id)
        XCTAssertNil(error.action?.id)

        let metric = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "[Mobile Metric] Metric Name" }))
        XCTAssertEqual(metric.application?.id, "rum-app-id")
        XCTAssertNotNil(metric.session?.id)
        XCTAssertNil(metric.view?.id)
        XCTAssertNil(metric.action?.id)

        let methodCalledMetric = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "[Mobile Metric] Method Called" }))
        XCTAssertEqual(methodCalledMetric.application?.id, "rum-app-id")
        XCTAssertNotNil(methodCalledMetric.session?.id)
        XCTAssertNil(methodCalledMetric.view?.id)
        XCTAssertNil(methodCalledMetric.action?.id)
    }

    func testGivenRUMEnabled_whenViewIsActive_telemetryEventsAreLinkedToView() throws {
        // Given
        var config = RUM.Configuration(applicationID: "rum-app-id")
        config.telemetrySampleRate = .maxSampleRate
        RUM.enable(with: config, in: core)

        // When
        RUMMonitor.shared(in: core).startView(key: .mockRandom())

        // Then
        core.telemetry.debug("Debug Telemetry")
        core.telemetry.error("Error Telemetry")
        core.telemetry.metric(name: "Metric Name", attributes: [:], sampleRate: 100)
        core.telemetry.stopMethodCalled(
            core.telemetry.startMethodCalled(operationName: .mockRandom(), callerClass: .mockRandom(), headSampleRate: 100),
            tailSampleRate: 100
        )

        let debugEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryDebugEvent.self)
        let errorEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryErrorEvent.self)

        let debug = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "Debug Telemetry" }))
        XCTAssertEqual(debug.application?.id, "rum-app-id")
        XCTAssertNotNil(debug.session?.id)
        XCTAssertNotNil(debug.view?.id)
        XCTAssertNil(debug.action?.id)

        let error = try XCTUnwrap(errorEvents.first)
        XCTAssertEqual(error.application?.id, "rum-app-id")
        XCTAssertNotNil(error.session?.id)
        XCTAssertNotNil(error.view?.id)
        XCTAssertNil(error.action?.id)

        let metric = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "[Mobile Metric] Metric Name" }))
        XCTAssertEqual(metric.application?.id, "rum-app-id")
        XCTAssertNotNil(metric.session?.id)
        XCTAssertNotNil(metric.view?.id)
        XCTAssertNil(metric.action?.id)

        let methodCalledMetric = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "[Mobile Metric] Method Called" }))
        XCTAssertEqual(methodCalledMetric.application?.id, "rum-app-id")
        XCTAssertNotNil(methodCalledMetric.session?.id)
        XCTAssertNotNil(methodCalledMetric.view?.id)
        XCTAssertNil(methodCalledMetric.action?.id)
    }

    func testGivenRUMEnabled_whenActionIsActive_telemetryEventsAreLinkedToAction() throws {
        // Given
        var config = RUM.Configuration(applicationID: "rum-app-id")
        config.telemetrySampleRate = .maxSampleRate
        RUM.enable(with: config, in: core)

        // When
        RUMMonitor.shared(in: core).startView(key: .mockRandom())
        RUMMonitor.shared(in: core).addAction(type: .tap, name: "tap")

        // Then
        core.telemetry.debug("Debug Telemetry")
        core.telemetry.error("Error Telemetry")
        core.telemetry.metric(name: "Metric Name", attributes: [:], sampleRate: 100)
        core.telemetry.stopMethodCalled(
            core.telemetry.startMethodCalled(operationName: .mockRandom(), callerClass: .mockRandom(), headSampleRate: 100),
            tailSampleRate: 100
        )

        let debugEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryDebugEvent.self)
        let errorEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryErrorEvent.self)

        let debug = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "Debug Telemetry" }))
        XCTAssertEqual(debug.application?.id, "rum-app-id")
        XCTAssertNotNil(debug.session?.id)
        XCTAssertNotNil(debug.view?.id)
        XCTAssertNotNil(debug.action?.id)

        let error = try XCTUnwrap(errorEvents.first)
        XCTAssertEqual(error.application?.id, "rum-app-id")
        XCTAssertNotNil(error.session?.id)
        XCTAssertNotNil(error.view?.id)
        XCTAssertNotNil(error.action?.id)

        let metric = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "[Mobile Metric] Metric Name" }))
        XCTAssertEqual(metric.application?.id, "rum-app-id")
        XCTAssertNotNil(metric.session?.id)
        XCTAssertNotNil(metric.view?.id)
        XCTAssertNotNil(metric.action?.id)

        let methodCalledMetric = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "[Mobile Metric] Method Called" }))
        XCTAssertEqual(methodCalledMetric.application?.id, "rum-app-id")
        XCTAssertNotNil(methodCalledMetric.session?.id)
        XCTAssertNotNil(methodCalledMetric.view?.id)
        XCTAssertNotNil(methodCalledMetric.action?.id)
    }

    func testGivenRUMEnabled_effectiveSampleRateIsComposed() throws {
        // Given
        var config = RUM.Configuration(applicationID: .mockAny())
        config.telemetrySampleRate = 90
        RUM.enable(with: config, in: core)
        let metricsSampleRate: SampleRate = 99
        let headSampleRate: SampleRate = 80.0

        // When
        (0..<100).forEach { _ in
            core.telemetry.debug("Debug Telemetry")
            core.telemetry.error("Error Telemetry")
            core.telemetry.metric(name: "Metric Name", attributes: [:], sampleRate: metricsSampleRate)
            core.telemetry.send(telemetry: .usage(.init(event: .setUser, sampleRate: metricsSampleRate)))
            core.telemetry.stopMethodCalled(
                core.telemetry.startMethodCalled(operationName: .mockRandom(), callerClass: .mockRandom(), headSampleRate: headSampleRate),
                tailSampleRate: metricsSampleRate
            )
        }

        // Then
        let debugEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryDebugEvent.self)
        let errorEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryErrorEvent.self)
        let usageEvents = core.waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryUsageEvent.self)

        XCTAssertGreaterThan(debugEvents.count, 0)
        XCTAssertGreaterThan(errorEvents.count, 0)
        XCTAssertGreaterThan(usageEvents.count, 0)

        let debug = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "Debug Telemetry" }))
        XCTAssertEqual(debug.effectiveSampleRate, Double(config.telemetrySampleRate))

        let error = try XCTUnwrap(errorEvents.first(where: { $0.telemetry.message == "Error Telemetry" }))
        XCTAssertEqual(error.effectiveSampleRate, Double(config.telemetrySampleRate))

        let mobileMetric = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "[Mobile Metric] Metric Name" }))
        XCTAssertEqual(
            mobileMetric.effectiveSampleRate,
            Double(config.telemetrySampleRate.composed(with: metricsSampleRate))
        )

        let methodCalledMetric = try XCTUnwrap(debugEvents.first(where: { $0.telemetry.message == "[Mobile Metric] Method Called" }))
        XCTAssertEqual(
            methodCalledMetric.effectiveSampleRate,
            Double(config.telemetrySampleRate.composed(with: metricsSampleRate).composed(with: headSampleRate))
        )

        let usage = try XCTUnwrap(usageEvents.first)
        XCTAssertEqual(
            usage.effectiveSampleRate,
            Double(config.telemetrySampleRate.composed(with: metricsSampleRate))
        )
    }
}
