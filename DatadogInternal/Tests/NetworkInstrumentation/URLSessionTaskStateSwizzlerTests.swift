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
    func testSwizzling_setState_interceptsCompletion() throws {
        let completionExpectation = self.expectation(description: "setState completion")
        completionExpectation.assertForOverFulfill = false // Allow multiple setState calls with same state
        var interceptedStates: [Int] = []

        // Given
        let swizzler = URLSessionTaskStateSwizzler()

        try swizzler.swizzle(
            interceptSetState: { _, state in
                interceptedStates.append(state)
                // Only fulfill when we see completed state
                if state == URLSessionTask.State.completed.rawValue {
                    completionExpectation.fulfill()
                }
            }
        )

        // When - Use localhost:1 for immediate connection failure
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://localhost:1")!
        let task = session.dataTask(with: url) { _, _, _ in }
        task.resume()

        // Then - Wait for completion state
        wait(for: [completionExpectation], timeout: 3)

        // Verify we intercepted state changes
        XCTAssertTrue(interceptedStates.contains(where: { $0 == URLSessionTask.State.running.rawValue }), "Should intercept running state")
        XCTAssertTrue(interceptedStates.contains(where: { $0 == URLSessionTask.State.completed.rawValue }), "Should intercept completed state")

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
                // Only fulfill when we see canceling or completed state
                if state >= URLSessionTask.State.canceling.rawValue {
                    completionExpectation.fulfill()
                }
            }
        )

        // When - Cancel task to trigger cancellation
        // Use a real remote URL: the task must be in-flight when cancel() is called
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://www.datadoghq.com/")!
        let task = session.dataTask(with: url) { _, _, _ in }
        task.resume()
        Thread.sleep(forTimeInterval: 0.1) // Let task start
        task.cancel() // Triggers running → canceling → completed (canceling state may be very brief)

        // Then - Wait for completion state
        wait(for: [completionExpectation], timeout: 3)

        // Verify we intercepted cancellation state
        // Note: Canceling state is very brief and may be missed due to timing - we may only see completed
        XCTAssertTrue(
            interceptedStates.contains(where: { $0 >= URLSessionTask.State.canceling.rawValue }),
            "Should intercept canceling or completed state"
        )

        swizzler.unswizzle()
    }

    func testSwizzling_setState_unswizzleStopsInterception() throws {
        let task1CompletedExpectation = self.expectation(description: "task1 reached completed state")
        task1CompletedExpectation.assertForOverFulfill = false // Allow multiple setState calls with same state

        var interceptionCount = 0

        // Given
        let swizzler = URLSessionTaskStateSwizzler()

        try swizzler.swizzle(
            interceptSetState: { _, state in
                interceptionCount += 1
                // Only fulfill once task1 has reached completed state, ensuring no more
                // setState: calls are pending before we snapshot the count and unswizzle.
                if state == URLSessionTask.State.completed.rawValue {
                    task1CompletedExpectation.fulfill()
                }
            }
        )

        // When - First task is intercepted
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://localhost:1")!
        let task1 = session.dataTask(with: url) { _, _, _ in }
        task1.resume()

        wait(for: [task1CompletedExpectation], timeout: 3)

        // Unswizzle
        swizzler.unswizzle()

        let countAfterTask1 = interceptionCount
        XCTAssertGreaterThanOrEqual(countAfterTask1, 2, "Task1 should have at least 2 state changes")

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
                // Only fulfill when we see completed state
                if state == URLSessionTask.State.completed.rawValue {
                    completionExpectation.fulfill()
                }
            }
        )

        // When - Use async/await API
        // Use localhost:1 to get an immediate connection refusal — fast, network-independent,
        // and URLSession still transitions the task through .running → .completed.
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://localhost:1")!

        Task {
            _ = try? await session.data(from: url)
        }

        // Then
        await fulfillment(of: [completionExpectation], timeout: 5)

        // Verify we intercepted completed state
        XCTAssertTrue(interceptedStates.contains(where: { $0 == URLSessionTask.State.completed.rawValue }), "Should intercept completed state")

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
                // Only fulfill when we see completed state
                if state == URLSessionTask.State.completed.rawValue {
                    completionExpectation.fulfill()
                }
            }
        )

        // When - Create task without delegate and without completion handler
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://localhost:1")!
        let task = session.dataTask(with: url)
        task.resume()

        // Then - Wait for completion state
        wait(for: [completionExpectation], timeout: 5)

        // Verify we intercepted completed state
        XCTAssertTrue(interceptedStates.contains(where: { $0 == URLSessionTask.State.completed.rawValue }), "Should intercept completed state")

        swizzler.unswizzle()
    }

    func testSwizzling_nwTaskComplete_interceptsCompletion() throws {
        guard #available(iOS 18.4, tvOS 18.4, macOS 15.4, watchOS 11.4, visionOS 2.4, *) else {
            throw XCTSkip("usesClassicLoadingMode requires iOS 18.4+")
        }
        guard URLSessionTaskStateSwizzler.NWTaskComplete.build() != nil else {
            throw XCTSkip("NW task completion not supported on this platform/version")
        }
        let completionExpectation = expectation(description: "NWURLSessionTask completion intercepted")

        // Given
        let swizzler = URLSessionTaskStateSwizzler()
        try swizzler.swizzle(interceptSetState: { _, state in
            if state == URLSessionTask.State.completed.rawValue {
                completionExpectation.fulfill()
            }
        })

        // When - usesClassicLoadingMode = false forces NWURLSessionTask instances
        let configuration = URLSessionConfiguration.ephemeral
        configuration.usesClassicLoadingMode = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://localhost:1")!) { _, _, _ in }
        let taskClassName = String(describing: type(of: task))
        XCTAssert(taskClassName.hasPrefix("NWURLSession"), "Expected NWURLSessionTask, got \(taskClassName)")
        task.resume()

        // Then
        wait(for: [completionExpectation], timeout: 5)
        swizzler.unswizzle()
    }
}
