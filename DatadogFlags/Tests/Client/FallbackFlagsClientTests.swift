/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class FallbackFlagsClientTests: XCTestCase {
    func testSetEvaluationContext() {
        // Given
        let core = SingleFeatureCoreMock<FlagsFeature>()
        Flags.enable(in: core)
        let client = FallbackFlagsClient(name: FlagsClient.defaultName, core: core)
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        // When
        let clientNotInitializedError = expectation(description: "clientNotInitializedError")
        client.setEvaluationContext(.mockAny()) { result in
            if case .failure(.clientNotInitialized) = result {
                clientNotInitializedError.fulfill()
            }
        }

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Using fallback client to set the evaluation context. Ensure that a client named 'default' is created before using it."
        )
    }

    func testGetDetails() {
        // Given
        let core = SingleFeatureCoreMock<FlagsFeature>()
        Flags.enable(in: core)
        let client = FallbackFlagsClient(name: FlagsClient.defaultName, core: core)
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        let flagDetails = client.getDetails(key: .mockAny(), defaultValue: false)

        // Then
        XCTAssertEqual(
            flagDetails,
            FlagDetails(key: .mockAny(), value: false, error: .providerNotReady)
        )
        XCTAssertEqual(dd.logger.errorMessages.count, 1)
        XCTAssertEqual(
            dd.logger.errorMessages.first,
            """
            Using fallback client to get '\(String.mockAny())' value. \
            Ensure that a client named 'default' is created before using it.
            """
        )
    }

    func testGetFlagAssignmentsSnapshot() {
        // Given
        let core = SingleFeatureCoreMock<FlagsFeature>()
        Flags.enable(in: core)
        let client = FallbackFlagsClient(name: FlagsClient.defaultName, core: core)
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        let snapshot = client.getFlagAssignmentsSnapshot()

        // Then
        XCTAssertNil(snapshot)
        XCTAssertEqual(dd.logger.errorMessages.count, 1)
        XCTAssertEqual(
            dd.logger.errorMessages.first,
            """
            Using fallback client to get all flag values. \
            Ensure that a client named 'default' is created before using it.
            """
        )
    }

    func testTrackEvaluation() {
        // Given
        let core = SingleFeatureCoreMock<FlagsFeature>()
        Flags.enable(in: core)
        let client = FallbackFlagsClient(name: FlagsClient.defaultName, core: core)
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // When
        client.trackFlagSnapshotEvaluation(key: .mockAny(), assignment: .mockAny(), context: .mockAny())

        // Then
        XCTAssertEqual(dd.logger.errorMessages.count, 1)
        XCTAssertEqual(
            dd.logger.errorMessages.first,
            """
            Using fallback client to track '\(String.mockAny())'. \
            Ensure that a client named 'default' is created before using it.
            """
        )
    }
}
