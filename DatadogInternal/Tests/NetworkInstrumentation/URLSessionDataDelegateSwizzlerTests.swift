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
        URLSessionDataDelegateSwizzler.unbind(delegateClass: MockDelegate1.self)
        URLSessionDataDelegateSwizzler.unbind(delegateClass: MockDelegate2.self)
        XCTAssertEqual(URLSessionDataDelegateSwizzler.didReceiveMap.count, 0)

        super.tearDown()
    }

    func testSwizzling_whenMultipleDelegatesAreGiven() throws {
        let delegate1 = MockDelegate1()
        let didReceiveData1 = XCTestExpectation(description: "didReceiveData1")
        try URLSessionDataDelegateSwizzler.bind(delegateClass: MockDelegate1.self) { _, _, _ in
            didReceiveData1.fulfill()
        }

        let didReceiveData2 = XCTestExpectation(description: "didReceiveData2")
        try URLSessionDataDelegateSwizzler.bind(delegateClass: MockDelegate2.self) { _, _, _ in
            didReceiveData2.fulfill()
        }

        let delegate2 = MockDelegate2()
        let session1 = URLSession(configuration: .default, delegate: delegate1, delegateQueue: nil)
        let task1 = session1.dataTask(with: URL(string: "https://www.datadoghq.com/")!)

        let session2 = URLSession(configuration: .default, delegate: delegate2, delegateQueue: nil)
        let task2 = session2.dataTask(with: URL(string: "https://www.datadoghq.com/")!)

        task1.resume()
        task2.resume()

        wait(for: [didReceiveData1, didReceiveData2], timeout: 5)
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

    class MockDelegate1: NSObject, URLSessionDataDelegate {
    }

    class MockDelegate2: NSObject, URLSessionDataDelegate {
    }
}
