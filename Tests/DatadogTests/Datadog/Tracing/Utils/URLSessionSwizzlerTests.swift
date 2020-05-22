/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

// TODO: RUMM-300 plug DDTracer into swizzled methods

class URLSessionSwizzlerTests: XCTestCase {
    func test_swizzleDataTaskWithURL() {
        defer {
            try! MethodSwizzler.shared.unswizzle(
                selector: URLSessionSwizzler.Selectors.DataTaskWithURL,
                in: URLSessionSwizzler.subjectClass
            )
        }

        let session = URLSession(configuration: .default)

        XCTAssertNoThrow(try URLSessionSwizzler.swizzleDataTaskWithURL())

        let url = URL(string: "http://foo.bar")!
        let task = session.dataTask(with: url)

        XCTAssertEqual(task.originalRequest?.url, url)
    }

    func test_unswizzleDataTaskWithURL() {
        let session = URLSession(configuration: .default)

        XCTAssertNoThrow(try URLSessionSwizzler.swizzleDataTaskWithURL())

        let url = URL(string: "http://foo.bar")!
        let task = session.dataTask(with: url)

        XCTAssertEqual(task.originalRequest?.url, url)

        try! MethodSwizzler.shared.unswizzle(
            selector: URLSessionSwizzler.Selectors.DataTaskWithURL,
            in: URLSessionSwizzler.subjectClass
        )

        let unswizzledTask = session.dataTask(with: url)
        XCTAssertEqual(unswizzledTask.originalRequest?.url, url)
    }

    func test_swizzleDataTaskWithRequest() {
        defer {
            try! MethodSwizzler.shared.unswizzle(
                selector: URLSessionSwizzler.Selectors.DataTaskWithRequest,
                in: URLSessionSwizzler.subjectClass
            )
        }

        let session = URLSession(configuration: .default)

        XCTAssertNoThrow(try URLSessionSwizzler.swizzleDataTaskWithRequest())

        let url = URL(string: "http://foo.bar")!
        let request = URLRequest(url: url)
        let task = session.dataTask(with: request)

        XCTAssertEqual(task.originalRequest?.url, url)
    }

    func test_swizzleDataTaskWithURLCompletion() {
        defer {
            try! MethodSwizzler.shared.unswizzle(
                selector: URLSessionSwizzler.Selectors.DataTaskWithURLCompletion,
                in: URLSessionSwizzler.subjectClass
            )
        }

        let session = URLSession(configuration: .default)

        XCTAssertNoThrow(try URLSessionSwizzler.swizzleDataTaskWithURLCompletionHandler())

        let asyncExpc = expectation(description: "completion handler expectation")
        let url = URL(string: "http://foo.bar")!
        let task = session.dataTask(with: url) { _,_,_ in asyncExpc.fulfill() }

        XCTAssertEqual(task.originalRequest?.url, url)

        task.resume()
        wait(for: [asyncExpc], timeout: 0.1)
    }

    func test_swizzleDataTaskWithRequestCompletion() {
        defer {
            try! MethodSwizzler.shared.unswizzle(
                selector: URLSessionSwizzler.Selectors.DataTaskWithRequestCompletion,
                in: URLSessionSwizzler.subjectClass
            )
        }

        let session = URLSession(configuration: .default)

        XCTAssertNoThrow(try URLSessionSwizzler.swizzleDataTaskWithRequestCompletionHandler())

        let asyncExpc = expectation(description: "completion handler expectation")
        let url = URL(string: "http://foo.bar")!
        let request = URLRequest(url: url)
        let task = session.dataTask(with: request) { _,_,_ in asyncExpc.fulfill() }

        XCTAssertEqual(task.originalRequest?.url, url)

        task.resume()
        wait(for: [asyncExpc], timeout: 0.1)
    }
}
