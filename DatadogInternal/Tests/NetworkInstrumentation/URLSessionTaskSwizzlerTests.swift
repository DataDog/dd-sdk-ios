/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

final class URLSessionTaskSwizzlerTests: XCTestCase {
    override func tearDown() {
        URLSessionTaskSwizzler.unbind()
        XCTAssertNil(URLSessionTaskSwizzler.resume as Any?)

        super.tearDown()
    }

    func testSwizzling() throws {
        let expectation = XCTestExpectation(description: "resume")
        try URLSessionTaskSwizzler.bind { _ in
            expectation.fulfill()
        }

        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)
        task.resume()

        wait(for: [expectation], timeout: 5)
    }

    func testBindings() {
        XCTAssertNil(URLSessionTaskSwizzler.resume as Any?)

        try? URLSessionTaskSwizzler.bind(interceptResume: { _ in })
        XCTAssertNotNil(URLSessionTaskSwizzler.resume as Any?)

        try? URLSessionTaskSwizzler.bind(interceptResume: { _ in })
        XCTAssertNotNil(URLSessionTaskSwizzler.resume as Any?)

        URLSessionTaskSwizzler.unbind()
        XCTAssertNil(URLSessionTaskSwizzler.resume as Any?)
    }

    func testConcurrentBinding() throws {
        // swiftlint:disable opening_brace trailing_closure
         callConcurrently(
            closures: [
                { try? URLSessionTaskSwizzler.bind(interceptResume: self.intercept(task:)) },
                { URLSessionTaskSwizzler.unbind() },
                { try? URLSessionTaskSwizzler.bind(interceptResume: self.intercept(task:)) },
                { URLSessionTaskSwizzler.unbind() },
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace trailing_closure
    }

    func intercept(task: URLSessionTask) {
    }
}
