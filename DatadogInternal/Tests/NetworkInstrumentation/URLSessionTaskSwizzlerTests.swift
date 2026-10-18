/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal

class URLSessionTaskSwizzlerTests: XCTestCase {
    func testSwizzling_taskResume() throws {
        let expectation = self.expectation(description: "resume")

        // Given
        let swizzler = URLSessionTaskSwizzler()

        try swizzler.swizzle(
            interceptResume: { _, continuation in
                expectation.fulfill()
                continuation()
            }
        )

        // When
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "https://www.datadoghq.com/")!
        session
            .dataTask(with: url)
            .resume() // intercepted

        swizzler.unswizzle()

        session
            .dataTask(with: url)
            .resume() // not intercepted

        // Then
        wait(for: [expectation], timeout: 5)
    }

    func testSwizzling_taskResume_defersOnlyTargetAndForwardsEachCall() throws {
        let server = ServerMock(
            delivery: .success(response: .mockWith(statusCode: 200), data: .mock(ofSize: 10)),
            skipIsMainThreadCheck: true
        )
        let session = server.getInterceptedURLSession()
        let target = session.dataTask(with: URL.mockAny())
        let foreign = session.dataTask(with: URL.mockAny())
        let forwarded = ReadWriteLock(wrappedValue: 0)
        let previous = URLSessionTaskSwizzler()
        try previous.swizzle { task, continuation in
            if task === target || task === foreign { forwarded.mutate { $0 += 1 } }
            continuation()
        }
        defer { previous.unswizzle() }
        var continuations: [URLSessionTaskSwizzler.ResumeContinuation] = []
        let swizzler = URLSessionTaskSwizzler()
        try swizzler.swizzle { task, continuation in
            guard task === target else {
                continuation()
                return
            }
            continuations.append(continuation)
        }
        defer {
            target.cancel()
            foreign.cancel()
            session.invalidateAndCancel()
            swizzler.unswizzle()
        }
        foreign.resume()
        XCTAssertEqual(forwarded.wrappedValue, 1)
        target.resume()
        target.resume()
        XCTAssertEqual(forwarded.wrappedValue, 1)
        XCTAssertEqual(continuations.count, 2)
        continuations.forEach { $0() }
        continuations.removeAll()
        XCTAssertEqual(forwarded.wrappedValue, 3)
        XCTAssertEqual(server.waitAndReturnRequests(count: 2).count, 2)
    }
}
