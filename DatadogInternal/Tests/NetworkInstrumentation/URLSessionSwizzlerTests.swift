/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogInternal

class URLSessionSwizzlerTests: XCTestCase {
    func testSwizzling_dataTaskWithCompletion() throws {
        let didInterceptCompletion = XCTestExpectation(description: "interceptCompletion")
        didInterceptCompletion.expectedFulfillmentCount = 2

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            interceptCompletionHandler: { _, _, _ in
                didInterceptCompletion.fulfill()
            }
        )

        let session = URLSession(configuration: .default)
        let url = URL(string: "https://www.datadoghq.com/")!
        session.dataTask(with: url) { _, _, _ in }.resume()
        session.dataTask(with: URLRequest(url: url)) { _, _, _ in }.resume()

        wait(for: [didInterceptCompletion], timeout: 5)
    }

    func testSwizzling_whenDidReceiveDataIsImplemented() throws {
        class MockDelegate: NSObject, URLSessionDataDelegate {
            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            }
        }

        let delegate = MockDelegate()
        let expectation = XCTestExpectation(description: "didReceiveData")

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            delegateClass: MockDelegate.self,
            interceptDidReceive: { _, _, _ in
                expectation.fulfill()
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)
        task.resume()

        wait(for: [expectation], timeout: 5)
    }

    func testSwizzling_whenDidReceiveDataNotImplemented() throws {
        class MockDelegate: NSObject, URLSessionDataDelegate {
        }

        let delegate = MockDelegate()
        let expectation = XCTestExpectation(description: "didReceiveData")

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            delegateClass: MockDelegate.self,
            interceptDidReceive: { _, _, _ in
                expectation.fulfill()
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)
        task.resume()

        wait(for: [expectation], timeout: 5)
    }

    func testSwizzling_taskResume() throws {
        let expectation = XCTestExpectation(description: "resume")

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            interceptResume: { _ in
                expectation.fulfill()
            }
        )

        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)
        task.resume()

        wait(for: [expectation], timeout: 5)
    }

    func testSwizzling_taskDelegate_whenMethodsAreImplemented() throws {
        class MockDelegate: NSObject, URLSessionTaskDelegate {
            func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) { }
            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { }
        }

        let delegate = MockDelegate()
        let didFinishCollecting = XCTestExpectation(description: "didFinishCollecting")
        let didCompleteWithError = XCTestExpectation(description: "didCompleteWithError")

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            delegateClass: MockDelegate.self,
            interceptDidFinishCollecting: { _, _, _ in
                didFinishCollecting.fulfill()
            }
        )

        try swizzler.swizzle(
            delegateClass: MockDelegate.self,
            interceptDidCompleteWithError: { _, _, _ in
                didCompleteWithError.fulfill()
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)
        task.resume()

        wait(for: [didFinishCollecting, didCompleteWithError], timeout: 5)
    }

    func testSwizzling_taskDelegate_whenMethodsAreNotImplemented() throws {
        class MockDelegate: NSObject, URLSessionTaskDelegate {
        }

        let delegate = MockDelegate()
        let didFinishCollecting = XCTestExpectation(description: "didFinishCollecting")
        let didCompleteWithError = XCTestExpectation(description: "didCompleteWithError")

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            delegateClass: MockDelegate.self,
            interceptDidFinishCollecting: { _, _, _ in
                didFinishCollecting.fulfill()
            }
        )

        try swizzler.swizzle(
            delegateClass: MockDelegate.self,
            interceptDidCompleteWithError: { _, _, _ in
                didCompleteWithError.fulfill()
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)
        task.resume()

        wait(for: [didFinishCollecting, didCompleteWithError], timeout: 5)
    }
}
