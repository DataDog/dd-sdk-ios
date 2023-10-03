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
        XCTAssertNil(URLSessionSwizzler.dataTaskWithURLRequest as Any?)

        super.tearDown()
    }

    func testSwizzling_dataTaskWithURLRequestAndCompletion() throws {
        let expectation = XCTestExpectation(description: "dataTaskWithURLRequestAndCompletion")
        try URLSessionSwizzler.bind { request in
            expectation.fulfill()
            return self.interceptRequest(request: request)
        }

        let session = URLSession(configuration: .default)
        let request = URLRequest(url: URL(string: "https://www.datadoghq.com/")!)
        let task = session.dataTask(with: request) { _, _, _ in }
        task.resume()

        wait(for: [expectation], timeout: 5)
    }

    func testSwizzling_testSwizzling_dataTaskWithURLRequest() throws {
        let expectation = XCTestExpectation(description: "dataTaskWithURLRequest")
        try URLSessionSwizzler.bind { request in
            expectation.fulfill()
            return self.interceptRequest(request: request)
        }

        let session = URLSession(configuration: .default)
        let request = URLRequest(url: URL(string: "https://www.datadoghq.com/")!)
        let task = session.dataTask(with: request)
        task.resume()

        wait(for: [expectation], timeout: 5)
    }

    func testBindings() {
        XCTAssertNil(URLSessionSwizzler.dataTaskWithURLRequestAndCompletion as Any?)

        try? URLSessionSwizzler.bind(interceptURLRequest: self.interceptRequest(request:))
        XCTAssertNotNil(URLSessionSwizzler.dataTaskWithURLRequestAndCompletion as Any?)

        try? URLSessionSwizzler.bind(interceptURLRequest: self.interceptRequest(request:))
        XCTAssertNotNil(URLSessionSwizzler.dataTaskWithURLRequestAndCompletion as Any?)

        URLSessionSwizzler.unbind()
        XCTAssertNil(URLSessionSwizzler.dataTaskWithURLRequestAndCompletion as Any?)
    }

    func testConcurrentBinding() throws {
        // swiftlint:disable opening_brace trailing_closure
         callConcurrently(
            closures: [
                { try? URLSessionSwizzler.bind(interceptURLRequest: self.interceptRequest(request:)) },
                { URLSessionSwizzler.unbind() },
                { try? URLSessionSwizzler.bind(interceptURLRequest: self.interceptRequest(request:)) },
                { URLSessionSwizzler.unbind() },
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace trailing_closure
    }

    func interceptRequest(request: URLRequest) -> URLRequest {
        return request
    }
}
