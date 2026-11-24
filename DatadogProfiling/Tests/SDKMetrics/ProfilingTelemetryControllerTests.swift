/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)
import XCTest
import TestUtilities
import DatadogInternal
import DatadogMachProfiler
@testable import DatadogProfiling

final class ProfilingTelemetryControllerTests: XCTestCase {
    private let telemetry = TelemetryMock()

    func testContinuousReportsAdvanceTelemetryCycleIndex() throws {
        let controller = ProfilingTelemetryController(telemetry: telemetry)
        controller.sendMemoryDiagnostics(.init(result: .idle, diagnostics: .init()), for: .continuousProfiling)
        controller.sendProfile(durationMs: 1, fileSize: 2, for: .continuousProfiling, profileTypes: [.memory])
        controller.sendProfile(durationMs: 1, fileSize: 2, for: .continuousProfiling, profileTypes: [.cpu, .memory])
        controller.sendProfile(durationMs: 1, fileSize: 2, for: .appLaunch)
        controller.sendProfileDropped(for: .customProfiling)
        controller.sendNoData(durationMs: nil, for: .continuousProfiling, profileTypes: [.memory])

        let sessions = telemetry.messages.compactMap {
            $0.asMetric?.attributes["profiling_session"] as? ProfilingSessionMetric.Attributes
        }
        XCTAssertEqual(sessions.map(\.cycleIndex), [0, 1, 2, nil, nil, 3])
    }

    func testTelemetryResetsMemoryCycleIndexOnlyForANewRUMSession() throws {
        let controller = ProfilingTelemetryController(telemetry: telemetry)
        let firstSession = DatadogContext.mockWith(additionalContext: [RUMCoreContext.mockWith(sessionID: .mockAny())])
        let secondSession = DatadogContext.mockWith(additionalContext: [RUMCoreContext.mockWith(sessionID: .mockAny())])
        for context in [firstSession, firstSession, secondSession] {
            controller.register(context: context)
            controller.sendMemoryDiagnostics(.init(result: .idle, diagnostics: .init()), for: .continuousProfiling)
        }
        let sessions = telemetry.messages.compactMap {
            $0.asMetric?.attributes["profiling_session"] as? ProfilingSessionMetric.Attributes
        }
        XCTAssertEqual(sessions.map(\.cycleIndex), [0, 1, 0])
    }

    func testExpectedMemoryOutcomesDoNotSendAnErrorMessage() throws {
        let controller = ProfilingTelemetryController(telemetry: telemetry)
        for result: MemoryDiagnostics.CaptureResult in [.idle, .discarded, .stopped] {
            controller.sendMemoryDiagnostics(.init(result: result, diagnostics: .init()), for: .continuousProfiling)
            let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
            XCTAssertNil(metric.errorMessage)
            XCTAssertEqual(metric.errorCode, 0)
        }
    }

    func testCPUConfigurationIsIncludedOnlyForReportsContainingCPU() throws {
        let configuration = ConfigurationMetric(bufferSize: 123)
        let controller = ProfilingTelemetryController(telemetry: telemetry, configMetric: configuration)
        let profileTypes: [[ProfilingSessionMetric.ProfileType]] = [[.cpu], [.memory], [.cpu, .memory]]

        for types in profileTypes {
            controller.sendProfile(durationMs: 1, fileSize: 2, for: .continuousProfiling, profileTypes: types)
            let metric = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
            let encodedConfiguration = metric.attributes[ConfigurationMetric.Constants.configurationKey] as? ConfigurationMetric
            if types.contains(.cpu) {
                XCTAssertEqual(encodedConfiguration?.bufferSize, 123)
            } else {
                XCTAssertNil(encodedConfiguration)
            }
        }
    }

