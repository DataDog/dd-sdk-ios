/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class MainThreadSchedulerTests: XCTestCase {
    func testWhenStarted_itRepeatsOperation() {
        let expectation = self.expectation(description: "repeat operation 5 times")
        expectation.expectedFulfillmentCount = 5
        expectation.assertForOverFulfill = false

        // Given
        let scheduler = MainThreadScheduler(interval: 0.01)
        scheduler.schedule { expectation.fulfill() }

        // When
        scheduler.start()

        // Then
        waitForExpectations(timeout: 0.5)
        scheduler.stop()
    }

    func testWhenNotStarted_itDoesNotRepeatOperation() {
        let expectation = self.expectation(description: "do not perform operation")
        expectation.isInverted = true

        // Given
        let scheduler = MainThreadScheduler(interval: 0.01)
        scheduler.schedule { expectation.fulfill() }

        // When (no start), Then
        waitForExpectations(timeout: 0.05)
    }

    func testWhenRepeatingOperations_itExecutesItOnTheMainThread() {
        let expectation = self.expectation(description: "perform operation")
        expectation.assertForOverFulfill = false

        // Given
        let scheduler = MainThreadScheduler(interval: 0.1)

        // When
        scheduler.schedule {
            XCTAssertTrue(Thread.isMainThread, "An operation should be ran on the main thread")
            expectation.fulfill()
        }

        // Then
        scheduler.start()
        waitForExpectations(timeout: 1)
        scheduler.stop()
    }

    func testItCanScheduleMultipleOperations() {
        let expectation = self.expectation(description: "perform 3 operations")
        expectation.expectedFulfillmentCount = 3
        expectation.assertForOverFulfill = false

        // Given
        let scheduler = MainThreadScheduler(interval: 0.01)

        // When
        scheduler.schedule { expectation.fulfill() }
        scheduler.schedule { expectation.fulfill() }
        scheduler.schedule { expectation.fulfill() }

        // Then
        scheduler.start()
        waitForExpectations(timeout: 1)
        scheduler.stop()
    }

    /// Collects dates when running recurring operation and checks if intervals are close to expected value.
    ///
    /// It asserts on p25 to mitigate precision issues in underlying`Timer`. Precission lost is expected and comes from `Timer.tolerance`
    /// used internally in `MainThreadScheduler`. Setting tolerance is recommended (ref.: https://developer.apple.com/documentation/foundation/timer )
    /// as it vastly improves performance and leads to less overhead on the app and device. The trade-off of this is more skews in actual intervals.
    func testItRepeatsScheduledOperationInGivenIntervals() {
        let numberOfRepeats = 100
        let expectation = self.expectation(description: "repeat \(numberOfRepeats) times")
        expectation.expectedFulfillmentCount = numberOfRepeats
        expectation.assertForOverFulfill = false

        // Given
        let interval: TimeInterval = .random(in: (0.001...0.01))
        let scheduler = MainThreadScheduler(interval: interval)

        var operationDates: [Date] = []
        let operation: () -> Void = {
            operationDates.append(Date())
            expectation.fulfill()
        }

        // When
        scheduler.schedule(operation: operation)
        scheduler.start()

        waitForExpectations(timeout: 10 * interval * Double(numberOfRepeats))
        scheduler.stop()

        // Then
        XCTAssertEqual(operationDates.count, numberOfRepeats, "It should repeat exactly \(numberOfRepeats) times")

        var belowIntervalCount = 0
        zip(operationDates, operationDates.dropFirst()).forEach { previous, next in
            belowIntervalCount += next.timeIntervalSince(previous) <= interval ? 1 : 0
        }

        let p25 = numberOfRepeats / 4 // Assert on p25 to avoid flakiness:
        XCTAssertGreaterThanOrEqual(belowIntervalCount, p25, "At least 25% of repeats should be below \(interval)s")
    }
}
