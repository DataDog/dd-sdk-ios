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
        ctor_profiler_stop()
        ctor_profiler_destroy()
    }

    // MARK: - State Management Tests

    func testCtorProfiler_initiallyNotStarted() {
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_NOT_CREATED, "Constructor profiler should not be started initially")
    }

    func testCtorProfiler_startTesting_withValidSampleRate_startsSuccessfully() {
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING, "Profiler should be running after starting with valid sample rate")
    }

    func testCtorProfiler_startTesting_withZeroSampleRate_doesNotStart() {
        ctor_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_SAMPLED_OUT, "Profiler should not start with zero sample rate")
    }

    func testCtorProfiler_startTesting_withSampleRateAbove100_startsSuccessfully() {
        ctor_profiler_start_testing(150, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING, "Profiler should start successfully with sample rate above 100")
    }

    func testCtorProfiler_startTesting_withCustomTimeout() {
        ctor_profiler_start_testing(100, false, 1.seconds.dd.toInt64Nanoseconds) // 1 second timeout
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING, "Profiler should start with custom timeout")
    }

    func testCtorProfiler_startTesting_withPrewarming_doesNotStart() {
        ctor_profiler_start_testing(100, true, 5.seconds.dd.toInt64Nanoseconds) // prewarming = true
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_PREWARMED, "Profiler should not start when prewarming is active")
    }

    func testCtorProfiler_stop_whenRunning_stopsSuccessfully() {
        // Given
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING, "Profiler should be running")

        // When
        ctor_profiler_stop()

        // Then
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_STOPPED, "Profiler should be stopped after calling stop")
    }

    func testCtorProfiler_stop_whenNotRunning_doesNotCrash() {
        // Given
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_NOT_CREATED, "Precondition: profiler should not be running")

        // When/Then - should not crash
        ctor_profiler_stop()
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_NOT_CREATED, "Status should remain unchanged")
    }

    func testCtorProfiler_multipleStops_doesNotCrash() {
        // Given
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        ctor_profiler_stop()
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        // When/Then - should not crash
        ctor_profiler_stop()
        ctor_profiler_stop()
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_STOPPED, "Status should remain stopped")
    }

    // MARK: - Profile Data Management Tests

    func testCtorProfiler_getProfile_whenNotStarted_returnsNil() {
        // Given
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_NOT_CREATED, "Precondition: profiler should not be started")

        // When/Then
        XCTAssertNil(ctor_profiler_get_profile(), "Profile should be nil when profiler was never started")
    }

    func testCtorProfiler_getProfile_whenRunning_returnsValidProfile() {
        // Given
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING, "Profiler should be running")

        // Allow some time for sampling to occur
        Thread.sleep(forTimeInterval: 0.1)

        // When
        let profile = ctor_profiler_get_profile()

        // Then
        XCTAssertNotNil(profile, "Profile should be available when profiler is running")
    }

    func testCtorProfiler_getProfile_afterStopping_returnsValidProfile() {
        // Given
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING, "Profiler should be running")

        // Allow some time for sampling
        Thread.sleep(forTimeInterval: 0.1)

        ctor_profiler_stop()
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        // When
        let profile = ctor_profiler_get_profile()

        // Then
        XCTAssertNotNil(profile, "Profile should still be available after stopping")
    }

    func testCtorProfiler_destroy_clearsAllData() {
        // Given
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        Thread.sleep(forTimeInterval: 0.1)

        ctor_profiler_stop()
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        let profile = ctor_profiler_get_profile()
        XCTAssertNotNil(profile, "Profile should be available before destroying")

        // When
        ctor_profiler_destroy()

        // Then
        XCTAssertNil(ctor_profiler_get_profile(), "Profile should be nil after destroying")
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_NOT_CREATED, "Status should be reset to not created")
    }

    func testCtorProfiler_destroy_whenNotStarted_doesNotCrash() {
        // Given
        XCTAssertNil(ctor_profiler_get_profile(), "Precondition: no profile should exist")

        // When/Then - should not crash
        ctor_profiler_destroy()
        XCTAssertNil(ctor_profiler_get_profile(), "Profile should still be nil")
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_NOT_CREATED, "Profiler Status should be not created")
    }

    func testCtorProfiler_multipleDestroy_doesNotCrash() {
        // Given
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        Thread.sleep(forTimeInterval: 0.1)

        // When
        ctor_profiler_stop()
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        ctor_profiler_destroy()
        XCTAssertNil(ctor_profiler_get_profile(), "Profile should be nil after destroying")

        // Then - should not crash
        ctor_profiler_destroy()
        ctor_profiler_destroy()
        XCTAssertNil(ctor_profiler_get_profile(), "Profile should remain nil")
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_NOT_CREATED, "Status should be reset to not created")
    }

    func testCtorProfiler_statusCodes_prewarmed() {
        ctor_profiler_start_testing(100, true, 5.seconds.dd.toInt64Nanoseconds) // prewarming = true
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_PREWARMED, "Should return PREWARMED status when prewarming is true")
    }

    // MARK: - Concurrency Tests

    func testConcurrentStop_doesNotCrash() {
        // Given
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING)

        let concurrentOperations = 10
        let expectation = expectation(description: "All concurrent stops complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            ctor_profiler_stop()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_STOPPED)
    }

    func testConcurrentGetStatus_doesNotCrash() {
        // Given
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING)

        let concurrentOperations = 100
        let expectation = expectation(description: "All concurrent status checks complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            ctor_profiler_get_status()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
    }

    func testConcurrentGetProfile_doesNotCrash() {
        // Given
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING)
        Thread.sleep(forTimeInterval: 0.1) // Allow some sampling

        let concurrentOperations = 50
        let expectation = expectation(description: "All concurrent profile fetches complete")
        expectation.expectedFulfillmentCount = 50

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            ctor_profiler_get_profile()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
    }

    func testConcurrentDestroy_doesNotCrash() {
        // Given
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(ctor_profiler_get_status(), CTOR_PROFILER_STATUS_RUNNING)
        Thread.sleep(forTimeInterval: 0.1) // Allow some sampling
        ctor_profiler_stop()

        let concurrentOperations = 10
        let expectation = expectation(description: "All concurrent destroys complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            ctor_profiler_destroy()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
        XCTAssertNil(ctor_profiler_get_profile())
    }

    func testConcurrentMixedOperations_doesNotCrash() {
        // Given
        ctor_profiler_start_testing(100, false, 5.seconds.dd.toInt64Nanoseconds)
        Thread.sleep(forTimeInterval: 0.1) // Allow some sampling

        let concurrentOperations = 50
        let expectation = expectation(description: "All concurrent mixed operations complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            switch index % 4 {
            case 0:
                ctor_profiler_stop()
            case 1:
                ctor_profiler_get_status()
            case 2:
                ctor_profiler_get_profile()
            case 3:
                ctor_profiler_destroy()
            default:
                break
            }
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
    }
}
