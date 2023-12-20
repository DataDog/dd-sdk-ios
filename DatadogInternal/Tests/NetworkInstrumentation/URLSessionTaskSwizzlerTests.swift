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
}
