/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogInternal

class URLSessionTaskSwizzlerTests: XCTestCase {
    func testSwizzling_taskResume() throws {
        let expectation = self.expectation(description: "resume")

        // Given
        let swizzler = URLSessionTaskSwizzler()

        try swizzler.swizzle(
            interceptResume: { _ in
                expectation.fulfill()
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

    func testSwizzling_nwTaskResume() throws {
        guard #available(iOS 18.4, tvOS 18.4, macOS 15.4, watchOS 11.4, visionOS 2.4, *) else {
            throw XCTSkip("usesClassicLoadingMode requires iOS 18.4+")
        }
        guard URLSessionTaskSwizzler.NWTaskResume.build() != nil else {
            throw XCTSkip("NW task tracking not supported on this platform/version")
        }
        let intercepted = expectation(description: "NWURLSessionTask.resume intercepted")

        // Given
        let swizzler = URLSessionTaskSwizzler()
        try swizzler.swizzle(interceptResume: { _ in intercepted.fulfill() })

        // When - usesClassicLoadingMode = false forces NWURLSessionTask instances
        let configuration = URLSessionConfiguration.ephemeral
        configuration.usesClassicLoadingMode = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://localhost:1")!)
        let taskClassName = String(describing: type(of: task))
        XCTAssert(taskClassName.hasPrefix("NWURLSession"), "Expected NWURLSessionTask, got \(taskClassName)")
        task.resume()

        // Then
        wait(for: [intercepted], timeout: 5)
        swizzler.unswizzle()
    }
}
