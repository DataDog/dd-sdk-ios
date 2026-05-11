/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

private final class RUMFlagEvaluationRecorder: BusMessageReceiver {
    private(set) var messages: [RUMFlagEvaluationMessage] = []
    func receive(message: RUMFlagEvaluationMessage, from core: DatadogCoreProtocol) {
        messages.append(message)
    }
}

final class RUMFlagEvaluationReporterTests: XCTestCase {
    func testSendFlagEvaluation() throws {
        // Given
        let core = PassthroughCoreMock()
        let recorder = RUMFlagEvaluationRecorder()
        core.subscribe(receiver: recorder)
        let reporter = RUMFlagEvaluationReporter(messageBus: core.messageBus)

        // When
        reporter.sendFlagEvaluation(
            flagKey: "feature-flag",
            value: true
        )

        // Then
        XCTAssertEqual(recorder.messages.count, 1, "Should send flag evaluation message")

        let flagEvaluation = try XCTUnwrap(recorder.messages.first)
        XCTAssertEqual(flagEvaluation.flagKey, "feature-flag")
        XCTAssertEqual(flagEvaluation.value as? Bool, true)
    }
}
