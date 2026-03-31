/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest

extension XCTestCase {
    /// Calls given closures concurrently from multiple threads.
    /// Each closure is called only once.
    public func callConcurrently(
        _ closure1: @escaping () -> Void,
        _ closure2: @escaping () -> Void,
        _ closure3: (() -> Void)? = nil,
        _ closure4: (() -> Void)? = nil,
        _ closure5: (() -> Void)? = nil,
        _ closure6: (() -> Void)? = nil
    ) {
        callConcurrently(
            closures: [closure1, closure2, closure3, closure4, closure5, closure6].compactMap { $0 },
            iterations: 1
        )
    }

    /// Calls given closures concurrently from multiple threads.
    /// Each closure will be called the number of times given by `iterations` count.
    public func callConcurrently(closures: [() -> Void], iterations: Int = 1) {
        var moreClosures: [() -> Void] = []
        (0..<iterations).forEach { _ in moreClosures.append(contentsOf: closures) }
        let randomizedClosures = moreClosures.shuffled()

        DispatchQueue.concurrentPerform(iterations: randomizedClosures.count) { iteration in
            randomizedClosures[iteration]()
        }
    }

    /// Calls given closures concurrently from multiple threads.
    /// Each closure will be called the number of times given by `iterations` count and iteration number passed as parameter.
    public func callConcurrently(closures: [(Int) -> Void], iterations: Int = 1) {
        var moreClosures: [(Int) -> Void] = []
        (0..<iterations).forEach { _ in moreClosures.append(contentsOf: closures) }
        let randomizedClosures = moreClosures.shuffled()

        DispatchQueue.concurrentPerform(iterations: randomizedClosures.count) { iteration in
            randomizedClosures[iteration](iteration)
        }
    }

    /// Waits until given `condition` returns `true` and then fulfills the `expectation`.
    /// It executes `condition()` block on the main thread, in every run loop.
    public func wait(until condition: @escaping () -> Bool, andThenFulfill expectation: XCTestExpectation) {
        if condition() {
            expectation.fulfill()
        } else {
            OperationQueue.main.addOperation { [weak self] in
                self?.wait(until: condition, andThenFulfill: expectation)
            }
        }
    }

    /// Simple helper for asynchronous testing.
    ///
    /// - Parameters:
    ///   - timeout: amount of time in seconds to wait before executing the closure.
    ///   - closure: a closure to execute when `timeout` seconds has passed
    public func wait(during timeout: TimeInterval, closure: @escaping () -> Void) {
        let expectation = self.expectation(description: "")
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            expectation.fulfill()
        }

        self.waitForExpectations(timeout: timeout + 0.1)
        closure()
    }

    @available(iOS 13.0, tvOS 13.0, *)
    public func dd_fulfillment(
        for expectations: [XCTestExpectation],
        timeout seconds: TimeInterval = .infinity,
        enforceOrder enforceOrderOfFulfillment: Bool = false) async {
#if compiler(>=5.8)
            await fulfillment(of: expectations, timeout: seconds, enforceOrder: enforceOrderOfFulfillment)
#else
        wait(
            for: expectations,
            timeout: seconds,
            enforceOrder: enforceOrderOfFulfillment
        )
#endif
    }

    /// Creates and returns an expectation associated with the test case by setting `isInverted` to `true`.
    /// - Parameter description: This string will be displayed in the test log to help diagnose failures.
    /// - Returns: Inverted expectation.
    public func invertedExpectation(description: String) -> XCTestExpectation {
        let expectation = self.expectation(description: description)
        expectation.isInverted = true
        return expectation
    }

    /// Sends request to `url` using real `URLSession` instrumented with provided `delegate`.
    /// It returns the actual request that was sent to the server which can include additional headers set by the SDK.
    ///
    /// # Implementation note
    /// `completionHandler` runs as part of `session.dataTask`'s completion handler. This is useful to finish
    /// active (or parent) spans in a more realistic way. Here's a description of problem this solves.
    ///
    /// By the end of a request interception, the `DatadogURLSessionHandler.interceptionDidComplete(interception:)`
    /// method is called. In situations where a span should be created to trace this request, that span is created inside this
    /// method. This span can be a child of a currently active span, or a root span if no active span is present.
    ///
    /// If the SDK users want to trace a process that includes a request, one possibility is setting an active span before
    /// initiating the request, and finishing it when the request ends, using the `DataTask` completion handler. Given
    /// how interception implemented, `interceptionDidComplete(interception:)` runs after that completion
    /// handler, which means if the active span is removed on the completion handler, there would not be an active session
    /// any more.
    ///
    /// The SDK handles this situation (as well as if the SDK users immediately finish the active span after initiating the
    /// request), so this is not a problem. However, in tests, we want to make sure this happens as we expect.
    ///
    /// In this specific method, and unlike most real world code, we block the main thread waiting for test expectations
    /// after initiating the request. In the previous implementation, any active span would be terminated inside the test,
    /// after we returned from this method, meaning after the entire request interception finished. This would not test
    /// if the request interceptors handled correctly the fact the active session is gone by the end of the request, but still
    /// existed in the beginning. Therefore, `completionHandler` was added, and runs as part of the `DataTask`
    /// completion handler. This allows tests to finish active spans inside this completion handler, in a more realistic way,
    /// close to what real world apps would do.
    public func sendURLSessionRequest(to url: URL, using delegate: URLSessionDelegate? = nil, completionHandler: (() -> Void)? = nil) throws -> URLRequest {
        let server = ServerMock(delivery: .success(response: .mockAny(), data: .mockAny()))
        let session = server.getInterceptedURLSession(delegate: delegate)
        let taskCompleted = expectation(description: "wait for task completion")
        let task = session.dataTask(with: .mockWith(url: url)) { _, _, _ in
            completionHandler?()
            taskCompleted.fulfill()
        }
        task.resume()
        waitForExpectations(timeout: 5)

        let requests = server.waitAndReturnRequests(count: 1)
        return try XCTUnwrap(requests.first)
    }
}
