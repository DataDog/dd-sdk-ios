/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

final class URLSessionDataDelegateSwizzlerTests: XCTestCase {
    override func tearDown() {
        URLSessionDataDelegateSwizzler.unbind(delegateClass: MockDelegate.self)
        XCTAssertEqual(URLSessionDataDelegateSwizzler.didReceiveMap.count, 0)

        super.tearDown()
    }

    func testSwizzling_whenDidReceiveDataIsImplemented() throws {
        class MockDelegate: NSObject, URLSessionDataDelegate {
            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            }
        }

        let delegate = MockDelegate()
        let expectation = XCTestExpectation(description: "didReceiveData")

        try URLSessionDataDelegateSwizzler.bind(delegateClass: MockDelegate.self) { _, _, _ in
            expectation.fulfill()
        }

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

        try URLSessionDataDelegateSwizzler.bind(delegateClass: MockDelegate.self) { _, _, _ in
            expectation.fulfill()
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: URL(string: "https://www.datadoghq.com/")!)
        task.resume()

        wait(for: [expectation], timeout: 5)
    }

    func testBindings() throws {
        XCTAssertNil(URLSessionDataDelegateSwizzler.didReceiveMap[MetaTypeExtensions.key(from: MockDelegate.self)] as Any?)

        try URLSessionDataDelegateSwizzler.bind(delegateClass: MockDelegate.self, interceptDidReceive: { _, _, _ in })
        XCTAssertNotNil(URLSessionDataDelegateSwizzler.didReceiveMap[MetaTypeExtensions.key(from: MockDelegate.self)] as Any?)

        try URLSessionDataDelegateSwizzler.bind(delegateClass: MockDelegate.self, interceptDidReceive: { _, _, _ in })
        XCTAssertNotNil(URLSessionDataDelegateSwizzler.didReceiveMap[MetaTypeExtensions.key(from: MockDelegate.self)] as Any?)

        URLSessionDataDelegateSwizzler.unbind(delegateClass: MockDelegate.self)
        XCTAssertNil(URLSessionDataDelegateSwizzler.didReceiveMap[MetaTypeExtensions.key(from: MockDelegate.self)] as Any?)
    }

    func testConcurrentBinding() throws {
        // swiftlint:disable opening_brace trailing_closure
        callConcurrently(
            closures: [
                { try? URLSessionDataDelegateSwizzler.bind(delegateClass: MockDelegate.self, interceptDidReceive: self.intercept(_:dataTask:didReceive:)) },
                { URLSessionDataDelegateSwizzler.unbind(delegateClass: MockDelegate.self) },
                { try? URLSessionDataDelegateSwizzler.bind(delegateClass: MockDelegate.self, interceptDidReceive: self.intercept(_:dataTask:didReceive:)) },
                { URLSessionDataDelegateSwizzler.unbind(delegateClass: MockDelegate.self) },
            ],
            iterations: 50
        )
        // swiftlint:enable opening_brace trailing_closure
    }

    func intercept(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    }

    class MockDelegate: NSObject, URLSessionDataDelegate {
    }
}
