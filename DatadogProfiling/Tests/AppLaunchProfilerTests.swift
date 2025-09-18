/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogProfiling
import DatadogMachProfiler

final class AppLaunchProfilerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ctor_profiler_stop()
        ctor_profiler_destroy()
    }

    override func tearDown() {
        super.tearDown()
        ctor_profiler_stop()
        ctor_profiler_destroy()
    }

    // MARK: - Message Handling Tests

    func testReceive_withAppLaunchProfileStopMessage_returnsTrue() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()
        ctor_profiler_start_testing(100.0, false, 5.seconds.toInt64Nanoseconds)

        // When
        let result = profiler.receive(
            message: .payload(AppLaunchProfileStop(context: mockRandomAttributes())),
            from: core
        )
        // Then
        XCTAssertTrue(result, "Should return true when processing AppLaunchProfileStop message")
    }

    func testReceive_withNonAppLaunchProfileStopMessage_returnsFalse() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()

        // When
        let result = profiler.receive(message: .payload(0), from: core)

        // Then
        XCTAssertFalse(result, "Should return false for non-AppLaunchProfileStop messages")
    }

    func testReceive_withAppLaunchProfileStopMessage_stopsProfiler() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()

        ctor_profiler_start_testing(100, false, 5.seconds.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING, "Profiler should be running")

        // When
        XCTAssertTrue(profiler.receive(message: .payload(AppLaunchProfileStop(context: mockRandomAttributes())), from: core))

        // Then
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_NOT_STARTED, "Profiler should be destroyed after processing message")
    }

    func testReceive_withAppLaunchProfileStopMessage_whenNoProfileData_returnsFalse() {
        // Given - profiler not started, so no profile data
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()

        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_NOT_STARTED, "Profiler should not be started")

        // When
        let result = profiler.receive(message: .payload(AppLaunchProfileStop(context: mockRandomAttributes())), from: core)

        // Then
        XCTAssertFalse(result, "Should return false when no profile data is available")
    }

    func testReceive_withAppLaunchProfileStopMessage_whenProfilerSampledOut_returnsFalse() {
        // Given - profiler sampled out
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()

        ctor_profiler_start_testing(0.0, false, 5.seconds.toInt64Nanoseconds) // 0% sample rate
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_SAMPLED_OUT, "Profiler should be sampled out")

        // When
        let result = profiler.receive(message: .payload(AppLaunchProfileStop(context: mockRandomAttributes())), from: core)

        // Then
        XCTAssertFalse(result, "Should return false when profiler was sampled out")
    }

    func testReceive_withAppLaunchProfileStopMessage_whenProfilerPrewarmed_returnsFalse() {
        // Given - profiler prewarmed
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()

        ctor_profiler_start_testing(100.0, true, 5.seconds.toInt64Nanoseconds) // prewarming = true
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_PREWARMED, "Profiler should be prewarmed")

        // When
        let result = profiler.receive(message: .payload(AppLaunchProfileStop(context: mockRandomAttributes())), from: core)

        // Then
        XCTAssertFalse(result, "Should return false when profiler was prewarmed")
    }

    // MARK: - Core Integration Tests

    func testReceive_withValidProfileData_createsCorrectProfileEvent() throws {
        // Given
        let profiler = AppLaunchProfiler()
        let core = SingleFeatureCoreMock(
            context: .mockWith(
                service: "test-service",
                env: "staging",
                version: "1.2.3",
                source: "ios"
            ),
            feature: ProfilerFeature(
                requestBuilder: FeatureRequestBuilderMock(),
                messageReceiver: profiler
            )
        )

        ctor_profiler_start_testing(100.0, false, 5.seconds.toInt64Nanoseconds)
        Thread.sleep(forTimeInterval: 0.1) // allow few samples

        let stopContext = mockRandomAttributes()

        // When
        XCTAssertTrue(profiler.receive(message: .payload(AppLaunchProfileStop(context: stopContext)), from: core))

        // Then
        let profilingContext = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(profilingContext.status, .stopped, "Should update the core context")

        XCTAssertEqual(core.events.count, 1, "Should write exactly one event")
        let event = try XCTUnwrap(core.events.first)
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileEvent)

        XCTAssertTrue(event is Data, "Event value should be Data (pprof)")
        XCTAssertEqual(metadata.family, "ios")
        XCTAssertEqual(metadata.runtime, "ios")
        XCTAssertEqual(metadata.version, "4")
        XCTAssertEqual(metadata.attachments, [ProfileEvent.Constants.wallFilename])

        let expectedTags = [
            "service:test-service",
            "version:1.2.3",
            "env:staging",
            "source:ios",
            "language:swift",
            "format:pprof",
            "remote_symbols:yes",
            "operation:launch"
        ].joined(separator: ",")
        XCTAssertEqual(metadata.tags, expectedTags)

        XCTAssertNotNil(metadata.start, "Should have start timestamp")
        XCTAssertNotNil(metadata.end, "Should have end timestamp")
        XCTAssertTrue(metadata.end >= metadata.start, "End timestamp should be >= start timestamp")
    }

    // MARK: - Status Mapping Tests

    func testProfilingContextStatus_mapsCorrectlyFromCtorStatus() {
        let cases: [(ctor_profiler_status_t, ProfilingContext.Status)] = [
            (CTOR_PROFILER_STATUS_NOT_STARTED, .notStarted),
            (CTOR_PROFILER_STATUS_RUNNING, .running),
            (CTOR_PROFILER_STATUS_STOPPED, .stopped),
            (CTOR_PROFILER_STATUS_TIMEOUT, .timedOut),
            (CTOR_PROFILER_STATUS_PREWARMED, .prewarmed),
            (CTOR_PROFILER_STATUS_SAMPLED_OUT, .sampledOut),
            (CTOR_PROFILER_STATUS_ERROR, .error),
            (CTOR_PROFILER_STATUS_ALLOCATION_FAILED, .error),
            (CTOR_PROFILER_STATUS_START_FAILED, .error)
        ]

        for (cStatus, swiftStatus) in cases {
            XCTAssertEqual(.init(cStatus), swiftStatus, "Status mapping for \(cStatus) should be \(swiftStatus)")
        }
    }

    func testProfilingContextStatus_currentProperty() {
        // Given
        ctor_profiler_start_testing(100.0, false, 5.seconds.toInt64Nanoseconds)

        // When
        let status: ProfilingContext.Status = .current

        // Then
        XCTAssertEqual(status, .running, "Current status should reflect actual profiler status")
    }
}
