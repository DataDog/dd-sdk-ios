/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogInternal

/// Tests for `URLSessionTaskStateSwizzler` which intercepts `setState:` on `URLSessionTask`.
///
/// **Important Note on `assertForOverFulfill`:**
/// URLSession's internal implementation can call `setState:` multiple times with the same state value.
/// For example, `Completed(3)` may be called twice in rapid succession from the same thread.
/// This is URLSession's internal behavior, not a bug in our swizzling.
/// Tests use `expectation.assertForOverFulfill = false` to handle this legitimate behavior.

class URLSessionTaskStateSwizzlerTests: XCTestCase {
    func testSwizzling_setState_interceptsSuccessfulCompletion() throws {
        let completionExpectation = self.expectation(description: "setState completion")
        completionExpectation.assertForOverFulfill = false // Allow multiple setState calls with same state
        var interceptedStates: [Int] = []

        // Given
        let swizzler = URLSessionTaskStateSwizzler()

        try swizzler.swizzle(
            interceptSetState: { _, state in
                interceptedStates.append(state)
                // Only fulfill when we see Completed state
                if state == 3 {
                    completionExpectation.fulfill()
                }
            }
        )

        // When
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://www.datadoghq.com/")!
        let task = session.dataTask(with: url) { _, _, _ in }
        task.resume()

        // Then - Wait for completion state
        wait(for: [completionExpectation], timeout: 3)

        // Verify we intercepted state changes (Running and Completed)
        XCTAssertTrue(interceptedStates.contains(where: { $0 == 1 }), "Should intercept Running state")
        XCTAssertTrue(interceptedStates.contains(where: { $0 == 3 }), "Should intercept Completed state")

        swizzler.unswizzle()
    }

    func testSwizzling_setState_interceptsFailedCompletion() throws {
        let completionExpectation = self.expectation(description: "setState completion")
        completionExpectation.assertForOverFulfill = false // Allow multiple setState calls with same state
        var interceptedStates: [Int] = []

        // Given
        let swizzler = URLSessionTaskStateSwizzler()

        try swizzler.swizzle(
            interceptSetState: { _, state in
                interceptedStates.append(state)
                // Only fulfill when we see Completed state
                if state == 3 {
                    completionExpectation.fulfill()
                }
            }
        )

        // When - Use invalid URL for immediate connection failure
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://localhost:1")!
        let task = session.dataTask(with: url) { _, _, _ in }
        task.resume()

        // Then - Wait for completion state
        wait(for: [completionExpectation], timeout: 3)

        // Verify we intercepted state changes (Running and Completed)
        XCTAssertTrue(interceptedStates.contains(where: { $0 == 1 }), "Should intercept Running state")
        XCTAssertTrue(interceptedStates.contains(where: { $0 == 3 }), "Should intercept Completed state")

        swizzler.unswizzle()
    }

    func testSwizzling_setState_interceptsCancelledTasks() throws {
        let completionExpectation = self.expectation(description: "setState completion for cancelled task")
        completionExpectation.assertForOverFulfill = false // Allow multiple setState calls with same state
        var interceptedStates: [Int] = []

        // Given
        let swizzler = URLSessionTaskStateSwizzler()

        try swizzler.swizzle(
            interceptSetState: { _, state in
                interceptedStates.append(state)
                // Only fulfill when we see a completion state (Canceling or Completed)
                if state >= 2 {
                    completionExpectation.fulfill()
                }
            }
        )

        // When - Cancel task to trigger cancellation
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://www.datadoghq.com/")!
        let task = session.dataTask(with: url) { _, _, _ in }
        task.resume()
        Thread.sleep(forTimeInterval: 0.1) // Let task start
        task.cancel() // Triggers Running → Canceling → Completed (Canceling state may be very brief)

        // Then - Wait for completion state
        wait(for: [completionExpectation], timeout: 3)

        // Verify we intercepted cancellation state
        // Note: Canceling (2) is very brief and may be missed due to timing - we may only see Completed (3)
        XCTAssertTrue(interceptedStates.contains(where: { $0 >= 2 }), "Should intercept Canceling or Completed state")

        swizzler.unswizzle()
    }

    func testSwizzling_setState_unswizzleStopsInterception() throws {
        let task1Expectation = self.expectation(description: "setState called for task1")
        task1Expectation.expectedFulfillmentCount = 2 // At least Running and Completed
        task1Expectation.assertForOverFulfill = false // Allow multiple setState calls with same state

        var interceptionCount = 0

        // Given
        let swizzler = URLSessionTaskStateSwizzler()

        try swizzler.swizzle(
            interceptSetState: { _, _ in
                interceptionCount += 1
                task1Expectation.fulfill()
            }
        )

        // When - First task is intercepted
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://www.datadoghq.com/")!
        let task1 = session.dataTask(with: url) { _, _, _ in }
        task1.resume()

        wait(for: [task1Expectation], timeout: 3)
        let countAfterTask1 = interceptionCount
        XCTAssertGreaterThanOrEqual(countAfterTask1, 2, "Task1 should have at least 2 state changes")

        // Unswizzle
        swizzler.unswizzle()

        // When - Second task should NOT be intercepted
        let task2 = session.dataTask(with: url) { _, _, _ in }
        task2.resume()

        // Give task2 time to complete
        Thread.sleep(forTimeInterval: 1)

        // Then - interception count should not have increased after unswizzle
        XCTAssertEqual(interceptionCount, countAfterTask1, "Task2 should not be intercepted after unswizzle")
    }

    @available(iOS 13.0, tvOS 13.0, *)
    func testSwizzling_setState_interceptsAsyncAwaitTasks() async throws {
        let completionExpectation = self.expectation(description: "setState for async/await")
        completionExpectation.assertForOverFulfill = false // Allow multiple setState calls with same state
        var interceptedStates: [Int] = []

        // Given
        let swizzler = URLSessionTaskStateSwizzler()

        try swizzler.swizzle(
            interceptSetState: { _, state in
                interceptedStates.append(state)
                // Only fulfill when we see Completed state
                if state == 3 {
                    completionExpectation.fulfill()
                }
            }
        )

        // When - Use async/await API
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://www.datadoghq.com/")!

        Task {
            _ = try? await session.data(from: url)
        }

        // Then
        await fulfillment(of: [completionExpectation], timeout: 5)

        // Verify we intercepted Completed state
        XCTAssertTrue(interceptedStates.contains(where: { $0 == 3 }), "Should intercept Completed state")

        swizzler.unswizzle()
    }

    func testSwizzling_setState_interceptsDelegatelessTasks() throws {
        let completionExpectation = self.expectation(description: "setState for delegate-less task")
        completionExpectation.assertForOverFulfill = false // Allow multiple setState calls with same state
        var interceptedStates: [Int] = []

        // Given
        let swizzler = URLSessionTaskStateSwizzler()

        try swizzler.swizzle(
            interceptSetState: { _, state in
                interceptedStates.append(state)
                // Only fulfill when we see Completed state
                if state == 3 {
                    completionExpectation.fulfill()
                }
            }
        )

        // When - Create task without delegate and without completion handler
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://www.datadoghq.com/")!
        let task = session.dataTask(with: url)
        task.resume()

        // Then - Wait for completion state
        wait(for: [completionExpectation], timeout: 5)

        // Verify we intercepted Completed state
        XCTAssertTrue(interceptedStates.contains(where: { $0 == 3 }), "Should intercept Completed state")

        swizzler.unswizzle()
    }
}
