/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@testable import DatadogProfiling
//swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
//swiftlint:enable duplicate_imports

final class AppLaunchProfilerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLaunchProfiler.resetPendingInstances()
        ctor_profiler_stop()
        ctor_profiler_destroy()
    }

    override func tearDown() {
        super.tearDown()
        AppLaunchProfiler.resetPendingInstances()
        ctor_profiler_stop()
        ctor_profiler_destroy()
        delete_profiling_defaults()
    }

    // MARK: - Message Handling Tests

    func testReceive_withProfilerStopMessage_returnsTrue() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()
        ctor_profiler_start_testing(100.0, false, 5.seconds.dd.toInt64Nanoseconds)

        // When
        let result = profiler.receive(
            message: .payload(ProfilerStop(context: mockRandomAttributes())),
            from: core
        )
        // Then
        XCTAssertTrue(result, "Should return true when processing ProfilerStop message")
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, 0)
    }

    func testReceive_withNonProfilerStopMessage_returnsFalse() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()

        // When
        let result = profiler.receive(message: .payload(0), from: core)

        // Then
        XCTAssertFalse(result, "Should return false for non-ProfilerStop messages")
    }

    func testReceive_withProfilerStopMessage_stopsProfiler() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()

        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING, "Profiler should be running")
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, 1)

        // When
        XCTAssertTrue(profiler.receive(message: .payload(ProfilerStop(context: mockRandomAttributes())), from: core))

        // Then
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_NOT_CREATED, "Profiler should be destroyed after processing message")
        XCTAssertNil(ctor_profiler_get_profile(), "Profile should be nil after destroy")
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, 0)
    }

    func testReceive_withProfilerStopMessage_whenNoProfileData_returnsFalse() {
        // Given - profiler not started, so no profile data
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()

        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_NOT_CREATED, "Profiler should not be created")

        // When
        let result = profiler.receive(message: .payload(ProfilerStop(context: mockRandomAttributes())), from: core)

        // Then
        XCTAssertFalse(result, "Should return false when no profile data is available")
    }

    func testReceive_withProfilerStopMessage_whenProfilerSampledOut_returnsFalse() {
        // Given - profiler sampled out
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()

        ctor_profiler_start_testing(0.0, false, 5.seconds.dd.toInt64Nanoseconds) // 0% sample rate
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_SAMPLED_OUT, "Profiler should be sampled out")

        // When
        let result = profiler.receive(message: .payload(ProfilerStop(context: mockRandomAttributes())), from: core)

        // Then
        XCTAssertFalse(result, "Should return false when profiler was sampled out")
    }

    func testReceive_withProfilerStopMessage_whenProfilerPrewarmed_returnsFalse() {
        // Given - profiler prewarmed
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler()

        ctor_profiler_start_testing(100.0, true, 5.seconds.dd.toInt64Nanoseconds) // prewarming = true
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_PREWARMED, "Profiler should be prewarmed")

        // When
        let result = profiler.receive(message: .payload(ProfilerStop(context: mockRandomAttributes())), from: core)

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
                source: "ios",
                sdkVersion: "4.5.6"
            ),
            feature: ProfilerFeature(
                requestBuilder: FeatureRequestBuilderMock(),
                messageReceiver: profiler,
                sampleRate: .maxSampleRate
            )
        )

        ctor_profiler_start_testing(100.0, false, 5.seconds.dd.toInt64Nanoseconds)
        Thread.sleep(forTimeInterval: 0.1) // allow few samples

        let stopContext = mockRandomAttributes()

        // When
        XCTAssertTrue(profiler.receive(message: .payload(ProfilerStop(context: stopContext)), from: core))

        // Then
        let profilingContext = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(profilingContext.status, .stopped(reason: .manual), "Should update the core context")

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
            "sdk_version:4.5.6",
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
            (CTOR_PROFILER_STATUS_NOT_STARTED, .stopped(reason: .notStarted)),
            (CTOR_PROFILER_STATUS_RUNNING, .running),
            (CTOR_PROFILER_STATUS_STOPPED, .stopped(reason: .manual)),
            (CTOR_PROFILER_STATUS_TIMEOUT, .stopped(reason: .timeout)),
            (CTOR_PROFILER_STATUS_PREWARMED, .stopped(reason: .prewarmed)),
            (CTOR_PROFILER_STATUS_SAMPLED_OUT, .stopped(reason: .sampledOut)),
            (CTOR_PROFILER_STATUS_ALLOCATION_FAILED, .error(reason: .memoryAllocationFailed)),
            (CTOR_PROFILER_STATUS_ALREADY_STARTED, .error(reason: .alreadyStarted))
        ]

        for (cStatus, swiftStatus) in cases {
            XCTAssertEqual(.init(cStatus), swiftStatus, "Status mapping for \(cStatus) should be \(swiftStatus)")
        }
    }

    func testProfilingContextStatus_currentProperty() {
        // Given
        ctor_profiler_start_testing(100.0, false, 5.seconds.dd.toInt64Nanoseconds)

        // When
        let status: ProfilingContext.Status = .current

        // Then
        XCTAssertEqual(status, .running, "Current status should reflect actual profiler status")
    }

    // MARK: - UserDefaults Integration

    func testIsProfilingEnabled_whenNoKeyExists() {
        // When
        let result = is_profiling_enabled()

        // Then
        XCTAssertFalse(result)
    }

    func testIsProfilingEnabled_whenKeyIsTrue() {
        // Given
        let userDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)
        userDefaults?.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)

        // When
        let result = is_profiling_enabled()

        // Then
        XCTAssertTrue(result)
    }

    func testIsProfilingDisabled_whenKeyIsFalse() {
        // Given
        let userDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)
        userDefaults?.setValue(false, forKey: DD_PROFILING_IS_ENABLED_KEY)

        // When
        let result = is_profiling_enabled()

        // Then
        XCTAssertFalse(result)
    }

    func testDeleteProfilingDefaults_removesKeyFromUserDefaults() {
        // Given
        let userDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)
        userDefaults?.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)

        XCTAssertTrue(is_profiling_enabled())

        // When
        delete_profiling_defaults()

        // Then
        XCTAssertFalse(is_profiling_enabled())
    }

    func testDeleteProfilingDefaults_multipleCallsAreSafe() {
        // Given
        let userDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)
        userDefaults?.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)

        // When
        delete_profiling_defaults()
        delete_profiling_defaults()
        delete_profiling_defaults()

        // Then
        XCTAssertFalse(is_profiling_enabled())
    }

    func testProfilingDefaults_persistAcrossTestCases() {
        // When
        let userDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)
        userDefaults?.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)
        let otherUserDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)

        // Then
        XCTAssertTrue(otherUserDefaults?.value(forKey: DD_PROFILING_IS_ENABLED_KEY) as? Bool ?? false)
        XCTAssertTrue(is_profiling_enabled())
    }

    // MARK: - Pending Instances Tests

    func testMultipleInstances_destroysOnlyAfterAllReceiveMessage() {
        // Given
        let iterations = 10
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, 0)
        let cores = (0..<iterations).map { _ in PassthroughCoreMock() }
        let profilers = (0..<iterations).map { _ in AppLaunchProfiler() }

        ctor_profiler_start_testing(100.0, false, 5.seconds.dd.toInt64Nanoseconds)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, iterations)

        // When
        for (index, profiler) in profilers.enumerated() {
            _ = profiler.receive(message: .payload(ProfilerStop(context: mockRandomAttributes())), from: cores[index])

            let remainingInstances = iterations - index - 1
            if remainingInstances > 0 {
                // Then
                XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, remainingInstances)
                XCTAssertNotNil(ctor_profiler_get_profile(), "Profile should still exist after first receive")
            }
        }

        // Then
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, 0)
        XCTAssertNil(ctor_profiler_get_profile(), "Profile should be nil after all instances received")
    }

    func testConcurrentRegistration_isThreadSafe() {
        // Given
        let iterations = 100
        let expectation = expectation(description: "All concurrent registrations complete")
        expectation.expectedFulfillmentCount = iterations

        // When
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = AppLaunchProfiler()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, iterations)
    }
}
