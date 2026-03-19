/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogProfiling

final class ProfilingTelemetryControllerTests: XCTestCase {
    private let telemetry = TelemetryMock()

    func testTrackingAppLaunchMetric_whileProfilingIsRunning() throws {
        // Given
        let status: ProfilingContext.Status = .running
        let duration = Int64(123_000_000)
        let fileSize = Int64(1_000_000)
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(metric: AppLaunchMetric(status: status, durationNs: duration, fileSize: fileSize))

        // Then
        let metric = try XCTUnwrap(telemetry.messages.appLaunchMetric)
        XCTAssertEqual(metric.duration, duration)
        XCTAssertEqual(metric.fileSize, fileSize)
        XCTAssertNil(metric.stoppedReason)
        XCTAssertNil(metric.errorMessage)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: AppLaunchMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingAppLaunchMetric_afterProfilingManuallyStopped() throws {
        // Given
        let status: ProfilingContext.Status = .stopped(reason: .manual)
        let duration = Int64(123_000_000)
        let fileSize = Int64(1_000_000)
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(metric: AppLaunchMetric(status: status, durationNs: duration, fileSize: fileSize))

        // Then
        let metric = try XCTUnwrap(telemetry.messages.appLaunchMetric)
        XCTAssertEqual(metric.duration, duration)
        XCTAssertEqual(metric.fileSize, fileSize)
        XCTAssertEqual(metric.stoppedReason, ProfilingContext.Status.StopReason.manual.rawValue)
        XCTAssertNil(metric.errorMessage)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: AppLaunchMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingStatusNotHandled() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(metric: AppLaunchMetric.statusNotHandled)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.appLaunchMetric)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertFalse(metric.errorMessage?.isEmpty ?? true)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: AppLaunchMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingNoDataDecoded() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(metric: AppLaunchMetric.noData)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.appLaunchMetric)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertFalse(metric.errorMessage?.isEmpty ?? true)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: AppLaunchMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingNoProfileCaptured() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(metric: AppLaunchMetric.noProfile)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.appLaunchMetric)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertFalse(metric.errorMessage?.isEmpty ?? true)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: AppLaunchMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingMultipleAppLaunchMetrics() throws {
        // Given
        let iterations = 10
        let status: ProfilingContext.Status = .running
        let duration = Int64(123_000_000)
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        (0..<iterations).forEach {
            controller.send(metric: AppLaunchMetric(status: status, durationNs: duration, fileSize: Int64($0)))
        }

        // Then
        XCTAssertEqual(telemetry.messages.count, iterations)
        try (0..<iterations).forEach {
            let metric = try XCTUnwrap(telemetry.messages[$0]
                .asMetric?.attributes[AppLaunchMetric.Constants.appLaunchKey] as? AppLaunchMetric.Attributes)
            XCTAssertEqual(metric.duration, duration)
            XCTAssertEqual(metric.fileSize, Int64($0))
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
#endif // !os(watchOS)
