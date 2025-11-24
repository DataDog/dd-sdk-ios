/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogInternal

class URLSessionTaskStateSwizzlerTests: XCTestCase {
    func testSwizzling_setState_interceptsCompletion() throws {
        let stateChanges: [(state: Int, taskURL: String)] = [(1, ""), (3, "")]
        let expectation = self.expectation(description: "setState completion")
        expectation.expectedFulfillmentCount = stateChanges.count
        
        var interceptedStates: [Int] = []
        
        // Given
        let swizzler = URLSessionTaskStateSwizzler()
        
        try swizzler.swizzle(
            interceptSetState: { task, state in
                interceptedStates.append(state)
                expectation.fulfill()
            }
        )
        
        // When
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://www.datadoghq.com/")!
        let task = session.dataTask(with: url) { _, _, _ in }
        task.resume()
        
        // Then
        wait(for: [expectation], timeout: 5)
        
        // Verify we intercepted state changes (at least Running and Completed)
        XCTAssertTrue(interceptedStates.contains(where: { $0 == 1 }), "Should intercept Running state")
        XCTAssertTrue(interceptedStates.contains(where: { $0 >= 2 }), "Should intercept Canceling or Completed state")
        
        swizzler.unswizzle()
    }
    
    func testSwizzling_setState_unswizzleStopsInterception() throws {
        let expectation = self.expectation(description: "setState called once")
        expectation.expectedFulfillmentCount = 1
        expectation.assertForOverFulfill = true
        
        // Given
        let swizzler = URLSessionTaskStateSwizzler()
        
        try swizzler.swizzle(
            interceptSetState: { _, _ in
                expectation.fulfill()
            }
        )
        
        // When - First task is intercepted
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://www.datadoghq.com/")!
        let task1 = session.dataTask(with: url) { _, _, _ in }
        task1.resume()
        
        wait(for: [expectation], timeout: 5)
        
        // Unswizzle
        swizzler.unswizzle()
        
        // When - Second task should NOT be intercepted
        let task2 = session.dataTask(with: url) { _, _, _ in }
        task2.resume()
        
        // Then - expectation should have been fulfilled exactly once (from task1)
        // If task2 was intercepted, expectation would be overfulfilled
    }
    
    func testSwizzling_setState_interceptsAsyncAwaitTasks() async throws {
        let expectation = self.expectation(description: "setState for async/await")
        expectation.expectedFulfillmentCount = 2 // At least Running and Completed
        
        // Given
        let swizzler = URLSessionTaskStateSwizzler()
        
        try swizzler.swizzle(
            interceptSetState: { _, state in
                // Track state changes for async/await task
                if state >= 1 { // Running or higher
                    expectation.fulfill()
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
        await fulfillment(of: [expectation], timeout: 5)
        
        swizzler.unswizzle()
    }
    
    func testSwizzling_setState_interceptsDelegatelessTasks() throws {
        let expectation = self.expectation(description: "setState for delegate-less task")
        expectation.expectedFulfillmentCount = 2 // At least Running and Completed
        
        var completionStateIntercepted = false
        
        // Given
        let swizzler = URLSessionTaskStateSwizzler()
        
        try swizzler.swizzle(
            interceptSetState: { _, state in
                expectation.fulfill()
                if state >= 2 { // Canceling or Completed
                    completionStateIntercepted = true
                }
            }
        )
        
        // When - Create task without delegate and without completion handler
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://www.datadoghq.com/")!
        let task = session.dataTask(with: url)
        task.resume()
        
        // Then
        wait(for: [expectation], timeout: 5)
        XCTAssertTrue(completionStateIntercepted, "Should intercept completion state (>= 2)")
        
        swizzler.unswizzle()
    }
}

