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
        let session = URLSession(configuration: .ephemeral)
        let target = session.dataTask(with: URL.mockAny())
        let foreign = session.dataTask(with: URL.mockAny())
        let forwardedTaskIDs = ReadWriteLock(wrappedValue: [ObjectIdentifier]())
        let previous = URLSessionTaskSwizzler()
        try previous.swizzle { task, continuation in
            guard task === target || task === foreign else {
                continuation()
                return
            }
            // Observe forwarded calls without starting requests.
            forwardedTaskIDs.mutate { $0.append(ObjectIdentifier(task)) }
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
        XCTAssertEqual(forwardedTaskIDs.wrappedValue, [ObjectIdentifier(foreign)])
        target.resume()
        target.resume()
        XCTAssertEqual(forwardedTaskIDs.wrappedValue, [ObjectIdentifier(foreign)])
        XCTAssertEqual(continuations.count, 2)
        continuations.forEach { $0() }
        continuations.removeAll()
        XCTAssertEqual(
            forwardedTaskIDs.wrappedValue,
            [ObjectIdentifier(foreign), ObjectIdentifier(target), ObjectIdentifier(target)]
        )
    }
}
