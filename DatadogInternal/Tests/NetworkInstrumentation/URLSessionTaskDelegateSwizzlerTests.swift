/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

final class URLSessionTaskDelegateSwizzlerTests: XCTestCase {
    override func tearDown() {
        URLSessionTaskDelegateSwizzler.unbind(delegateClass: MockDelegate.self)
        URLSessionTaskDelegateSwizzler.unbind(delegateClass: MockDelegate1.self)
        URLSessionTaskDelegateSwizzler.unbind(delegateClass: MockDelegate2.self)
        XCTAssertEqual(URLSessionTaskDelegateSwizzler.didFinishCollectingMap.count, 0)

        super.tearDown()
    }

    func testSwizzling_whenMultipleDelegatesAreGiven() throws {
        let delegate1 = MockDelegate1()
        let didFinishCollecting1 = XCTestExpectation(description: "didFinishCollecting1")
        try URLSessionTaskDelegateSwizzler.bind(
            delegateClass: MockDelegate1.self,
            interceptDidFinishCollecting: { _, _, _ in
                didFinishCollecting1.fulfill()
            }, interceptDidCompleteWithError: { _, _, _ in
                didFinishCollecting1.fulfill()
            }
        )

        let delegate2 = MockDelegate2()
        let didFinishCollecting2 = XCTestExpectation(description: "didFinishCollecting2")
        try URLSessionTaskDelegateSwizzler.bind(
            delegateClass: MockDelegate2.self,
            interceptDidFinishCollecting: { _, _, _ in
                didFinishCollecting2.fulfill()
            }, interceptDidCompleteWithError: { _, _, _ in
                didFinishCollecting2.fulfill()
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate1, delegateQueue: nil)
        let task1 = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)

        let session2 = URLSession(configuration: .default, delegate: delegate2, delegateQueue: nil)
        let task2 = session2.dataTask(with: URL(string: "https://www.datadoghq.com/")!)

        task1.resume()
        task2.resume()

        wait(for: [didFinishCollecting1, didFinishCollecting2], timeout: 5)
    }

    func testSwizzling_whenMethodsAreImplemented() throws {
        class MockDelegate: NSObject, URLSessionTaskDelegate {
            func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            }
        }

        let delegate = MockDelegate()
        let didFinishCollecting = XCTestExpectation(description: "didFinishCollecting")

        try URLSessionTaskDelegateSwizzler.bind(
            delegateClass: MockDelegate.self,
            interceptDidFinishCollecting: { _, _, _ in
                didFinishCollecting.fulfill()
            }, interceptDidCompleteWithError: { _, _, _ in
                didFinishCollecting.fulfill()
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)
        task.resume()

        wait(for: [didFinishCollecting], timeout: 5)
    }

    func testSwizzling_whenMethodsAreNotImplemented() throws {
        class MockDelegate: NSObject, URLSessionTaskDelegate {
        }

        let delegate = MockDelegate()
        let didFinishCollecting = XCTestExpectation(description: "didFinishCollecting")

        try URLSessionTaskDelegateSwizzler.bind(
            delegateClass: MockDelegate.self,
            interceptDidFinishCollecting: { _, _, _ in
                didFinishCollecting.fulfill()
            }, interceptDidCompleteWithError: { _, _, _ in
                didFinishCollecting.fulfill()
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)
        task.resume()

        wait(for: [didFinishCollecting], timeout: 5)
    }

    func testBindings() throws {
        XCTAssertNil(URLSessionTaskDelegateSwizzler.didFinishCollectingMap[MetaTypeExtensions.key(from: MockDelegate.self)] as Any?)

        try URLSessionTaskDelegateSwizzler.bind(delegateClass: MockDelegate.self, interceptDidFinishCollecting: interceptDidFinishCollecting, interceptDidCompleteWithError: interceptDidCompleteWithError)
        XCTAssertNotNil(URLSessionTaskDelegateSwizzler.didFinishCollectingMap[MetaTypeExtensions.key(from: MockDelegate.self)] as Any?)
        XCTAssertNotNil(URLSessionTaskDelegateSwizzler.didCompleteWithErrorMap[MetaTypeExtensions.key(from: MockDelegate.self)] as Any?)

        try URLSessionTaskDelegateSwizzler.bind(delegateClass: MockDelegate.self, interceptDidFinishCollecting: interceptDidFinishCollecting, interceptDidCompleteWithError: interceptDidCompleteWithError)
        XCTAssertNotNil(URLSessionTaskDelegateSwizzler.didFinishCollectingMap[MetaTypeExtensions.key(from: MockDelegate.self)] as Any?)
        XCTAssertNotNil(URLSessionTaskDelegateSwizzler.didCompleteWithErrorMap[MetaTypeExtensions.key(from: MockDelegate.self)] as Any?)

        URLSessionTaskDelegateSwizzler.unbind(delegateClass: MockDelegate.self)
        XCTAssertNil(URLSessionTaskDelegateSwizzler.didFinishCollectingMap[MetaTypeExtensions.key(from: MockDelegate.self)] as Any?)
        XCTAssertNil(URLSessionTaskDelegateSwizzler.didCompleteWithErrorMap[MetaTypeExtensions.key(from: MockDelegate.self)] as Any?)
    }

    func testConcurrentBinding() throws {
        // swiftlint:disable opening_brace trailing_closure
         callConcurrently(
            closures: [
                { try? URLSessionTaskDelegateSwizzler.bind(delegateClass: MockDelegate.self, interceptDidFinishCollecting: self.intercept(session:task:metrics:), interceptDidCompleteWithError: self.interceptDidCompleteWithError(session:task:error:)) },
                { URLSessionTaskDelegateSwizzler.unbind(delegateClass: MockDelegate.self) },
                { try? URLSessionTaskDelegateSwizzler.bind(delegateClass: MockDelegate.self, interceptDidFinishCollecting: self.intercept(session:task:metrics:), interceptDidCompleteWithError: self.interceptDidCompleteWithError(session:task:error:)) },
                { URLSessionTaskDelegateSwizzler.unbind(delegateClass: MockDelegate.self) },
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace trailing_closure
    }

    func intercept(session: URLSession, task: URLSessionTask, metrics: URLSessionTaskMetrics) {
    }

    func interceptDidFinishCollecting(session: URLSession, task: URLSessionTask, metrics: URLSessionTaskMetrics) {
    }

    func interceptDidCompleteWithError(session: URLSession, task: URLSessionTask, error: Error?) {
    }

    class MockDelegate: NSObject, URLSessionTaskDelegate {
    }

    class MockDelegate1: NSObject, URLSessionTaskDelegate {
    }

    class MockDelegate2: NSObject, URLSessionTaskDelegate {
    }
}
