/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

final class URLSessionSwizzlerTests: XCTestCase {
    override func tearDown() {
        URLSessionSwizzler.unbind()
        XCTAssertNil(URLSessionSwizzler.dataTaskWithURLRequestAndCompletion as Any?)

        super.tearDown()
    }

    func testSwizzling_dataTaskWithURLRequestAndCompletion() throws {
        let didInterceptRequest = XCTestExpectation(description: "interceptURLRequest")
        let didInterceptTask = XCTestExpectation(description: "interceptTask")
        try URLSessionSwizzler.bind(interceptURLRequest: { request in
            didInterceptRequest.fulfill()
            return self.interceptRequest(request: request)
        }, interceptTask: { _ in
            didInterceptTask.fulfill()
        })

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
        try URLSessionSwizzler.bind(interceptURLRequest: { request in
            didInterceptRequest.fulfill()
            return self.interceptRequest(request: request)
        }, interceptTask: { _ in
            didInterceptTask.fulfill()
        })

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

    func testBindings() {
        XCTAssertNil(URLSessionSwizzler.dataTaskWithURLRequestAndCompletion as Any?)

        try? URLSessionSwizzler.bind(interceptURLRequest: self.interceptRequest(request:), interceptTask: self.interceptTask(task:))
        XCTAssertNotNil(URLSessionSwizzler.dataTaskWithURLRequestAndCompletion as Any?)

        try? URLSessionSwizzler.bind(interceptURLRequest: self.interceptRequest(request:), interceptTask: self.interceptTask(task:))
        XCTAssertNotNil(URLSessionSwizzler.dataTaskWithURLRequestAndCompletion as Any?)

        URLSessionSwizzler.unbind()
        XCTAssertNil(URLSessionSwizzler.dataTaskWithURLRequestAndCompletion as Any?)
    }

    func testConcurrentBinding() throws {
        // swiftlint:disable opening_brace trailing_closure
         callConcurrently(
            closures: [
                { try? URLSessionSwizzler.bind(interceptURLRequest: self.interceptRequest(request:), interceptTask: self.interceptTask(task:)) },
                { URLSessionSwizzler.unbind() },
                { try? URLSessionSwizzler.bind(interceptURLRequest: self.interceptRequest(request:), interceptTask: self.interceptTask(task:)) },
                { URLSessionSwizzler.unbind() },
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace trailing_closure
    }

    func interceptRequest(request: URLRequest) -> URLRequest {
        return request
    }

    func interceptTask(task: URLSessionTask) {
    }
}