    func testMemoryDiagnosticsEnrichProfilingSessionWithNumericFields() throws {
        var native = dd_memory_profiler_diagnostics_t()
        native.sampled_allocations = 11
        native.reentrant_skips = 12
        native.window.recorded_allocations = 13
        native.window.dropped_alloc_records = 14
        native.window.peak_recorded_allocations = 15
        native.window.live_set.occupancy = 16
        native.window.live_set.peak_occupancy = 17
        native.window.live_set.dropped_samples = 18
        native.window.live_set.tombstones = 19
        native.window.live_set.max_probe_length = 20
        native.window.live_set.table_bytes = 21
        native.window.live_set.snapshot_bytes_high_water = 22
        native.recorder_storage_bytes = 23
        native.encoder_storage_bytes = 24
        native.swift_install_result = 25
        native.objc_install_result = 26
        native.window.live_set.probe_count = 2
        native.window.live_set.total_probe_length = 7
        let memory = MemoryDiagnostics(result: .idle, diagnostics: native)
        let controller = ProfilingTelemetryController(sampleRate: 37, telemetry: telemetry)
        controller.sendMemoryDiagnostics(memory, for: .continuousProfiling)

        let sent = try XCTUnwrap(telemetry.messages.lastMetric(named: "Profiling Session"))
        XCTAssertEqual(sent.sampleRate, 37)
        XCTAssertNil(sent.attributes[ConfigurationMetric.Constants.configurationKey])
        let session = try XCTUnwrap(sent.attributes["profiling_session"] as? ProfilingSessionMetric.Attributes)
        XCTAssertEqual(session.profileTypes, ["memory"])
        let diagnostics = try XCTUnwrap(sent.attributes["profiling_diagnostics"] as? ProfilingDiagnostics)
        XCTAssertNil(diagnostics.cpu)
        let encoded = try JSONEncoder().encode(XCTUnwrap(diagnostics.memory))
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let expected: [String: UInt64] = [
            "sampled_allocations": 11,
            "reentrant_skips": 12,
            "recorded_allocations": 13,
            "dropped_alloc_records": 14,
            "live_occupancy": 16,
            "peak_live_occupancy": 17,
            "dropped_samples": 18,
            "tombstones": 19,
            "max_probe_length": 20,
            "recorder_storage_bytes": 23,
            "encoder_storage_bytes": 24,
            "swift_install_result": 25,
            "objc_install_result": 26,
            "payload_bytes": 0
        ]
        for (key, value) in expected {
            XCTAssertEqual((values[key] as? NSNumber)?.uint64Value, value, key)
        }
        XCTAssertEqual(values["capture_result"] as? String, "idle")
        XCTAssertNil(values["total_allocations"])
        for key in ["outcome", "sampled", "peak_recorded_allocations", "table_bytes", "snapshot_bytes_high_water"] {
            XCTAssertNil(values[key], key)
        }
        XCTAssertEqual(values["average_probe_length"] as? Double, 3.5)
        XCTAssertTrue(values.filter { $0.key != "capture_result" }.values.allSatisfy { $0 is NSNumber })
        XCTAssertEqual(telemetry.messages.count, 1)
    }

    func testMemoryFailureDoesNotUseCPUStatusAndAdvancesTelemetryCycleIndex() throws {
        let controller = ProfilingTelemetryController(telemetry: telemetry)
        controller.sendMemoryDiagnostics(
            .init(result: .startFailed, diagnostics: .init()),
            for: .continuousProfiling
        )
        let failure = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(failure.profileTypes, ["memory"])
        XCTAssertEqual(failure.errorCode, ProfilingSessionMetric.ErrorCode.executionFailed.rawValue)
        XCTAssertEqual(failure.cycleIndex, 0)
        XCTAssertEqual(failure.errorMessage, "Memory profile: start_failed.")

        controller.sendProfile(durationMs: 1, fileSize: 2, for: .continuousProfiling)
        let cpu = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(cpu.profileTypes, ["cpu"])
        XCTAssertEqual(cpu.cycleIndex, 1)
    }

