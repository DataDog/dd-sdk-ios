/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
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
    func testReporterCapturesOriginAndPreservesValueAcrossHandoffExit() throws {
        let reporter = RUMFlagEvaluationReporter(featureScope: featureScope)
        let origin: RUMCoreContext = .mockWith(viewID: UUID().uuidString)
        RUMContextHandoff.withValue(owner: featureScope.rumContextHandoffOwner, rumContext: origin, sceneIdentifier: "scene-A") {
            reporter.sendFlagEvaluation(flagKey: "captured", value: 7)
        }
        let messages = featureScope.messagesSent()
        XCTAssertEqual(messages.count, 1)
        let captured = try XCTUnwrap(messages.firstPayload as? RUMFlagEvaluationContextMessage)
        XCTAssertEqual(captured.evaluation.flagKey, "captured")
        XCTAssertEqual(captured.evaluation.value as? Int, 7)
        XCTAssertEqual(captured.context(for: featureScope.rumContextHandoffOwner)?.rumContext?.viewID, origin.viewID)
        XCTAssertEqual(captured.context(for: featureScope.rumContextHandoffOwner)?.sceneIdentifier, "scene-A")
        XCTAssertNil(captured.context(for: FeatureScopeMock().rumContextHandoffOwner))
        featureScope.rumContextHandoffOwner?.invalidate()
        XCTAssertNil(captured.context(for: featureScope.rumContextHandoffOwner))
    }

    func testReporterPreservesCapturedNilViewAndIgnoresForeignHandoff() throws {
        let reporter = RUMFlagEvaluationReporter(featureScope: featureScope)
        RUMContextHandoff.withValue(owner: featureScope.rumContextHandoffOwner, rumContext: nil, sceneIdentifier: "scene-A") {
            reporter.sendFlagEvaluation(flagKey: "nil-view", value: false)
        }
        let captured = try XCTUnwrap(featureScope.messagesSent().firstPayload as? RUMFlagEvaluationContextMessage)
        let context = try XCTUnwrap(captured.context(for: featureScope.rumContextHandoffOwner))
        XCTAssertNil(context.rumContext)
        XCTAssertEqual(context.sceneIdentifier, "scene-A")
        let foreign = FeatureScopeMock()
        RUMContextHandoff.withValue(owner: foreign.rumContextHandoffOwner, rumContext: .mockAny(), sceneIdentifier: "foreign") {
            reporter.sendFlagEvaluation(flagKey: "legacy", value: "value")
        }
        guard case let .payload(evaluation as RUMFlagEvaluationMessage) = featureScope.messagesSent().last else {
            return XCTFail("Foreign handoff must leave an ordinary legacy payload")
        }
        XCTAssertEqual(evaluation.flagKey, "legacy")
        XCTAssertEqual(evaluation.value as? String, "value")
    }

    func testNOPScopeAndReporterDoNotCaptureOrEmitNewContext() {
        let scope = NOPDatadogCore().scope(for: FlagsFeature.self)
        let evaluation = RUMFlagEvaluationMessage(flagKey: "nop", value: true)
        XCTAssertNil(RUMFlagEvaluationContextMessage(evaluation: evaluation, in: scope))
        let reporter = NOPRUMFlagEvaluationReporter()
        reporter.sendFlagEvaluation(flagKey: "nop", value: true)
        XCTAssertTrue(featureScope.messagesSent().isEmpty)
    }
}
