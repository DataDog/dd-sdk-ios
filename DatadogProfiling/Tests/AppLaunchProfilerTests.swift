/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

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
        dd_profiler_stop()
        dd_profiler_destroy()
    }

    override func tearDown() {
        super.tearDown()
        AppLaunchProfiler.resetPendingInstances()
        dd_profiler_stop()
        dd_profiler_destroy()
        dd_delete_profiling_defaults()
    }

    // MARK: - Message Handling Tests

    func testReceiveRUMMessage() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = appLaunchProfiler
        XCTAssertEqual(dd_profiler_start(), 1)

        // When
        let result = profiler.receive(
            message: .payload(RUMMessage(context: mockRandomAttributes(), event: vital)),
            from: core
        )
        // Then
        XCTAssertFalse(result, "Continuous profiler and AppLaunch profiler consume app launch vitals")
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, 0)
    }

    func testReceiveNonVitalMessage() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = appLaunchProfiler

        // When
        let result = profiler.receive(message: .payload(0), from: core)

        // Then
        XCTAssertFalse(result, "Should return false for non-ProfilerStop messages")
    }

    func testReceiveVitalMessage_stopsProfiler() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = appLaunchProfiler

        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "Profiler should be running")
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, 1)

        // When
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: vital)), from: core)

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
        let sampleCount = dd_pprof_sample_count(dd_profiler_get_profile())
        XCTAssertEqual(sampleCount, 0, "Current profile should have no samples after harvest")
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, 0)
    }

    // Profiler should remain running when continuous profiling is enabled
    func testReceiveVitalMessageWhenContinuousProfiling_doesNotStopProfiler() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler(core: core, isContinuousProfiling: true)

        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        // When
        let result = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: vital)), from: core)

        // Then
        XCTAssertFalse(result, "Continuous profiler and AppLaunch profiler consume app launch vitals")
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
    }

    func testReceive_withVitalMessage_whenNoProfileData_returnsFalse() {
        // Given - profiler not started, so no profile data
        let core = PassthroughCoreMock()
        let profiler = appLaunchProfiler

        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED, "Profiler should not be created")

        // When
        let result = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: vital)), from: core)

        // Then
        XCTAssertFalse(result, "Should return false when no profile data is available")
    }

    func testReceive_withVitalMessage_whenProfilerSampledOut_returnsFalse() {
        // Given - profiler sampled out
        let core = PassthroughCoreMock()
        let profiler = appLaunchProfiler

        dd_profiler_start_testing(0.0, false, 5.seconds.dd.toInt64Nanoseconds) // 0% sample rate
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED, "Profiler should be sampled out")

        // When
        let result = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: vital)), from: core)

        // Then
        XCTAssertFalse(result, "Should return false when profiler was sampled out")
    }

    func testReceive_withVitalMessage_whenProfilerPrewarmed_returnsFalse() {
        // Given - profiler prewarmed
        let core = PassthroughCoreMock()
        let profiler = appLaunchProfiler

        dd_profiler_start_testing(100.0, true, 5.seconds.dd.toInt64Nanoseconds) // prewarming = true
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_PREWARMED, "Profiler should be prewarmed")

        // When
        let result = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: vital)), from: core)

        // Then
        XCTAssertFalse(result, "Should return false when profiler was prewarmed")
    }

    // MARK: - Core Integration Tests

    func testReceive_withValidProfileData_createsCorrectProfileEvent() throws {
        // Given
        let core = SingleFeatureCoreMock(
            context: .mockWith(
                service: "test-service",
                env: "staging",
                version: "1.2.3",
                source: "ios",
                sdkVersion: "4.5.6",
                os: .mockWith(version: "26.1")
            ),
            feature: ProfilerFeature(
                core: PassthroughCoreMock(),
                configuration: .init(),
                requestBuilder: FeatureRequestBuilderMock(),
                telemetryController: .init()
            )
        )
        let profiler = AppLaunchProfiler(core: core, isContinuousProfiling: false)

        XCTAssertEqual(dd_profiler_start(), 1)
        Thread.sleep(forTimeInterval: 0.1) // allow few samples

        let stopContext = mockRandomAttributes()

        // When
        _ = profiler.receive(message: .payload(RUMMessage(context: stopContext, event: vital)), from: core)

        // Then
        let profilingContext = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(profilingContext.status, .stopped(reason: .manual), "Should update the core context")

        XCTAssertEqual(core.events.count, 1, "Should write exactly one event")
        let event = try XCTUnwrap(core.events.first as? ProfileEvent)
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)

        XCTAssertTrue(metadata.rumEvents != nil)
        XCTAssertEqual(event.family, "ios")
        XCTAssertEqual(event.runtime, "ios")
        XCTAssertEqual(event.version, "4")
        XCTAssertEqual(event.attachments, [ProfileAttachments.Constants.wallFilename, ProfileAttachments.Constants.rumEventsFilename])

        let expectedTags = [
            "service:test-service",
            "version:1.2.3",
            "sdk_version:4.5.6",
            "profiler_version:4.5.6",
            "runtime_version:26.1",
            "env:staging",
            "source:ios",
            "language:swift",
            "format:pprof",
            "remote_symbols:yes",
            "operation:launch"
        ].joined(separator: ",")
        XCTAssertEqual(event.tags, expectedTags)

        XCTAssertNotNil(event.start, "Should have start timestamp")
        XCTAssertNotNil(event.end, "Should have end timestamp")
        XCTAssertTrue(event.end >= event.start, "End timestamp should be >= start timestamp")
    }

    // MARK: - Status Mapping Tests

    func testProfilingContextStatus_mapsCorrectlyFromDDProfilerStatus() {
        let cases: [(dd_profiler_status_t, ProfilingContext.Status)] = [
            (DD_PROFILER_STATUS_NOT_STARTED, .stopped(reason: .notStarted)),
            (DD_PROFILER_STATUS_RUNNING, .running),
            (DD_PROFILER_STATUS_STOPPED, .stopped(reason: .manual)),
            (DD_PROFILER_STATUS_TIMEOUT, .stopped(reason: .timeout)),
            (DD_PROFILER_STATUS_PREWARMED, .stopped(reason: .prewarmed)),
            (DD_PROFILER_STATUS_ALLOCATION_FAILED, .error(reason: .memoryAllocationFailed)),
            (DD_PROFILER_STATUS_ALREADY_STARTED, .error(reason: .alreadyStarted))
        ]

        for (cStatus, swiftStatus) in cases {
            XCTAssertEqual(.init(cStatus), swiftStatus, "Status mapping for \(cStatus) should be \(swiftStatus)")
        }
    }

    func testProfilingContextStatus_currentProperty() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)

        // When
        let status: ProfilingContext.Status = .current

        // Then
        XCTAssertEqual(status, .running, "Current status should reflect actual profiler status")
    }

    // MARK: - UserDefaults Integration

    func testIsProfilingEnabled_whenNoKeyExists() {
        // When
        let result = dd_is_profiling_enabled()

        // Then
        XCTAssertFalse(result)
    }

    func testIsProfilingEnabled_whenKeyIsTrue() {
        // Given
        let userDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)
        userDefaults?.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)

        // When
        let result = dd_is_profiling_enabled()

        // Then
        XCTAssertTrue(result)
    }

    func testIsProfilingDisabled_whenKeyIsFalse() {
        // Given
        let userDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)
        userDefaults?.setValue(false, forKey: DD_PROFILING_IS_ENABLED_KEY)

        // When
        let result = dd_is_profiling_enabled()

        // Then
        XCTAssertFalse(result)
    }

    func testDeleteProfilingDefaults_removesKeyFromUserDefaults() {
        // Given
        let userDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)
        userDefaults?.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)

        XCTAssertTrue(dd_is_profiling_enabled())

        // When
        dd_delete_profiling_defaults()

        // Then
        XCTAssertFalse(dd_is_profiling_enabled())
    }

    func testDeleteProfilingDefaults_multipleCallsAreSafe() {
        // Given
        let userDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)
        userDefaults?.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)

        // When
        dd_delete_profiling_defaults()
        dd_delete_profiling_defaults()
        dd_delete_profiling_defaults()

        // Then
        XCTAssertFalse(dd_is_profiling_enabled())
    }

    func testProfilingDefaults_persistAcrossTestCases() {
        // When
        let userDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)
        userDefaults?.setValue(true, forKey: DD_PROFILING_IS_ENABLED_KEY)
        let otherUserDefaults = UserDefaults(suiteName: DD_PROFILING_USER_DEFAULTS_SUITE_NAME)

        // Then
        XCTAssertTrue(otherUserDefaults?.value(forKey: DD_PROFILING_IS_ENABLED_KEY) as? Bool ?? false)
        XCTAssertTrue(dd_is_profiling_enabled())
    }

    // MARK: - RUM Vitals

    func testReceiveCompleteRumOperation() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler(core: core, isContinuousProfiling: false)
        let startVital = Vital.mockWith(type: .rumOperation(.start))
        let endVital = Vital.mockWith(name: startVital.name, operationKey: startVital.operationKey, type: .rumOperation(.end))

        // When
        XCTAssertFalse(
            profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: startVital)), from: core),
            "RUM operations are also consumed by continuous profiler"
        )
        let result = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: endVital)), from: core)

        // Then
        XCTAssertFalse(result, "Continuous profiler and AppLaunch profiler consume RUM operations")
    }

    func testReceiveApplicationLaunchAndOperations() {
        // Given
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler(core: core, isContinuousProfiling: false)
        XCTAssertEqual(dd_profiler_start(), 1)

        // When
        var result = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: vital)), from: core)
        // Then
        XCTAssertFalse(result, "Continuous profiler and AppLaunch profiler consume app launch vitals")

        // When
        result = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: vital)), from: core)
        // Then
        XCTAssertFalse(result, "Continuous profiler and AppLaunch profiler consume RUM operations")
    }

    func testApplicationLaunchWithRumOperations_includesVitalsInProfile() throws {
        // Given
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler(core: core, isContinuousProfiling: false)
        let startVital = Vital.mockWith(id: "start-id", name: "operation", type: .rumOperation(.start))
        let endVital = Vital.mockWith(id: "end-id", name: "operation", type: .rumOperation(.end))

        XCTAssertEqual(dd_profiler_start(), 1)
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: startVital)), from: core)
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: endVital)), from: core)

        // When
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: vital)), from: core)

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEventsData = try XCTUnwrap(metadata.rumEvents)
        let rumEvents = try JSONDecoder().decode(RUMEvents.self, from: rumEventsData)
        let vitalIDs = rumEvents.vitals.map(\.id)
        XCTAssertEqual(vitalIDs.count, 3)
        XCTAssertTrue(vitalIDs.contains("start-id"))
        XCTAssertTrue(vitalIDs.contains("end-id"))
    }

    func testApplicationLaunchWithOrphanedEndVital_excludesOrphanedFromProfile() throws {
        // Given
        let core = PassthroughCoreMock()
        let profiler = AppLaunchProfiler(core: core, isContinuousProfiling: false)
        let startVital = Vital.mockWith(id: "start-id", name: "operation1", type: .rumOperation(.start))
        let orphanedEnd = Vital.mockWith(id: "orphan-id", name: "operation2", type: .rumOperation(.end))

        XCTAssertEqual(dd_profiler_start(), 1)
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: startVital)), from: core)
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: orphanedEnd)), from: core)

        // When
        _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: vital)), from: core)

        // Then
        let metadata = try XCTUnwrap(core.metadata.first as? ProfileAttachments)
        let rumEventsData = try XCTUnwrap(metadata.rumEvents)
        let rumEvents = try JSONDecoder().decode(RUMEvents.self, from: rumEventsData)
        let vitalIDs = rumEvents.vitals.map(\.id)
        XCTAssertEqual(vitalIDs.count, 2)
        XCTAssertTrue(vitalIDs.contains("start-id"))
        XCTAssertFalse(vitalIDs.contains("orphan-id"))
    }

    // MARK: - Pending Instances Tests

    func testMultipleInstances_destroysOnlyAfterAllReceiveMessage() {
        // Given
        let iterations = 10
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, 0)
        let cores = (0..<iterations).map { _ in PassthroughCoreMock() }
        let profilers = (0..<iterations).map { _ in appLaunchProfiler }

        XCTAssertEqual(dd_profiler_start(), 1)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, iterations)

        // When
        for (index, profiler) in profilers.enumerated() {
            _ = profiler.receive(message: .payload(RUMMessage(context: mockRandomAttributes(), event: vital)), from: cores[index])

            let remainingInstances = iterations - index - 1
            if remainingInstances > 0 {
                // Then
                XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, remainingInstances)
                XCTAssertNotNil(dd_profiler_get_profile(), "Profile should still exist after first receive")
            }
        }

        // Then
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, 0)
        let sampleCount = dd_pprof_sample_count(dd_profiler_get_profile())
        XCTAssertEqual(sampleCount, 0, "Profile should have no samples after all instances received")
    }

    func testConcurrentRegistration_isThreadSafe() {
        // Given
        let iterations = 100
        let expectation = expectation(description: "All concurrent registrations complete")
        expectation.expectedFulfillmentCount = iterations

        // When
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = appLaunchProfiler
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
        XCTAssertEqual(AppLaunchProfiler.currentPendingInstances, 0, "Not all AppLaunchProfilers have deallocated")
    }

    private var appLaunchProfiler: AppLaunchProfiler {
        AppLaunchProfiler(core: PassthroughCoreMock(), isContinuousProfiling: false)
    }

    private var vital: Vital {
        .mockWith(type: .applicationLaunch)
    }
}

#endif // !os(watchOS)
