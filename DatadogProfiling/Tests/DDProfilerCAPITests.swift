/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
import DatadogMachProfiler

final class DDProfilerCAPITests: XCTestCase {
    private var receivedTraces: [UnsafePointer<stack_trace_t>?] = []
    private var receivedCounts: [Int] = []
    private var callbackUserData: UnsafeMutableRawPointer?

    override func setUp() {
        super.setUp()
        receivedTraces.removeAll()
        receivedCounts.removeAll()
        callbackUserData = nil
    }

    // MARK: - Profiler Creation Tests

    func testCreateProfiler_withDefaultConfig_createsValidInstance() {
        // Given
        let callback: stack_trace_callback_t = { _, _, _ in }

        // When
        let profiler = profiler_create(nil, callback, nil)

        // Then
        XCTAssertNotNil(profiler, "Profiler should be created successfully with default config")
        profiler_destroy(profiler)
    }

    func testCreateProfiler_withCustomConfig_createsValidInstance() {
        // Given
        var config = sampling_config_t(
            sampling_interval_nanos: 500_000, // 0.5ms
            profile_current_thread_only: 1,
            max_buffer_size: 50,
            max_stack_depth: 64,
            max_thread_count: 10,
            qos_class: QOS_CLASS_USER_INITIATED
        )

        let callback: stack_trace_callback_t = { _, _, _ in }

        // When
        let profiler = profiler_create(&config, callback, nil)

        // Then
        XCTAssertNotNil(profiler, "Profiler should be created with custom config")
        profiler_destroy(profiler)
    }

    func testCreateProfiler_withNilCallback_returnsNil() {
        // When
        let profiler = profiler_create(nil, nil, nil)

        // Then
        XCTAssertNil(profiler, "Profiler creation should fail with nil callback")
    }

    // MARK: - Profiler State Management Tests

    func testProfilerState_initiallyNotRunning() {
        // Given
        let callback: stack_trace_callback_t = { _, _, _ in }
        let profiler = profiler_create(nil, callback, nil)

        // Then
        XCTAssertEqual(profiler_is_running(profiler), 0, "Newly created profiler should not be running")
        profiler_destroy(profiler)
    }

    func testProfilerStart_changesStateToRunning() {
        // Given
        let callback: stack_trace_callback_t = { _, _, _ in }
        let profiler = profiler_create(nil, callback, nil)
        XCTAssertNotNil(profiler)

        // Then
        XCTAssertEqual(profiler_start(profiler), 1)
        XCTAssertEqual(profiler_is_running(profiler), 1, "Profiler should be running after start")

        // Cleanup
        profiler_stop(profiler)
        profiler_destroy(profiler)
    }

    func testProfilerStop_changesStateToNotRunning() {
        // Given
        let callback: stack_trace_callback_t = { _, _, _ in }
        let profiler = profiler_create(nil, callback, nil)
        XCTAssertNotNil(profiler)
        XCTAssertEqual(profiler_start(profiler), 1)
        XCTAssertEqual(profiler_is_running(profiler), 1, "Precondition: profiler should be running")

        // When
        profiler_stop(profiler)

        // Then
        XCTAssertEqual(profiler_is_running(profiler), 0, "Profiler should not be running after stop")

        // Cleanup
        profiler_destroy(profiler)
    }

    func testProfilerStartTwice_doesNotCrash() {
        // Given
        let callback: stack_trace_callback_t = { _, _, _ in }
        let profiler = profiler_create(nil, callback, nil)
        XCTAssertNotNil(profiler)
        XCTAssertEqual(profiler_start(profiler), 1)

        // When
        let secondStartResult = profiler_start(profiler)

        // Then
        XCTAssertEqual(secondStartResult, 0, "Second start should return failure")
        XCTAssertEqual(profiler_is_running(profiler), 1, "Profiler should still be running")

        // Cleanup
        profiler_stop(profiler)
        profiler_destroy(profiler)
    }

    // MARK: - Memory Management Tests

    func testProfilerDestroy_withNilProfiler_doesNotCrash() {
        // Should not crash
        profiler_destroy(nil)
    }

    func testProfilerDestroy_stopsRunningProfiler() {
        // Given
        let callback: stack_trace_callback_t = { _, _, _ in }
        let profiler = profiler_create(nil, callback, nil)
        XCTAssertNotNil(profiler)
        XCTAssertEqual(profiler_start(profiler), 1)
        XCTAssertEqual(profiler_is_running(profiler), 1)

        // When
        profiler_destroy(profiler)

        // Then
        // Should have cleaned up resources without crashing
        // Note: Can't test is_running after destroy as profiler is deallocated
    }
}
#endif // !os(watchOS)
