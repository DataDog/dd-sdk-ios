/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogCore

class ApplicationVersionPublisherTests: XCTestCase {
    func testInitialValue() throws {
        let publisher = ApplicationVersionPublisher(version: "0")
        XCTAssertEqual(publisher.initialValue, "0")
    }

    func testPublishApplicationVersion() throws {
        let expectation = expectation(description: "application version publisher publishes data")

        // Given
        let publisher = ApplicationVersionPublisher(version: "0")
        let version: String = .mockRandom()

        // When
        publisher.publish {
            // Then
            XCTAssertEqual($0, version)
            expectation.fulfill()
        }

        publisher.version = version

        // ApplicationVersionPublisher publishes in sync
        waitForExpectations(timeout: 0)
    }
}
