/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM

class RUMSessionEndedMetricIntegrationTests: XCTestCase {
    private let dateProvider = DateProviderMock()
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var rumConfig: RUM.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        core = DatadogCoreProxy()
        core.context = .mockWith(
            launchTime: .mockWith(launchDate: dateProvider.now),
            applicationStateHistory: .mockAppInForeground(since: dateProvider.now)
        )
        rumConfig = RUM.Configuration(applicationID: .mockAny())
        rumConfig.telemetrySampleRate = 100
        rumConfig.metricsTelemetrySampleRate = 100
        rumConfig.dateProvider = dateProvider
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        rumConfig = nil
    }

    // MARK: - Conditions For Sending The Metric

    func testWhenSessionEndsWithStopAPI() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")

        // When
        monitor.stopSession()

        // Then
        let metricAttributes = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent()?.attributes)
        XCTAssertTrue(metricAttributes.wasStopped)
    }

    func testWhenSessionEndsDueToInactivityTimeout() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key1", name: "View1")

        // When
        dateProvider.now += RUMSessionScope.Constants.sessionTimeoutDuration + 1.seconds
        monitor.startView(key: "key2", name: "View2")

        // Then
        let metricAttributes = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent()?.attributes)
        XCTAssertFalse(metricAttributes.wasStopped)
    }

    func testWhenSessionReachesMaxDuration() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")

        // When
        let deadline = dateProvider.now + RUMSessionScope.Constants.sessionMaxDuration * 1.5
        while dateProvider.now < deadline {
            monitor.addAction(type: .custom, name: "action")
            dateProvider.now += RUMSessionScope.Constants.sessionTimeoutDuration - 1.seconds
        }

        // Then
        let metricAttributes = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent()?.attributes)
        XCTAssertFalse(metricAttributes.wasStopped)
    }

    func testWhenSessionIsNotSampled_thenMetricIsNotSent() throws {
        rumConfig.sessionSampleRate = 0
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")

        // When
        monitor.stopSession()

        // Then
        let events = core.waitAndReturnEventsData(ofFeature: RUMFeature.name, timeout: .now() + 0.5)
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Reporting Session Attributes

    func testReportingSessionInformation() throws {
        var currentSessionID: String?
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")
        monitor.currentSessionID { currentSessionID = $0 }
        monitor.stopView(key: "key")

        // When
        monitor.stopSession()

        // Then
        let metric = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent())
        let expectedSessionID = try XCTUnwrap(currentSessionID)
        XCTAssertEqual(metric.session?.id, expectedSessionID.lowercased())
        XCTAssertEqual(metric.attributes?.hasBackgroundEventsTrackingEnabled, rumConfig.trackBackgroundEvents)
    }

    func testTrackingSessionDuration() throws {
        let startTime = dateProvider.now
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        dateProvider.now += 5.seconds
        monitor.startView(key: "key1", name: "View1")
        dateProvider.now += 5.seconds
        monitor.startView(key: "key2", name: "View2")
        dateProvider.now += 5.seconds
        monitor.startView(key: "key3", name: "View3")
        dateProvider.now += 5.seconds
        monitor.stopView(key: "key3")

        // When
        monitor.stopSession()

        // Then
        let expectedDuration = dateProvider.now.timeIntervalSince(startTime)
        let metricAttributes = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent()?.attributes)
        XCTAssertEqual(metricAttributes.duration, expectedDuration.toInt64Nanoseconds)
    }

    func testTrackingViewsCount() throws {
        rumConfig.trackBackgroundEvents = true // enable tracking "Background" view
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        (0..<3).forEach { _ in
            // Simulate app in foreground:
            core.context = .mockWith(applicationStateHistory: .mockAppInForeground(since: dateProvider.now))

            // Track 2 distinct views:
            dateProvider.now += 5.seconds
            monitor.startView(key: "key1", name: "View1")
            dateProvider.now += 5.seconds
            monitor.startView(key: "key2", name: "View2")
            dateProvider.now += 5.seconds
            monitor.stopView(key: "key2")

            // Simulate app in background:
            core.context = .mockWith(applicationStateHistory: .mockAppInBackground(since: dateProvider.now))

            // Track resource without view:
            dateProvider.now += 1.seconds
            monitor.startResource(resourceKey: "resource", url: .mockAny())
            dateProvider.now += 1.seconds
            monitor.stopResource(resourceKey: "resource", response: .mockAny())
        }

        // When
        monitor.stopSession()

        // Then
        let metricAttributes = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent()?.attributes)
        XCTAssertEqual(metricAttributes.viewsCount.total, 10)
        XCTAssertEqual(metricAttributes.viewsCount.applicationLaunch, 1)
        XCTAssertEqual(metricAttributes.viewsCount.background, 3)
        XCTAssertEqual(metricAttributes.viewsCount.byInstrumentation, ["manual": 6])
    }

    func testTrackingSDKErrors() throws {
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")

        core.flush()
        (0..<9).forEach { _ in core.telemetry.error(id: "id1", message: .mockAny(), kind: "kind1", stack: .mockAny()) }
        (0..<8).forEach { _ in core.telemetry.error(id: "id2", message: .mockAny(), kind: "kind2", stack: .mockAny()) }
        (0..<7).forEach { _ in core.telemetry.error(id: "id3", message: .mockAny(), kind: "kind3", stack: .mockAny()) }
        (0..<6).forEach { _ in core.telemetry.error(id: "id4", message: .mockAny(), kind: "kind4", stack: .mockAny()) }
        (0..<5).forEach { _ in core.telemetry.error(id: "id5", message: .mockAny(), kind: "kind5", stack: .mockAny()) }
        (0..<4).forEach { _ in core.telemetry.error(id: "id6", message: .mockAny(), kind: "kind6", stack: .mockAny()) }
        core.flush()

        // When
        monitor.stopSession()

        // Then
        let metricAttributes = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent()?.attributes)
        XCTAssertEqual(metricAttributes.sdkErrorsCount.total, 39, "It should count all SDK errors")
        XCTAssertEqual(
            metricAttributes.sdkErrorsCount.byKind,
            ["kind1": 9, "kind2": 8, "kind3": 7, "kind4": 6, "kind5": 5],
            "It should report TOP 5 error kinds"
        )
    }

    func testTrackingNTPOffset() throws {
        let offsetAtStart: TimeInterval = .mockRandom(min: -10, max: 10)
        let offsetAtEnd: TimeInterval = .mockRandom(min: -10, max: 10)

        core.context.serverTimeOffset = offsetAtStart
        RUM.enable(with: rumConfig, in: core)

        // Given
        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "key", name: "View")

        // When
        core.context.serverTimeOffset = offsetAtEnd
        monitor.stopSession()

        // Then
        let metric = try XCTUnwrap(core.waitAndReturnSessionEndedMetricEvent())
        XCTAssertEqual(metric.attributes?.ntpOffset.atStart, offsetAtStart.toInt64Milliseconds)
        XCTAssertEqual(metric.attributes?.ntpOffset.atEnd, offsetAtEnd.toInt64Milliseconds)
    }
}

// MARK: - Helpers

private extension DatadogCoreProxy {
    func waitAndReturnSessionEndedMetricEvent() -> TelemetryDebugEvent? {
        let events = waitAndReturnEvents(ofFeature: RUMFeature.name, ofType: TelemetryDebugEvent.self)
        return events.first(where: { $0.telemetry.message == "[Mobile Metric] \(SessionEndedMetric.Constants.name)" })
    }
}

private extension TelemetryDebugEvent {
    var attributes: SessionEndedMetric.Attributes? {
        return telemetry.telemetryInfo[SessionEndedMetric.Constants.rseKey] as? SessionEndedMetric.Attributes
    }
}

