/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class NOPFlagsClientTests: XCTestCase {
    func testSetEvaluationContext() {
        // Given
        let client = NOPFlagsClient()
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        let clientNotInitializedError = expectation(description: "clientNotInitializedError")
        client.setEvaluationContext(.mockAny()) { result in
            if case .failure(.clientNotInitialized) = result {
                clientNotInitializedError.fulfill()
            }
        }

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertEqual(dd.logger.criticalMessages.count, 1)
        XCTAssertEqual(
            dd.logger.criticalMessages.first,
            """
            Calling `setEvaluationContext(_:completion:)` on NOPFlagsClient.
            Make sure Flags feature is enabled and that the `FlagsClient` was created successfully.
            """
        )
    }

    func testGetDetails() {
        // Given
        let client = NOPFlagsClient()
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        let flagDetails = client.getDetails(key: "booleanFlag", defaultValue: false)

        // Then
        XCTAssertEqual(
            flagDetails,
            FlagDetails(key: "booleanFlag", value: false, error: .invalidClient)
        )
        XCTAssertEqual(dd.logger.criticalMessages.count, 1)
        XCTAssertEqual(
            dd.logger.criticalMessages.first,
            """
            Calling `getDetails(key:defaultValue:)` on NOPFlagsClient.
            Make sure Flags feature is enabled and that the `FlagsClient` was created successfully.
            """
        )
    }
}
