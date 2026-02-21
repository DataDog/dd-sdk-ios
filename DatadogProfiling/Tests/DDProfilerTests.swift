/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import XCTest
import DatadogInternal
// swiftlint:disable duplicate_imports
import DatadogMachProfiler
import DatadogMachProfiler.Testing
// swiftlint:enable duplicate_imports

final class DDProfilerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // `tearDown` leaves `g_dd_profiler` nil; without this, only the first test would match the
        // static constructor's state. Recreate with 0% sample rate so `auto_start` leaves `NOT_STARTED`.
        dd_profiler_destroy()
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds)
    }

    override func tearDown() {
        dd_profiler_stop()
        dd_profiler_destroy()
        super.tearDown()
    }

    // MARK: - State Management Tests

    func testDDProfiler_initiallyNotStarted() {
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED, "Profiler should exist but not be running until started")
    }

    func testDDProfiler_startTesting_withValidSampleRate_startsSuccessfully() {
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "Profiler should be running after starting with valid sample rate")
    }

    func testDDProfiler_startTesting_withZeroSampleRate_doesNotStart() {
        dd_profiler_start_testing(0, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED, "Profiler should not start with zero sample rate")
    }

    func testDDProfiler_startTesting_withSampleRateAbove100_startsSuccessfully() {
        dd_profiler_start_testing(150, false, 5.seconds.dd.toInt64Nanoseconds)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "Profiler should start successfully with sample rate above 100")
    }

    func testDDProfiler_startTesting_withCustomTimeout() {
        dd_profiler_start_testing(100, false, 1.seconds.dd.toInt64Nanoseconds) // 1 second timeout
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "Profiler should start with custom timeout")
    }

    func testDDProfiler_startTesting_withPrewarming_doesNotStart() {
        dd_profiler_start_testing(100, true, 5.seconds.dd.toInt64Nanoseconds) // prewarming = true
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_PREWARMED, "Profiler should not start when prewarming is active")
    }

    func testDDProfiler_stop_whenRunning_stopsSuccessfully() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "Profiler should be running")

        // When
        dd_profiler_stop()

        // Then
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED, "Profiler should be stopped after calling stop")
    }

    func testDDProfiler_stop_whenNotRunning_doesNotCrash() {
        // Given
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED, "Precondition: profiler should not be running")

        // When/Then - should not crash (`stop` is a no-op when sampling was never started)
        dd_profiler_stop()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED, "Status should remain unchanged")
    }

    func testDDProfiler_multipleStops_doesNotCrash() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        dd_profiler_stop()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        // When/Then - should not crash
        dd_profiler_stop()
        dd_profiler_stop()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED, "Status should remain stopped")
    }

    // MARK: - Profile Data Management Tests

    func testDDProfiler_getProfile_whenNotStarted_returnsNil() {
        // Given
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_STARTED, "Precondition: profiler should not be started")

        // When/Then
        XCTAssertNil(dd_profiler_get_profile(), "Profile should be nil when profiler was never started")
    }

    func testDDProfiler_getProfile_whenRunning_returnsValidProfile() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "Profiler should be running")

        // Allow some time for sampling to occur
        Thread.sleep(forTimeInterval: 0.1)

        // When
        let profile = dd_profiler_get_profile()

        // Then
        XCTAssertNotNil(profile, "Profile should be available when profiler is running")
    }

    func testDDProfiler_getProfile_afterStopping_returnsValidProfile() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING, "Profiler should be running")

        // Allow some time for sampling
        Thread.sleep(forTimeInterval: 0.1)

        dd_profiler_stop()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        // When
        let profile = dd_profiler_get_profile()

        // Then
        XCTAssertNotNil(profile, "Profile should still be available after stopping")
    }

    func testDDProfiler_destroy_clearsAllData() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        Thread.sleep(forTimeInterval: 0.1)

        dd_profiler_stop()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        let profile = dd_profiler_get_profile()
        XCTAssertNotNil(profile, "Profile should be available before destroying")

        // When
        dd_profiler_destroy()

        // Then
        XCTAssertNil(dd_profiler_get_profile(), "Profile should be nil after destroying")
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED, "Status should be reset to not created")
    }

    func testDDProfiler_destroy_whenNotStarted_doesNotCrash() {
        // Given
        XCTAssertNil(dd_profiler_get_profile(), "Precondition: no profile should exist")

        // When/Then - should not crash
        dd_profiler_destroy()
        XCTAssertNil(dd_profiler_get_profile(), "Profile should still be nil")
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED, "Profiler Status should be not created")
    }

    func testDDProfiler_multipleDestroy_doesNotCrash() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        Thread.sleep(forTimeInterval: 0.1)

        // When
        dd_profiler_stop()
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED, "Profiler should be stopped")

        dd_profiler_destroy()
        XCTAssertNil(dd_profiler_get_profile(), "Profile should be nil after destroying")

        // Then - should not crash
        dd_profiler_destroy()
        dd_profiler_destroy()
        XCTAssertNil(dd_profiler_get_profile(), "Profile should remain nil")
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_NOT_CREATED, "Status should be reset to not created")
    }

    func testDDProfiler_statusCodes_prewarmed() {
        dd_profiler_start_testing(100, true, 5.seconds.dd.toInt64Nanoseconds) // prewarming = true
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_PREWARMED, "Should return PREWARMED status when prewarming is true")
    }

    // MARK: - Concurrency Tests

    func testConcurrentStop_doesNotCrash() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        let concurrentOperations = 10
        let expectation = expectation(description: "All concurrent stops complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            dd_profiler_stop()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_STOPPED)
    }

    func testConcurrentGetStatus_doesNotCrash() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)

        let concurrentOperations = 100
        let expectation = expectation(description: "All concurrent status checks complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            dd_profiler_get_status()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
    }

    func testConcurrentGetProfile_doesNotCrash() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        Thread.sleep(forTimeInterval: 0.1) // Allow some sampling

        let concurrentOperations = 50
        let expectation = expectation(description: "All concurrent profile fetches complete")
        expectation.expectedFulfillmentCount = 50

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            dd_profiler_get_profile()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
    }

    func testConcurrentDestroy_doesNotCrash() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        XCTAssertEqual(dd_profiler_get_status(), DD_PROFILER_STATUS_RUNNING)
        Thread.sleep(forTimeInterval: 0.1) // Allow some sampling
        dd_profiler_stop()

        let concurrentOperations = 10
        let expectation = expectation(description: "All concurrent destroys complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            dd_profiler_destroy()
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
        XCTAssertNil(dd_profiler_get_profile())
    }

    func testConcurrentMixedOperations_doesNotCrash() {
        // Given
        XCTAssertEqual(dd_profiler_start(), 1)
        Thread.sleep(forTimeInterval: 0.1) // Allow some sampling

        let concurrentOperations = 50
        let expectation = expectation(description: "All concurrent mixed operations complete")
        expectation.expectedFulfillmentCount = concurrentOperations

        // When
        DispatchQueue.concurrentPerform(iterations: concurrentOperations) { index in
            switch index % 4 {
            case 0:
                dd_profiler_stop()
            case 1:
                dd_profiler_get_status()
            case 2:
                dd_profiler_get_profile()
            case 3:
                dd_profiler_destroy()
            default:
                break
            }
            expectation.fulfill()
        }

        // Then
        wait(for: [expectation], timeout: 0.1)
    }
}
#endif // !os(watchOS)
