/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

final class ThreadingTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case expected
    }

    func testRunOnQueueSyncExecutesOnQueueAndReturnsValueSynchronously() {
        let queue = DispatchQueue(label: "test.queue")
        let key = DispatchSpecificKey<Void>()
        queue.setSpecific(key: key, value: ())
        var didExecute = false

        let value = runOnQueueSync(queue, key: key) {
            XCTAssertNotNil(DispatchQueue.getSpecific(key: key))
            didExecute = true
            return 42
        }

        XCTAssertTrue(didExecute)
        XCTAssertEqual(value, 42)
        XCTAssertNil(DispatchQueue.getSpecific(key: key))
    }

    func testRunOnQueueSyncRethrowsBlockError() {
        let queue = DispatchQueue(label: "test.queue")
        let key = DispatchSpecificKey<Void>()
        queue.setSpecific(key: key, value: ())

        XCTAssertThrowsError(try runOnQueueSync(queue, key: key) {
            XCTAssertNotNil(DispatchQueue.getSpecific(key: key))
            throw TestError.expected
        }) { error in
            XCTAssertEqual(error as? TestError, .expected)
        }
    }

    func testRunOnQueueSyncRunsInlineWhenAlreadyOnQueue() {
        let queue = DispatchQueue(label: "test.queue")
        let key = DispatchSpecificKey<Void>()
        queue.setSpecific(key: key, value: ())
        let completed = expectation(description: "Reentrant work completes")

        queue.async {
            let value = runOnQueueSync(queue, key: key) {
                XCTAssertNotNil(DispatchQueue.getSpecific(key: key))
                return 42
            }
            XCTAssertEqual(value, 42)
            do {
                try runOnQueueSync(queue, key: key) {
                    throw TestError.expected
                }
                XCTFail("Expected the block error to be rethrown")
            } catch {
                XCTAssertEqual(error as? TestError, .expected)
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
    }

    func testRunOnQueueSyncDistinguishesQueuesWithDifferentKeys() {
        let firstQueue = DispatchQueue(label: "test.first")
        let firstKey = DispatchSpecificKey<Void>()
        firstQueue.setSpecific(key: firstKey, value: ())
        let secondQueue = DispatchQueue(label: "test.second")
        let secondKey = DispatchSpecificKey<Void>()
        secondQueue.setSpecific(key: secondKey, value: ())
        let completed = expectation(description: "Work executes on the second queue")

        firstQueue.async {
            runOnQueueSync(secondQueue, key: secondKey) {
                XCTAssertNotNil(DispatchQueue.getSpecific(key: secondKey))
                XCTAssertNil(DispatchQueue.getSpecific(key: firstKey))
            }
            XCTAssertNotNil(DispatchQueue.getSpecific(key: firstKey))
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
    }

    @MainActor
    func testRunOnMainThreadSyncRunsInlineAndReturnsValue() {
        XCTAssertTrue(Thread.isMainThread)
        var didExecute = false

        let value = runOnMainThreadSync {
            XCTAssertTrue(Thread.isMainThread)
            didExecute = true
            return 42
        }

        XCTAssertTrue(didExecute)
        XCTAssertEqual(value, 42)
    }

    @MainActor
    func testRunOnMainThreadSyncRethrowsOnMainThread() {
        XCTAssertTrue(Thread.isMainThread)

        XCTAssertThrowsError(try runOnMainThreadSync {
            XCTAssertTrue(Thread.isMainThread)
            throw TestError.expected
        }) { error in
            XCTAssertEqual(error as? TestError, .expected)
        }
    }

    func testRunOnMainThreadSyncExecutesOnMainThreadAndReturnsValueFromBackground() async {
        let completed = expectation(description: "Background caller receives the main-thread result")

        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            let value = runOnMainThreadSync {
                XCTAssertTrue(Thread.isMainThread)
                return 42
            }
            XCTAssertEqual(value, 42)
            XCTAssertFalse(Thread.isMainThread)
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 5)
    }

    func testRunOnMainThreadSyncRethrowsToBackgroundCaller() async {
        let completed = expectation(description: "Background caller receives the main-thread error")

        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            do {
                try runOnMainThreadSync {
                    XCTAssertTrue(Thread.isMainThread)
                    throw TestError.expected
                }
                XCTFail("Expected the block error to be rethrown")
            } catch {
                XCTAssertEqual(error as? TestError, .expected)
            }
            XCTAssertFalse(Thread.isMainThread)
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 5)
    }
}
