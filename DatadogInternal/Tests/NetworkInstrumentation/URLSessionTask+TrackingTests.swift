/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class URLSessionTaskTrackingTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var session: URLSession!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        session = URLSession(configuration: .ephemeral)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    // MARK: - Prepare Once

    func testPrepareOnce_whenCalledRepeatedly_itPreparesOnce() {
        let task = session.dataTask(with: URL.mockAny())
        let identifier = UUID()
        var preparations = 0

        task.dd.prepareOnce(for: identifier) { preparations += 1 }
        task.dd.prepareOnce(for: identifier) { preparations += 1 }

        XCTAssertEqual(preparations, 1)
    }

    func testPrepareOnce_whenIdentifiersDiffer_itPreparesOncePerIdentifier() {
        let task = session.dataTask(with: URL.mockAny())
        let first = UUID()
        let second = UUID()
        var preparations: [UUID] = []

        task.dd.prepareOnce(for: first) { preparations.append(first) }
        task.dd.prepareOnce(for: second) { preparations.append(second) }
        task.dd.prepareOnce(for: first) { preparations.append(first) }
        task.dd.prepareOnce(for: second) { preparations.append(second) }

        XCTAssertEqual(preparations, [first, second])
    }

    func testPrepareOnce_whenTaskIsCompleted_itDoesNotPrepare() {
        let cancelled = expectation(description: "Unstarted task finishes cancellation")
        let task = session.dataTask(with: URL.mockAny()) { _, _, _ in cancelled.fulfill() }
        task.cancel()
        wait(for: [cancelled], timeout: 5)
        XCTAssertEqual(task.state, .completed)
        var preparations = 0

        task.dd.prepareOnce(for: UUID()) { preparations += 1 }

        XCTAssertEqual(preparations, 0)
    }

    func testPrepareOnce_whenCalledConcurrently_otherCallersWaitForThePreparation() {
        let task = session.dataTask(with: URL.mockAny())
        let identifier = UUID()
        let events = ReadWriteLock(wrappedValue: [String]())
        let preparing = expectation(description: "First caller is preparing")
        let secondCalling = expectation(description: "Second caller is calling")
        let returned = expectation(description: "Both callers returned")
        returned.expectedFulfillmentCount = 2
        let releasePreparation = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            task.dd.prepareOnce(for: identifier) {
                preparing.fulfill()
                XCTAssertEqual(releasePreparation.wait(timeout: .now() + 5), .success)
                events.mutate { $0.append("prepared") }
            }
            returned.fulfill()
        }
        wait(for: [preparing], timeout: 5)
        DispatchQueue.global().async {
            secondCalling.fulfill()
            task.dd.prepareOnce(for: identifier) { events.mutate { $0.append("prepared again") } }
            events.mutate { $0.append("second caller returned") }
            returned.fulfill()
        }
        wait(for: [secondCalling], timeout: 5)
        releasePreparation.signal()
        wait(for: [returned], timeout: 5)

        XCTAssertEqual(events.wrappedValue, ["prepared", "second caller returned"])
    }

    func testPrepareOnce_whenTasksDiffer_itPreparesThemIndependently() {
        // Tasks from different sessions can share a `taskIdentifier`.
        let otherSession = URLSession(configuration: .ephemeral)
        defer { otherSession.invalidateAndCancel() }
        let blockedTask = session.dataTask(with: URL.mockAny())
        let otherTask = otherSession.dataTask(with: URL.mockAny())
        XCTAssertEqual(blockedTask.taskIdentifier, otherTask.taskIdentifier)
        let identifier = UUID()
        let preparing = expectation(description: "Blocked task is preparing")
        let returned = expectation(description: "Blocked task returned")
        let releasePreparation = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            blockedTask.dd.prepareOnce(for: identifier) {
                preparing.fulfill()
                XCTAssertEqual(releasePreparation.wait(timeout: .now() + 5), .success)
            }
            returned.fulfill()
        }
        wait(for: [preparing], timeout: 5)
        var otherPrepared = false
        otherTask.dd.prepareOnce(for: identifier) { otherPrepared = true }
        releasePreparation.signal()
        wait(for: [returned], timeout: 5)

        XCTAssertTrue(otherPrepared, "Another task must prepare while the first one is still preparing")
    }
}