    func testTrackingAllocationFailure_sendsExecutionFailedWithTelemetryMetadata() throws {
        // Given
        let configMetric = ConfigurationMetric(bufferSize: 123)
        let controller = ProfilingTelemetryController(sampleRate: 37, telemetry: telemetry, configMetric: configMetric)

        // When
        controller.send(
            .allocationFailure(
                startReason: .applicationLaunch,
                status: .error(reason: .memoryAllocationFailed),
                appStartInfo: "user_launch"
            )
        )

        // Then
        XCTAssertEqual(telemetry.messages.count, 1)
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertNil(metric.cycleIndex)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertEqual(metric.errorCode, 4)
        XCTAssertEqual(metric.errorMessage, ProfilingSessionMetric.Constants.allocationFailureErrorMessage)
        XCTAssertEqual(metric.appStartInfo, "user_launch")

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 37.0)
        let configuration = try XCTUnwrap(
            metricTelemetry.attributes[ConfigurationMetric.Constants.configurationKey] as? ConfigurationMetric
        )
        XCTAssertEqual(configuration.bufferSize, 123)
        XCTAssertNotNil(
            metricTelemetry.attributes[ProfilingDiagnostics.Constants.diagnosticsKey] as? ProfilingDiagnostics
        )
    }

    func testTrackingProfilingSessionMetric_whileAppLaunchProfilingIsRunning() throws {
        // Given
        let durationMs = Int64(123)
        let fileSize = Int64(1_000_000)
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(
            ProfilingSessionMetric(
                startReason: .applicationLaunch,
                status: .running,
                durationMs: durationMs,
                fileSize: fileSize,
                appStartInfo: "user_launch"
            )
        )

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertEqual(metric.duration, durationMs)
        XCTAssertEqual(metric.fileSize, fileSize)
        XCTAssertNil(metric.stoppedReason)
        XCTAssertEqual(metric.errorCode, ProfilingSessionMetric.ErrorCode.none.rawValue)
        XCTAssertNil(metric.errorMessage)
        XCTAssertNil(metric.cycleIndex)
        XCTAssertEqual(metric.appStartInfo, "user_launch")

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingProfilingSessionMetric_afterAppLaunchProfilingManuallyStopped() throws {
        // Given
        let durationMs = Int64(123)
        let fileSize = Int64(1_000_000)
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(
            ProfilingSessionMetric(
                startReason: .applicationLaunch,
                status: .stopped(reason: .manual),
                durationMs: durationMs,
                fileSize: fileSize,
                appStartInfo: "background_launch"
            )
        )

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertEqual(metric.duration, durationMs)
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
                durationMs: nil,
                cycleIndex: nil,
                appStartInfo: "prewarming"
            )
        )

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertEqual(metric.errorCode, ProfilingSessionMetric.ErrorCode.none.rawValue)
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
                cycleIndex: nil,
                appStartInfo: "uncertain"
            )
        )

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.applicationLaunch.rawValue)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertEqual(metric.errorCode, ProfilingSessionMetric.ErrorCode.none.rawValue)
        XCTAssertFalse(metric.errorMessage?.isEmpty ?? true)
        XCTAssertEqual(metric.appStartInfo, "uncertain")

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingProfilingSessionMetric_whileContinuousProfilingIsRunning() throws {
        // Given
        let durationMs = Int64(123)
        let fileSize = Int64(1_000_000)
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.send(
            ProfilingSessionMetric(
                startReason: .continuous,
                status: .running,
                durationMs: durationMs,
                fileSize: fileSize,
                cycleIndex: 0
            )
        )

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.continuous.rawValue)
        XCTAssertEqual(metric.duration, durationMs)
        XCTAssertEqual(metric.fileSize, fileSize)
        XCTAssertEqual(metric.cycleIndex, 0)
        XCTAssertNil(metric.stoppedReason)
        XCTAssertEqual(metric.errorCode, ProfilingSessionMetric.ErrorCode.none.rawValue)
        XCTAssertNil(metric.errorMessage)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingProfilingSessionMetric_whenProfileIsDropped() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.sendProfileDropped(for: .customProfiling)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.rumOperation.rawValue)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertEqual(metric.errorCode, ProfilingSessionMetric.ErrorCode.none.rawValue)
        XCTAssertEqual(metric.errorMessage, ProfilingSessionMetric.Constants.noProfiledEventsErrorMessage)

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingProfilingSessionMetric_whenProfileIsDroppedBecauseQuotaRejected() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.sendProfileDropped(for: .customProfiling, reason: .quotaRejected(.quotaExceeded))

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.rumOperation.rawValue)
        XCTAssertNil(metric.duration)
        XCTAssertNil(metric.fileSize)
        XCTAssertEqual(metric.errorCode, ProfilingSessionMetric.ErrorCode.none.rawValue)
        XCTAssertEqual(
            metric.errorMessage,
            "\(ProfilingSessionMetric.Constants.quotaErrorMessage) Quota reason: quota_exceeded."
        )

        let metricTelemetry = try XCTUnwrap(telemetry.messages.lastMetric(named: ProfilingSessionMetric.Constants.name))
        XCTAssertEqual(metricTelemetry.sampleRate, 20.0)
    }

    func testTrackingProfilingSessionMetric_attachesCPUDiagnostics() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)
        let diagnosticsKey = ProfilingDiagnostics.Constants.diagnosticsKey

        // When
        controller.sendProfile(durationMs: 1, fileSize: 2, for: .continuousProfiling)
        controller.sendProfileDropped(for: .customProfiling)

        // Then
        let diagnostics = telemetry.messages.compactMap { message in
            message.asMetric?.attributes[diagnosticsKey] as? ProfilingDiagnostics
        }
        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertEqual(diagnostics.first?.cpu?.droppedBatchCount, 0)
        XCTAssertEqual(diagnostics.first?.cpu?.droppedSampleCount, 0)
        XCTAssertEqual(diagnostics.first?.cpu?.maxPendingBytes, 0)
        let encoded = try JSONEncoder().encode(XCTUnwrap(diagnostics.first))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(fields["cpu"])
        XCTAssertNil(fields["aggregation"])
    }

    func testSendProfile_usesContinuousStartReason_forContinuousOperation() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.sendProfile(durationMs: 1, fileSize: 2, for: .continuousProfiling)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.profilingSessionMetric)
        XCTAssertEqual(metric.startReason, ProfilingSessionMetric.StartReason.continuous.rawValue)
        XCTAssertEqual(metric.cycleIndex, 0)
    }

    func testSendProfile_usesRumOperationStartReason_forCustomOperation() throws {
        // Given
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        controller.sendProfile(durationMs: 1, fileSize: 2, for: .customProfiling)
        controller.sendNoData(durationMs: 1, for: .customProfiling)

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
        controller.sendProfile(durationMs: 1, fileSize: 2, for: .continuousProfiling)
        controller.sendProfile(durationMs: 3, fileSize: 4, for: .continuousProfiling)

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
        let durationMs = Int64(123)
        let controller = ProfilingTelemetryController(telemetry: telemetry)

        // When
        (0..<iterations).forEach {
            controller.send(
                ProfilingSessionMetric(
                    startReason: .continuous,
                    status: status,
                    durationMs: durationMs,
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
            XCTAssertEqual(metric.duration, durationMs)
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
#endif // !os(watchOS) && !os(macOS)
