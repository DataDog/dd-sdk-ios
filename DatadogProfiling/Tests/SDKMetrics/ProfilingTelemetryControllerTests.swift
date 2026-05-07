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

    func testTrackingProfilingSessionMetric_whileAppLaunchProfilingIsRunning() throws {
        // Given
        let duration = Int64(123_000_000)
        let fileSize = Int64(1_000_000)
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(
            ProfilingSessionMetric(
                startReason: .applicationLaunch,
                status: .running,
                durationNs: duration,
                fileSize: fileSize,
                appStartInfo: "user_launch"
            )
        )

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertEqual(metric.duration, duration)
        XCTAssertEqual(metric.fileSize, fileSize)
        XCTAssertNil(metric.stoppedReason)
        XCTAssertNil(metric.errorCode)
        XCTAssertNil(metric.errorMessage)
        XCTAssertNil(metric.cycleIndex)
        XCTAssertEqual(metric.appStartInfo, "user_launch")

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingProfilingSessionMetric_afterAppLaunchProfilingManuallyStopped() throws {
        // Given
        let duration = Int64(123_000_000)
        let fileSize = Int64(1_000_000)
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(
            ProfilingSessionMetric(
                startReason: .applicationLaunch,
                status: .stopped(reason: .manual),
                durationNs: duration,
                fileSize: fileSize,
                appStartInfo: "background_launch"
            )
        )

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertEqual(metric.duration, duration)
        XCTAssertEqual(metric.fileSize, fileSize)
        XCTAssertEqual(metric.stoppedReason, ProfilingContext.Status.StopReason.manual.rawValue)
        XCTAssertNil(metric.errorMessage)
        XCTAssertEqual(metric.appStartInfo, "background_launch")

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingNoDataDecoded() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(
            ProfilingSessionMetric.noData(
                startReason: .applicationLaunch,
                status: .stopped(reason: .manual),
                durationNs: nil,
                errorCode: 3,
                cycleIndex: nil,
                appStartInfo: "prewarming"
            )
        )

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertEqual(metric.errorCode, 3)
        XCTAssertFalse(metric.errorMessage?.isEmpty ?? true)
        XCTAssertEqual(metric.appStartInfo, "prewarming")

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingNoProfileCaptured() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(
            ProfilingSessionMetric.noProfile(
                startReason: .applicationLaunch,
                status: .stopped(reason: .notStarted),
                errorCode: 1,
                cycleIndex: nil,
                appStartInfo: "uncertain"
            )
        )

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertEqual(metric.errorCode, 1)
        XCTAssertFalse(metric.errorMessage?.isEmpty ?? true)
        XCTAssertEqual(metric.appStartInfo, "uncertain")

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingProfilingSessionMetric_whileContinuousProfilingIsRunning() throws {
        // Given
        let duration = Int64(123_000_000)
        let fileSize = Int64(1_000_000)
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(
            ProfilingSessionMetric(
                startReason: .continuous,
                status: .running,
                durationNs: duration,
                fileSize: fileSize,
                cycleIndex: 0
            )
        )

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.continuous.rawValue)
        XCTAssertEqual(metric.duration, duration)
        XCTAssertEqual(metric.fileSize, fileSize)
        XCTAssertEqual(metric.cycleIndex, 0)
        XCTAssertNil(metric.stoppedReason)
        XCTAssertNil(metric.errorCode)
        XCTAssertNil(metric.errorMessage)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingProfilingSessionMetric_whenProfileIsNotWritten() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.sendProfileNotWritten(for: .customProfiling)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.rumOperation.rawValue)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertNil(metric.errorCode)
        XCTAssertEqual(metric.errorMessage, ProfilingSessionMetric.Constants.profileNotWrittenErrorMessage)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingProfilingSessionMetric_attachesAggregationDiagnostics() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)
        let diagnosticsKey = AggregationDiagnosticsMetric.Constants.diagnosticsKey

        // When
        controller.sendProfile(durationNs: 1, fileSize: 2, for: .continuousProfiling)
        controller.sendProfileNotWritten(for: .customProfiling)

        // Then
        let diagnostics = telemetry.messages.compactMap { message in
            message.asMetric?.attributes[diagnosticsKey] as? AggregationDiagnosticsMetric.Attributes
        }
        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertEqual(diagnostics.first?.aggregation.droppedBatchCount, 0)
        XCTAssertEqual(diagnostics.first?.aggregation.droppedSampleCount, 0)
        XCTAssertEqual(diagnostics.first?.aggregation.maxPendingBytes, 0)
    }

    func testSendProfile_usesContinuousStartReason_forContinuousOperation() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.sendProfile(durationNs: 1, fileSize: 2, for: .continuousProfiling)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.continuous.rawValue)
        XCTAssertEqual(metric.cycleIndex, 0)
    }

    func testSendProfile_usesRumOperationStartReason_forCustomOperation() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.sendProfile(durationNs: 1, fileSize: 2, for: .customProfiling)
        controller.sendNoData(durationNs: 1, for: .customProfiling)

        // Then
        let firstMetric = try XCTUnwrap(telemetry.messages[0]
            .asMetric?.attributes[ProfilingSessionMetric.Constants.sessionKey] as? ProfilingSessionMetric.Attributes)
        let secondMetric = try XCTUnwrap(telemetry.messages[1]
            .asMetric?.attributes[ProfilingSessionMetric.Constants.sessionKey] as? ProfilingSessionMetric.Attributes)
        XCTAssertEqual(firstMetric.startReason, ProfilingSessionMetric.StartReason.rumOperation.rawValue)
        XCTAssertEqual(secondMetric.startReason, ProfilingSessionMetric.StartReason.rumOperation.rawValue)
        XCTAssertNil(firstMetric.cycleIndex)
        XCTAssertNil(secondMetric.cycleIndex)
        XCTAssertEqual(secondMetric.errorMessage, ProfilingSessionMetric.Constants.noDataErrorMessage)
    }

    func testSendNoProfile_usesApplicationLaunchStartReason_forAppLaunchOperation() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)
        controller.register(context: DatadogContext.mockWith(launchInfo: .mockWith(launchReason: .userLaunch)))

        // When
        controller.sendNoProfile(for: .appLaunch)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertNil(metric.cycleIndex)
        XCTAssertEqual(metric.appStartInfo, "user_launch")
        XCTAssertEqual(metric.errorMessage, ProfilingSessionMetric.Constants.noProfileErrorMessage)
    }

    func testSendProfile_incrementsCycleIndex_forContinuousOperation() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.sendProfile(durationNs: 1, fileSize: 2, for: .continuousProfiling)
        controller.sendProfile(durationNs: 3, fileSize: 4, for: .continuousProfiling)

        // Then
        let firstMetric = try XCTUnwrap(telemetry.messages[0]
            .asMetric?.attributes[ProfilingSessionMetric.Constants.sessionKey] as? ProfilingSessionMetric.Attributes)
        let secondMetric = try XCTUnwrap(telemetry.messages[1]
            .asMetric?.attributes[ProfilingSessionMetric.Constants.sessionKey] as? ProfilingSessionMetric.Attributes)
        XCTAssertEqual(firstMetric.cycleIndex, 0)
        XCTAssertEqual(secondMetric.cycleIndex, 1)
    }

    func testTrackingMultipleProfilingSessionMetrics() throws {
        // Given
        let iterations = 10
        let status: ProfilingContext.Status = .running
        let duration = Int64(123_000_000)
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        (0..<iterations).forEach {
            controller.send(
                ProfilingSessionMetric(
                    startReason: .continuous,
                    status: status,
                    durationNs: duration,
                    fileSize: Int64($0),
                    cycleIndex: $0
                )
            )
        }

        // Then
        XCTAssertEqual(telemetry.messages.count, iterations)
        try (0..<iterations).forEach {
            let metric = try XCTUnwrap(telemetry.messages[$0]
                .asMetric?.attributes[ProfilingSessionMetric.Constants.sessionKey] as? ProfilingSessionMetric.Attributes)
            XCTAssertEqual(metric.duration, duration)
            XCTAssertEqual(metric.fileSize, Int64($0))
            XCTAssertEqual(metric.cycleIndex, $0)
        }
    }
}

// MARK: - Helpers

private extension Array where Element == TelemetryMessage {
    var profilingSessionMetric: ProfilingSessionMetric.Attributes? {
        lastMetric(named: ProfilingSessionMetric.Constants.name)?
            .attributes[ProfilingSessionMetric.Constants.sessionKey] as? ProfilingSessionMetric.Attributes
    }
}
#endif // !os(watchOS)
