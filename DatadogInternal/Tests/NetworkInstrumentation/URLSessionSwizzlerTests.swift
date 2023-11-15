/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogInternal

class URLSessionSwizzlerTests: XCTestCase {
    func testSwizzling_dataTaskWithURLRequestAndCompletion() throws {
        let didInterceptRequest = XCTestExpectation(description: "interceptURLRequest")
        let didInterceptTask = XCTestExpectation(description: "interceptTask")

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            interceptRequest: { request in
                didInterceptRequest.fulfill()
                return request
            },
            interceptTask: { _ in
                didInterceptTask.fulfill()
            }
        )

        let session = URLSession(configuration: .default)
        let request = URLRequest(url: URL(string: "https://www.datadoghq.com/")!)
        let task = session.dataTask(with: request) { _, _, _ in }
        task.resume()

        wait(
            for: [
                didInterceptRequest,
                didInterceptTask
            ],
            timeout: 5,
            enforceOrder: true
        )
    }

    func testSwizzling_testSwizzling_dataTaskWithURLRequest() throws {
        // runs only on iOS 12 or below
        // because on iOS 12 and below `URLSession.dataTask(with:)` is implemented using `URLSession.dataTask(with:completionHandler:)`
        if #available(iOS 13.0, *) {
            return
        }

        let didInterceptRequest = XCTestExpectation(description: "interceptURLRequest")
        let didInterceptTask = XCTestExpectation(description: "interceptTask")

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            interceptRequest: { request in
                didInterceptRequest.fulfill()
                return request
            },
            interceptTask: { _ in
                didInterceptTask.fulfill()
            }
        )

        let session = URLSession(configuration: .default)
        let request = URLRequest(url: URL(string: "https://www.datadoghq.com/")!)
        let task = session.dataTask(with: request)
        task.resume()

        wait(
            for: [
                didInterceptRequest,
                didInterceptTask
            ],
            timeout: 5,
            enforceOrder: true
        )
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
            func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            }
        }

        let delegate = MockDelegate()
        let didFinishCollecting = XCTestExpectation(description: "didFinishCollecting")

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            delegateClass: MockDelegate.self,
            interceptDidFinishCollecting: { _, _, _ in
                didFinishCollecting.fulfill()
            },
            interceptDidCompleteWithError: { _, _, _ in
                didFinishCollecting.fulfill()
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)
        task.resume()

        wait(for: [didFinishCollecting], timeout: 5)
    }

    func testSwizzling_taskDelegate_whenMethodsAreNotImplemented() throws {
        class MockDelegate: NSObject, URLSessionTaskDelegate {
        }

        let delegate = MockDelegate()
        let didFinishCollecting = XCTestExpectation(description: "didFinishCollecting")

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            delegateClass: MockDelegate.self,
            interceptDidFinishCollecting: { _, _, _ in
                didFinishCollecting.fulfill()
            },
            interceptDidCompleteWithError: { _, _, _ in
                didFinishCollecting.fulfill()
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)
        task.resume()

        wait(for: [didFinishCollecting], timeout: 5)
    }
}
