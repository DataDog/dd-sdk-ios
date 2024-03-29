/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogInternal

class URLSessionDataDelegateSwizzlerTests: XCTestCase {
    func testSwizzling_implementedMethods() throws {
        class MockDelegate: NSObject, URLSessionDataDelegate {
            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { }
            func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) { }
            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { }
        }

        let delegate = MockDelegate()
        let didReceiveData = expectation(description: "didReceiveData")
        didReceiveData.assertForOverFulfill = false

        // Given
        let swizzler = URLSessionDataDelegateSwizzler()

        try swizzler.swizzle(
            delegateClass: MockDelegate.self,
            interceptDidReceive: { _, _, _ in
                didReceiveData.fulfill()
            }
        )

        // When
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let url = URL(string: "https://www.datadoghq.com/")!
        session
            .dataTask(with: url)
            .resume() // intercepted

        wait(for: [didReceiveData], timeout: 5)
    }

    func testSwizzling_whenMethodsNotImplemented() throws {
        class MockDelegate: NSObject, URLSessionDataDelegate {
        }

        let delegate = MockDelegate()
        let didReceiveData = expectation(description: "didReceiveData")
        didReceiveData.assertForOverFulfill = false

        // Given
        let swizzler = URLSessionDataDelegateSwizzler()

        try swizzler.swizzle(
            delegateClass: MockDelegate.self,
            interceptDidReceive: { _, _, _ in
                didReceiveData.fulfill()
            }
        )

        // When
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let url = URL(string: "https://www.datadoghq.com/")!
        session
            .dataTask(with: url)
            .resume() // intercepted

        wait(for: [didReceiveData], timeout: 5)
    }

    func testUnSwizzling() throws {
        class MockDelegate: NSObject, URLSessionDataDelegate {
        }

        let delegate = MockDelegate()
        let expectation = self.expectation(description: "not expected")
        expectation.isInverted = true

        // Given
        let swizzler = URLSessionDataDelegateSwizzler()

        try swizzler.swizzle(
            delegateClass: MockDelegate.self,
            interceptDidReceive: { _, _, _ in
                expectation.fulfill()
            }
        )

        // When
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let url = URL(string: "https://www.datadoghq.com/")!
        session
            .dataTask(with: url)
            .resume() // not intercepted

        swizzler.unswizzle()

        waitForExpectations(timeout: 5)
    }
}
