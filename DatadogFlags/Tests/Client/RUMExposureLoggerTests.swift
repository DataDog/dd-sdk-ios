/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class RUMExposureLoggerTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    func testLogExposure() throws {
        // Given
        let dateProvider = DateProviderMock(now: .mockDecember15th2019At10AMUTC())
        let logger = RUMExposureLogger(
            dateProvider: dateProvider,
            featureScope: featureScope
        )

        let serverTimeOffset: TimeInterval = 5
        featureScope.contextMock.serverTimeOffset = serverTimeOffset

        let assignment = FlagAssignment(
            allocationKey: "allocation-123",
            variationKey: "variation-456",
            variation: .boolean(true),
            reason: "DEFAULT",
            doLog: true
        )

        let evaluationContext = FlagsEvaluationContext(
            targetingKey: "user-123",
            attributes: ["email": "test@example.com", "plan": "premium"]
        )

        // When
        logger.logExposure(
            flagKey: "feature-flag",
            value: true,
            assignment: assignment,
            evaluationContext: evaluationContext
        )

        // Then
        let messages = featureScope.messagesSent()
        XCTAssertEqual(messages.count, 2, "Should send both flag evaluation and exposure messages")

        let flagEvaluation = try XCTUnwrap(messages.firstPayload as? RUMFlagEvaluationMessage)
        XCTAssertEqual(flagEvaluation.flagKey, "feature-flag")
        XCTAssertEqual(flagEvaluation.value as? Bool, true)

        let flagExposure = try XCTUnwrap(messages.lastPayload as? RUMFlagExposureMessage)
        XCTAssertEqual(flagExposure.flagKey, "feature-flag")
        XCTAssertEqual(flagExposure.allocationKey, "allocation-123")
        XCTAssertEqual(flagExposure.exposureKey, "feature-flag-allocation-123")
        XCTAssertEqual(flagExposure.subjectKey, "user-123")
        XCTAssertEqual(flagExposure.variantKey, "variation-456")

        let expectedTimestamp = dateProvider.now
            .addingTimeInterval(serverTimeOffset)
            .timeIntervalSince1970
        XCTAssertEqual(flagExposure.timestamp, expectedTimestamp, accuracy: 0.001)

        let subjectAttributes = flagExposure.subjectAttributes
        XCTAssertEqual(subjectAttributes["email"] as? String, "test@example.com")
        XCTAssertEqual(subjectAttributes["plan"] as? String, "premium")
    }
}
