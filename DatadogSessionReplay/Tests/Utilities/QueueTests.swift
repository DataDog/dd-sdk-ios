/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

class QueueTests: XCTestCase {
    func testMainAsyncQueueRunsAsynchronouslyOnTheMainThread() {
        let expectation = self.expectation(description: "Run asynchronously on the main thread")
        let randomValue: Int = .mockRandom()

        // Given
        let queue = MainAsyncQueue()

        // When
        var value = randomValue
        queue.run {
            XCTAssertTrue(Thread.isMainThread)
            value = .mockRandom(otherThan: [randomValue])
            expectation.fulfill()
        }

        // Then
        XCTAssertEqual(value, randomValue)
        waitForExpectations(timeout: 0.5)
        XCTAssertNotEqual(value, randomValue)
    }

    func testBackgroundAsyncQueueRunsAsynchronouslyOnBackgroundThread() {
        let expectation = self.expectation(description: "Run asynchronously on background thread")
        let randomValue: Int = .mockRandom()

        // Given
        let queue = BackgroundAsyncQueue(named: .mockAny())

        // When
        var value = randomValue
        queue.run {
            XCTAssertFalse(Thread.isMainThread)
            value = .mockRandom(otherThan: [randomValue])
            expectation.fulfill()
        }

        // Then
        XCTAssertEqual(value, randomValue)
        waitForExpectations(timeout: 0.5)
        XCTAssertNotEqual(value, randomValue)
    }
}
#endif
