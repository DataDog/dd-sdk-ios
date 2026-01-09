/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

final class AppLaunchMetricControllerTests: XCTestCase {
    private let telemetry = TelemetryMock()

    func testTrackingAppLaunchMetric() throws {
        // Given
        let datadogContext: DatadogContext = .mockRandom()
        let vitalEvent: RUMVitalAppLaunchEvent = .mockWith(
            vital: .mockWith(
                appLaunchMetric: .ttid,
                isPrewarmed: datadogContext.launchInfo.launchReason == .prewarming
            )
        )
        let coldStartRule: ColdStartRule = .appUpdate
        let controller = AppLaunchMetricController(telemetry: telemetry)

        // When
        controller.track(coldStartRule: coldStartRule)
        controller.track(ttidEvent: vitalEvent, context: datadogContext)
        controller.sendMetric()

        // Then
        let metric = try XCTUnwrap(telemetry.messages.appLaunchMetric)
        XCTAssertEqual(metric.ttidDurationNs, vitalEvent.vital.duration.dd.toInt64Nanoseconds)
        XCTAssertEqual(metric.startupType, vitalEvent.vital.startupType?.rawValue)
        XCTAssertEqual(metric.coldStartRule, coldStartRule.rawValue)
        XCTAssertEqual(metric.isPrewarmed, vitalEvent.vital.isPrewarmed)
        XCTAssertEqual(metric.launchReason, datadogContext.launchInfo.launchReason)
        XCTAssertEqual(metric.taskPolicyRole, datadogContext.launchInfo.raw.taskPolicyRole)
        XCTAssertEqual(metric.pois.count, 5)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: AppLaunchMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingLargeTTID() throws {
        // Given
        let datadogContext: DatadogContext = .mockRandom()
        let controller = AppLaunchMetricController(telemetry: telemetry)
        let duration: TimeInterval = 1_000

        // When
        controller.send(metric: .largeTTID(context: datadogContext, duration: duration))

        // Then
        let metric = try XCTUnwrap(telemetry.messages.appLaunchMetric)
        XCTAssertEqual(metric.ttidDurationNs, duration.dd.toInt64Nanoseconds)
        XCTAssertEqual(metric.launchReason, datadogContext.launchInfo.launchReason)
        XCTAssertEqual(metric.taskPolicyRole, datadogContext.launchInfo.raw.taskPolicyRole)
        XCTAssertEqual(metric.isPrewarmed, datadogContext.launchInfo.launchReason == .prewarming)
        XCTAssertEqual(metric.pois.count, 5)
        XCTAssertFalse(metric.errorMessage?.isEmpty ?? true)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: AppLaunchMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingLaunchNotSupported() throws {
        // Given
        let datadogContext: DatadogContext = .mockRandom()
        let controller = AppLaunchMetricController(telemetry: telemetry)
        let duration: TimeInterval = 1_000

        // When
        controller.send(metric: .launchNotSupported(context: datadogContext, duration: duration))

        // Then
        let metric = try XCTUnwrap(telemetry.messages.appLaunchMetric)
        XCTAssertEqual(metric.ttidDurationNs, duration.dd.toInt64Nanoseconds)
        XCTAssertEqual(metric.launchReason, datadogContext.launchInfo.launchReason)
        XCTAssertEqual(metric.taskPolicyRole, datadogContext.launchInfo.raw.taskPolicyRole)
        XCTAssertEqual(metric.isPrewarmed, datadogContext.launchInfo.launchReason == .prewarming)
        XCTAssertEqual(metric.pois.count, 5)
        XCTAssertFalse(metric.errorMessage?.isEmpty ?? true)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: AppLaunchMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingAppLaunchMetric_withTTFDRecordedFirst() throws {
        // Given
        let datadogContext: DatadogContext = .mockRandom()
        let vitalEvent: RUMVitalAppLaunchEvent = .mockAny()
        let controller = AppLaunchMetricController(telemetry: telemetry)
        let ttfdDuration: Int64 = 1_000

        // When
        controller.track(ttidEvent: vitalEvent, context: datadogContext)
        controller.trackTTFD(duration: ttfdDuration)
        controller.sendMetric()

        // Then
        let metric = try XCTUnwrap(telemetry.messages.appLaunchMetric)
        XCTAssertEqual(metric.ttidDurationNs, vitalEvent.vital.duration.dd.toInt64Nanoseconds)
        XCTAssertEqual(metric.startupType, vitalEvent.vital.startupType?.rawValue)
        XCTAssertEqual(metric.launchReason, datadogContext.launchInfo.launchReason)
        XCTAssertEqual(metric.taskPolicyRole, datadogContext.launchInfo.raw.taskPolicyRole)
        XCTAssertEqual(metric.pois.count, 5)
        XCTAssertEqual(metric.ttfdDurationNs, ttfdDuration)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: AppLaunchMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingMoreThanOneTTID() throws {
        // Given
        let datadogContext: DatadogContext = .mockRandom()
        let vitalEvent: RUMVitalAppLaunchEvent = .mockAny()
        let controller = AppLaunchMetricController(telemetry: telemetry)

        // When
        controller.track(ttidEvent: vitalEvent, context: datadogContext)
        controller.incrementTTIDCounter()
        controller.incrementTTIDCounter()
        controller.sendMetric()

        // Then
        let metric = try XCTUnwrap(telemetry.messages.appLaunchMetric)
        XCTAssertEqual(metric.ttidDurationNs, vitalEvent.vital.duration.dd.toInt64Nanoseconds)
        XCTAssertEqual(metric.startupType, vitalEvent.vital.startupType?.rawValue)
        XCTAssertEqual(metric.launchReason, datadogContext.launchInfo.launchReason)
        XCTAssertEqual(metric.taskPolicyRole, datadogContext.launchInfo.raw.taskPolicyRole)
        XCTAssertEqual(metric.pois.count, 5)
        XCTAssertEqual(metric.extraTTIDsCount, 2)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: AppLaunchMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingMultipleAppLaunchMetrics() throws {
        // Given
        let iterations = 10
        let datadogContext: DatadogContext = .mockRandom()
        let vitalEvent: RUMVitalAppLaunchEvent = .mockAny()
        let controller = AppLaunchMetricController(telemetry: telemetry)
        let appLaunchMetric = try XCTUnwrap(AppLaunchMetric(vitalEvent: vitalEvent, context: datadogContext))

        // When
        (0..<iterations).forEach { _ in
            controller.send(metric: appLaunchMetric)
        }

        // Then
        XCTAssertEqual(telemetry.messages.count, iterations)
        try (0..<iterations).forEach {
            let metric = try XCTUnwrap(telemetry.messages[$0]
                .asMetric?.attributes[AppLaunchMetric.Constants.appLaunchKey] as? AppLaunchMetric.Attributes)

            XCTAssertEqual(metric.ttidDurationNs, vitalEvent.vital.duration.dd.toInt64Nanoseconds)
            XCTAssertEqual(metric.startupType, vitalEvent.vital.startupType?.rawValue)
            XCTAssertEqual(metric.launchReason, datadogContext.launchInfo.launchReason)
            XCTAssertEqual(metric.taskPolicyRole, datadogContext.launchInfo.raw.taskPolicyRole)
            XCTAssertEqual(metric.pois.count, 5)
        }
    }
}

// MARK: - Helpers

private extension Array where Element == TelemetryMessage {
    var appLaunchMetric: AppLaunchMetric.Attributes? {
        lastMetric(named: AppLaunchMetric.Constants.name)?
            .attributes[AppLaunchMetric.Constants.appLaunchKey] as? AppLaunchMetric.Attributes
    }
}
