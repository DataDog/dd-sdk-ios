/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

import TestUtilities
@testable import DatadogInternal

class URLSessionTaskDelegateSwizzlerTests: XCTestCase {
    func testSwizzling_implementedMethods() throws {
        let delegate = SessionTaskDelegateMock()
        let didFinishCollecting = expectation(description: "didFinishCollecting")
        let didCompleteWithError = expectation(description: "didCompleteWithError")

        // Given
        let swizzler = URLSessionTaskDelegateSwizzler()

        try swizzler.swizzle(
            delegateClass: SessionTaskDelegateMock.self,
            interceptDidFinishCollecting: { _, _, _ in
                didFinishCollecting.fulfill()
            },
            interceptDidCompleteWithError: { _, _, _ in
                didCompleteWithError.fulfill()
            }
        )

        // When
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let url = URL(string: "https://www.datadoghq.com/")!
        session
            .dataTask(with: url)
            .resume() // intercepted

        wait(for: [didFinishCollecting, didCompleteWithError], timeout: 5)
    }

    func testSwizzling_whenMethodsNotImplemented() throws {
        let delegate = SessionDataDelegateMock()
        let didFinishCollecting = expectation(description: "didFinishCollecting")
        let didCompleteWithError = expectation(description: "didCompleteWithError")

        // Given
        let swizzler = URLSessionTaskDelegateSwizzler()

        try swizzler.swizzle(
            delegateClass: SessionDataDelegateMock.self,
            interceptDidFinishCollecting: { _, _, _ in
                didFinishCollecting.fulfill()
            },
            interceptDidCompleteWithError: { _, _, _ in
                didCompleteWithError.fulfill()
            }
        )

        // When
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let url = URL(string: "https://www.datadoghq.com/")!
        session
            .dataTask(with: url)
            .resume() // intercepted

        wait(for: [didFinishCollecting, didCompleteWithError], timeout: 5)
    }

    func testUnSwizzling() throws {
        let delegate: URLSessionTaskDelegate = SessionDataDelegateMock()
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: URL.mockAny())
        var interceptionCount = 0

        // Given
        let swizzler = URLSessionTaskDelegateSwizzler()

        try swizzler.swizzle(
            delegateClass: SessionDataDelegateMock.self,
            interceptDidFinishCollecting: { _, _, _ in
                interceptionCount += 1
            },
            interceptDidCompleteWithError: { _, _, _ in
                interceptionCount += 1
            }
        )

        delegate.urlSession?(session, task: task, didFinishCollecting: .mockAny()) // intercepted
        delegate.urlSession?(session, task: task, didCompleteWithError: nil) // intercepted
        XCTAssertEqual(interceptionCount, 2)

        // When
        swizzler.unswizzle()

        // Then
        delegate.urlSession?(session, task: task, didFinishCollecting: .mockAny()) // not intercepted
        delegate.urlSession?(session, task: task, didCompleteWithError: nil) // not intercepted
        XCTAssertEqual(interceptionCount, 2)
    }
}
