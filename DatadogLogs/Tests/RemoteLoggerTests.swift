/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogLogs

private class RemoteLoggerErrorMessageReceiver: FeatureMessageReceiver {
    struct ErrorMessage: Decodable {
        /// The Log error message
        let message: String
    }

    var errors: [String] = []

    /// Adds RUM Error with given message and stack to current RUM View.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard
            let error = try? message.baggage(forKey: "error", type: ErrorMessage.self)
        else {
            return false
        }

        self.errors.append(error.message)

        return true
    }
}

class RemoteLoggerTests: XCTestCase {
    func testItSendsErrorAlongWithErrorLog() throws {
        let errorMessageReceiver = RemoteLoggerErrorMessageReceiver()

        let core = PassthroughCoreMock(
            expectation: expectation(description: "Send error"),
            messageReceiver: errorMessageReceiver
        )

        // Given
        let logger = RemoteLogger(
            core: core,
            configuration: .init(
                service: "logger.tests",
                name: "TestLogger",
                networkInfoEnabled: false,
                threshold: LogLevel.info,
                eventMapper: nil,
                sampler: Sampler(samplingRate: 100.0)
            ),
            dateProvider: RelativeDateProvider(
                using: .mockDecember15th2019At10AMUTC()
            ),
            rumContextIntegration: false,
            activeSpanIntegration: false
        )

        // When
        logger.error("Error message")

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertEqual(errorMessageReceiver.errors.count, 1)
        XCTAssertEqual(errorMessageReceiver.errors.first, "Error message")
    }

    func testItDoesNotSendErrorAlongWithCrossPlatformCrashLog() throws {
        let errorMessageReceiver = RemoteLoggerErrorMessageReceiver()

        let core = PassthroughCoreMock(
            expectation: expectation(description: "Send error"),
            messageReceiver: errorMessageReceiver
        )

        // Given
        let logger = RemoteLogger(
            core: core,
            configuration: .init(
                service: "logger.tests",
                name: "TestLogger",
                networkInfoEnabled: false,
                threshold: LogLevel.info,
                eventMapper: nil,
                sampler: Sampler(samplingRate: 100.0)
            ),
            dateProvider: RelativeDateProvider(
                using: .mockDecember15th2019At10AMUTC()
            ),
            rumContextIntegration: false,
            activeSpanIntegration: false
        )

        // When
        logger.error("Error message", error: nil, attributes: [CrossPlatformAttributes.errorLogIsCrash: true])

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)

        XCTAssertEqual(errorMessageReceiver.errors.count, 0)
    }
}
