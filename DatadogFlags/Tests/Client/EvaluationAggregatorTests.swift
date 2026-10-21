/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/)
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities

@_spi(Internal)
@testable import DatadogFlags

class EvaluationAggregatorTests: XCTestCase {
    private let featureScope = FeatureScopeMock()

    func testTelemetryUsesEffectiveReasonAndPreservesErrorClassification() throws {
        for originalReason in ["DEFAULT", "TARGETING_MATCH"] {
            for cached in [false, true] {
                for error in [nil, "TYPE_MISMATCH"] as [String?] {
                    let scope = FeatureScopeMock()
                    let aggregator = EvaluationAggregator(
                        dateProvider: DateProviderMock(),
                        featureScope: scope,
                        flushInterval: 100
                    )
                    var assignment = FlagAssignment(
                        allocationKey: "allocation",
                        variationKey: "variant",
                        variation: .boolean(true),
                        reason: originalReason,
                        doLog: false
                    )
                    if cached {
                        assignment.reason = "CACHED"
                    }
                    aggregator.recordEvaluation(
                        for: "flag",
                        assignment: assignment,
                        evaluationContext: .mockAny(),
                        flagError: error
                    )
                    aggregator.sendEvaluations()
                    let event = try XCTUnwrap(scope.eventsWritten(ofType: FlagEvaluationEvent.self).first)
                    let isDefault = (!cached && originalReason == "DEFAULT") || error != nil
                    XCTAssertEqual(event.runtimeDefaultUsed, isDefault ? true : nil)
                    XCTAssertEqual(event.variant?.key, isDefault ? nil : "variant")
                    XCTAssertEqual(event.allocation?.key, isDefault ? nil : "allocation")
                    XCTAssertEqual(event.error?.message, error)
                }
            }
        }
    }

    func testFirstRecordClassificationUsesEffectiveReasonInBothOrders() throws {
        for projected in [false, true] {
            for defaultFirst in [false, true] {
                let scope = FeatureScopeMock()
                let aggregator = EvaluationAggregator(
                    dateProvider: DateProviderMock(),
                    featureScope: scope,
                    flushInterval: 100
                )
                var defaultAssignment = FlagAssignment(
                    allocationKey: "allocation",
                    variationKey: "variant",
                    variation: .boolean(true),
                    reason: "DEFAULT",
                    doLog: true
                )
                var networkAssignment = defaultAssignment
                networkAssignment.reason = "TARGETING_MATCH"
                if projected {
                    defaultAssignment.reason = "CACHED"
                }
                let assignments = defaultFirst
                    ? [defaultAssignment, networkAssignment]
                    : [networkAssignment, defaultAssignment]
                for assignment in assignments {
                    aggregator.recordEvaluation(
                        for: "flag",
                        assignment: assignment,
                        evaluationContext: .mockAny(),
                        flagError: nil
                    )
                }
                aggregator.sendEvaluations()
                let events = scope.eventsWritten(ofType: FlagEvaluationEvent.self)
                XCTAssertEqual(events.count, projected ? 1 : 2)
                XCTAssertEqual(events.reduce(0) { $0 + $1.evaluationCount }, 2)
                XCTAssertEqual(events.filter { $0.runtimeDefaultUsed == true }.count, projected ? 0 : 1)
                XCTAssertEqual(events.filter { $0.variant?.key == "variant" }.count, 1)
            }
        }
    }

    // MARK: - Implementation Details

    func testGivenPendingAggregations_whenSendEvaluations_itClearsPending() {
        // Given
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 100.0,
            maxAggregations: 1_000
        )

        // When
        aggregator.recordEvaluation(
            for: "flag-1",
            assignment: .mockAnyBoolean(),
            evaluationContext: .mockAny(),
            flagError: nil
        )
        aggregator.recordEvaluation(
            for: "flag-2",
            assignment: .mockAnyBoolean(),
            evaluationContext: .mockAny(),
            flagError: nil
        )

        // Then
        aggregator.sendEvaluations()
        XCTAssertEqual(featureScope.eventsWritten.count, 2)

        aggregator.recordEvaluation(
            for: "flag-3",
            assignment: .mockAnyBoolean(),
            evaluationContext: .mockAny(),
            flagError: nil
        )

        aggregator.sendEvaluations()
        XCTAssertEqual(featureScope.eventsWritten.count, 3, "Should have 2 from first flush + 1 from second flush")
    }

    // MARK: - Thread Safety

    func testGivenConcurrentAccess_whenRecordAndSend_itHandlesSafely() {
        // Given
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 100.0,
            maxAggregations: 1_000
        )

        let iterations = 50
        let expectation = self.expectation(description: "All operations complete")
        expectation.expectedFulfillmentCount = iterations * 2

        // When
        DispatchQueue.global().async {
            for index in 0..<iterations {
                aggregator.recordEvaluation(
                    for: "flag-\(index)",
                    assignment: .mockAnyBoolean(),
                    evaluationContext: .mockAny(),
                    flagError: nil
                )
                expectation.fulfill()
            }
        }

        DispatchQueue.global().async {
            for _ in 0..<iterations {
                aggregator.sendEvaluations()
                expectation.fulfill()
            }
        }

        // Then
        wait(for: [expectation], timeout: 5.0)
        aggregator.sendEvaluations()

        XCTAssertEqual(featureScope.eventsWritten.count, 50, "Should have written exactly one event per unique flag")
    }
}

