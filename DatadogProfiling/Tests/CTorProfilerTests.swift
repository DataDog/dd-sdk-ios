/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import DatadogMachProfiler

final class CTorProfilerTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        profiler_stop()
        profiler_destroy()
    }

    // MARK: - State Management Tests

    func testCtorProfiler_initiallyNotStarted() {
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_NOT_CREATED, "Constructor profiler should not be started initially")
    }

    func testCtorProfiler_startTesting_withValidSampleRate_startsSuccessfully() {
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_RUNNING, "Profiler should be running after starting with valid sample rate")
    }

    func testCtorProfiler_startTesting_withZeroSampleRate_doesNotStart() {
        profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_SAMPLED_OUT, "Profiler should not start with zero sample rate")
    }

    func testCtorProfiler_startTesting_withSampleRateAbove100_startsSuccessfully() {
        profiler_start_testing(150, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_RUNNING, "Profiler should start successfully with sample rate above 100")
    }

    func testCtorProfiler_startTesting_withCustomTimeout() {
        profiler_start_testing(100, false, 1.seconds.dd.toInt64Nanoseconds) // 1 second timeout
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_RUNNING, "Profiler should start with custom timeout")
    }

    func testCtorProfiler_startTesting_withPrewarming_doesNotStart() {
        profiler_start_testing(100, true, 5.seconds.dd.toInt64Nanoseconds) // prewarming = true
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_PREWARMED, "Profiler should not start when prewarming is active")
    }

    func testCtorProfiler_stop_whenRunning_stopsSuccessfully() {
        // Given
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_RUNNING, "Profiler should be running")

        // When
        profiler_stop()

        // Then
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_STOPPED, "Profiler should be stopped after calling stop")
    }

    func testCtorProfiler_stop_whenNotRunning_doesNotCrash() {
        // Given
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_NOT_CREATED, "Precondition: profiler should not be running")

        // When/Then - should not crash
        profiler_stop()
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_NOT_CREATED, "Status should remain unchanged")
    }

    func testCtorProfiler_multipleStops_doesNotCrash() {
        // Given
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        profiler_stop()
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        // When/Then - should not crash
        profiler_stop()
        profiler_stop()
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_STOPPED, "Status should remain stopped")
    }

    // MARK: - Profile Data Management Tests

    func testCtorProfiler_getProfile_whenNotStarted_returnsNil() {
        // Given
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_NOT_CREATED, "Precondition: profiler should not be started")

        // When/Then
        XCTAssertNil(profiler_get_profile(false), "Profile should be nil when profiler was never started")
    }

    func testCtorProfiler_getProfile_whenRunning_returnsValidProfile() {
        // Given
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_RUNNING, "Profiler should be running")

        // Allow some time for sampling to occur
        Thread.sleep(forTimeInterval: 0.1)

        // When
        let profile = profiler_get_profile(false)

        // Then
        XCTAssertNotNil(profile, "Profile should be available when profiler is running")
    }

    func testCtorProfiler_getProfile_afterStopping_returnsValidProfile() {
        // Given
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_RUNNING, "Profiler should be running")

        // Allow some time for sampling
        Thread.sleep(forTimeInterval: 0.1)

        profiler_stop()
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        // When
        let profile = profiler_get_profile(false)

        // Then
        XCTAssertNotNil(profile, "Profile should still be available after stopping")
    }

    func testCtorProfiler_destroy_clearsAllData() {
        // Given
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        Thread.sleep(forTimeInterval: 0.1)

        profiler_stop()
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        let profile = profiler_get_profile(false)
        XCTAssertNotNil(profile, "Profile should be available before destroying")

        // When
        profiler_destroy()

        // Then
        XCTAssertNil(profiler_get_profile(false), "Profile should be nil after destroying")
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_NOT_CREATED, "Status should be reset to not created")
    }

    func testCtorProfiler_destroy_whenNotStarted_doesNotCrash() {
        // Given
        XCTAssertNil(profiler_get_profile(false), "Precondition: no profile should exist")

        // When/Then - should not crash
        profiler_destroy()
        XCTAssertNil(profiler_get_profile(false), "Profile should still be nil")
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_NOT_CREATED, "Profiler Status should be not created")
    }

    func testCtorProfiler_multipleDestroy_doesNotCrash() {
        // Given
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        Thread.sleep(forTimeInterval: 0.1)

        // When
        profiler_stop()
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        profiler_destroy()
        XCTAssertNil(profiler_get_profile(false), "Profile should be nil after destroying")

        // Then - should not crash
        profiler_destroy()
        profiler_destroy()
        XCTAssertNil(profiler_get_profile(false), "Profile should remain nil")
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_NOT_CREATED, "Status should be reset to not created")
    }

    func testCtorProfiler_statusCodes_prewarmed() {
        profiler_start_testing(100, true, 5.seconds.dd.toInt64Nanoseconds) // prewarming = true
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_PREWARMED, "Should return PREWARMED status when prewarming is true")
    }

    // MARK: - Concurrency Tests

    func testConcurrentStop_doesNotCrash() {
        // Given
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_RUNNING)

        let concurrentOperations = 10
        let expectation = expectation(description: "All concurrent stops complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            profiler_stop()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_STOPPED)
    }

    func testConcurrentGetStatus_doesNotCrash() {
        // Given
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_RUNNING)

        let concurrentOperations = 100
        let expectation = expectation(description: "All concurrent status checks complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            profiler_get_status()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
    }

    func testConcurrentGetProfile_doesNotCrash() {
        // Given
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_RUNNING)
        Thread.sleep(forTimeInterval: 0.1) // Allow some sampling

        let concurrentOperations = 50
        let expectation = expectation(description: "All concurrent profile fetches complete")
        expectation.expectedFulfillmentCount = 50

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            profiler_get_profile(false)
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
    }

    func testConcurrentDestroy_doesNotCrash() {
        // Given
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(profiler_get_status(), PROFILER_STATUS_RUNNING)
        Thread.sleep(forTimeInterval: 0.1) // Allow some sampling
        profiler_stop()

        let concurrentOperations = 10
        let expectation = expectation(description: "All concurrent destroys complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            profiler_destroy()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
        XCTAssertNil(profiler_get_profile(false))
    }

    func testConcurrentMixedOperations_doesNotCrash() {
        // Given
        profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        Thread.sleep(forTimeInterval: 0.1) // Allow some sampling

        let concurrentOperations = 50
        let expectation = expectation(description: "All concurrent mixed operations complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            switch index % 4 {
            case 0:
                profiler_stop()
            case 1:
                profiler_get_status()
            case 2:
                profiler_get_profile(false)
            case 3:
                profiler_destroy()
            default:
                break
            }
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
    }
}
