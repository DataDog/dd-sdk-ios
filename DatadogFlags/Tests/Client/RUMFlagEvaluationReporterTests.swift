/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class RUMFlagEvaluationReporterTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    func testSendFlagEvaluation() throws {
        // Given
        let reporter = RUMFlagEvaluationReporter(featureScope: featureScope)

        // When
        reporter.sendFlagEvaluation(
            flagKey: "feature-flag",
            value: true
        )

        // Then
        let messages = featureScope.messagesSent()
        XCTAssertEqual(messages.count, 1, "Should send flag evaluation message")

        let flagEvaluation = try XCTUnwrap(messages.firstPayload as? RUMFlagEvaluationMessage)
        XCTAssertEqual(flagEvaluation.flagKey, "feature-flag")
        XCTAssertEqual(flagEvaluation.value as? Bool, true)
    }
}