extension EvaluationAggregatorTests {
    func testPrivacyHashAndUnicodeVectors() throws {
        let vectors = [
            ("jane.doe@datadoghq.com", "sha256_b4698f9b6d186781fa8dc59e533578fa2d8379a46b1cf6db85cda6aa9c99e51b"),
            ("", ""),
            ("é", "sha256_4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c"),
            ("e\u{301}", "sha256_bf12767b0f2a56b2190075bae8169f656e3ce8d6357d4aff184bc6c7ea48f9f6")
        ]
        for (targetingKey, expected) in vectors {
            let scope = FeatureScopeMock()
            let aggregator = EvaluationAggregator(dateProvider: DateProviderMock(), featureScope: scope, flushInterval: 100)
            aggregator.recordEvaluation(
                for: "flag", assignment: .mockAnyBoolean(doLog: false),
                evaluationContext: .init(targetingKey: targetingKey, attributes: ["private": .string("CONTEXT_CANARY")]),
                flagError: nil
            )
            aggregator.sendEvaluations()
            let event = try XCTUnwrap(scope.eventsWritten(ofType: FlagEvaluationEvent.self).first)
            XCTAssertEqual(event.targetingKey, expected)
            XCTAssertNil(event.context)
            XCTAssertNil(event.error)
            let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
            XCTAssertFalse(json.contains("CONTEXT_CANARY"))
        }
    }

    func testConsentAndSanitizedErrorsDefineBucketsBeforeFlush() throws {
        let scope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(dateProvider: DateProviderMock(), featureScope: scope, flushInterval: 100)
        var assignment = FlagAssignment.mockAnyBoolean(doLog: false)
        for consent in [false, true] {
            assignment.observeFullEvaluationData = consent
            for canary in ["ONE", "TWO"] {
                aggregator.recordEvaluation(
                    for: "flag", assignment: assignment,
                    evaluationContext: .init(targetingKey: "", attributes: ["private": .string(canary)]),
                    flagError: "ERROR_CANARY_" + canary
                )
            }
        }
        assignment.observeFullEvaluationData = false
        aggregator.sendEvaluations()
        aggregator.sendEvaluations()
        let events = scope.eventsWritten(ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.reduce(0) { $0 + $1.evaluationCount }, 4)
        XCTAssertEqual(events.first { $0.context == nil }?.evaluationCount, 2)
        XCTAssertTrue(events.allSatisfy { $0.error?.message == "GENERAL" && $0.runtimeDefaultUsed == true })
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(events), as: UTF8.self).contains("ERROR_CANARY"))
    }

    func testAllStableErrorsAndAbsentErrorsInBothModes() throws {
        let codes = ["PROVIDER_NOT_READY", "PROVIDER_FATAL", "FLAG_NOT_FOUND", "PARSE_ERROR",
                     "TYPE_MISMATCH", "TARGETING_KEY_MISSING", "INVALID_CONTEXT", "GENERAL"]
        for consent in [false, true] {
            let scope = FeatureScopeMock()
            let aggregator = EvaluationAggregator(dateProvider: DateProviderMock(), featureScope: scope, flushInterval: 100)
            var assignment = FlagAssignment.mockAnyBoolean()
            assignment.observeFullEvaluationData = consent
            for code in codes.map(Optional.some) + [nil] {
                aggregator.recordEvaluation(for: "flag", assignment: assignment, evaluationContext: .mockAny(), flagError: code)
            }
            aggregator.sendEvaluations()
            let events = scope.eventsWritten(ofType: FlagEvaluationEvent.self)
            XCTAssertEqual(events.count, 9)
            XCTAssertEqual(Set(events.compactMap { $0.error?.message }), Set(codes))
            XCTAssertEqual(events.filter { $0.error == nil }.count, 1)
        }
    }

    func testMissingTargetingAndOwnedFullDataContext() throws {
        let scope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(dateProvider: DateProviderMock(), featureScope: scope, flushInterval: 100)
        aggregator.recordEvaluation(for: "missing", assignment: .mockAnyBoolean(), evaluationContext: .empty, flagError: "PROVIDER_NOT_READY")
        var attributes: [String: AnyValue] = ["nested": .dictionary(["value": .string("original")])]
        var assignment = FlagAssignment.mockAnyBoolean()
        assignment.observeFullEvaluationData = true
        let context = FlagsEvaluationContext(targetingKey: "raw", attributes: attributes)
        aggregator.recordEvaluation(for: "full", assignment: assignment, evaluationContext: context, flagError: nil)
        attributes["nested"] = .dictionary(["value": .string("mutated")])
        aggregator.sendEvaluations()
        let events = scope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let missing = try XCTUnwrap(events.first { $0.flag.key == "missing" })
        XCTAssertNil(missing.targetingKey)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(missing), as: UTF8.self).contains("targeting_key"))
        XCTAssertEqual(events.first { $0.flag.key == "full" }?.context?.evaluation, context.attributes)
    }
}
