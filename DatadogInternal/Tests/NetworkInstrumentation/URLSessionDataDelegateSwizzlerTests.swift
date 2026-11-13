/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

import TestUtilities
@testable import DatadogInternal

class URLSessionDataDelegateSwizzlerTests: XCTestCase {
    func testSwizzling_implementedMethods() throws {
        let delegate = SessionDataDelegateMock()
        let didReceiveData = expectation(description: "didReceiveData")
        didReceiveData.assertForOverFulfill = false

        // Given
        let swizzler = URLSessionDataDelegateSwizzler()

        try swizzler.swizzle(
            delegateClass: SessionDataDelegateMock.self,
            interceptDidReceive: { _, _, _ in
                didReceiveData.fulfill()
            }
        )

        // When
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        session
            .dataTask(with: URL.mockAny())
            .resume() // intercepted

        wait(for: [didReceiveData], timeout: 5)
    }

    func testSwizzling_whenMethodsNotImplemented() throws {
        let delegate = SessionDataDelegateMock()
        let didReceiveData = expectation(description: "didReceiveData")
        didReceiveData.assertForOverFulfill = false

        // Given
        let swizzler = URLSessionDataDelegateSwizzler()

        try swizzler.swizzle(
            delegateClass: SessionDataDelegateMock.self,
            interceptDidReceive: { _, _, _ in
                didReceiveData.fulfill()
            }
        )

        // When
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        session
            .dataTask(with: URL.mockAny())
            .resume() // intercepted

        wait(for: [didReceiveData], timeout: 5)
    }

    func testUnSwizzling() throws {
        let delegate: URLSessionDataDelegate = SessionDataDelegateMock()
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: URL.mockAny())
        var interceptionCount = 0

        // Given
        let swizzler = URLSessionDataDelegateSwizzler()

        try swizzler.swizzle(
            delegateClass: SessionDataDelegateMock.self,
            interceptDidReceive: { _, _, _ in
                interceptionCount += 1
            }
        )

        delegate.urlSession?(session, dataTask: task, didReceive: Data()) // intercepted
        XCTAssertEqual(interceptionCount, 1)

        // When
        swizzler.unswizzle()

        // Then
        delegate.urlSession?(session, dataTask: task, didReceive: Data()) // not intercepted
        XCTAssertEqual(interceptionCount, 1)
    }
}
