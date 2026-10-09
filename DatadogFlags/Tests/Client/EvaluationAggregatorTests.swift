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
                XCTAssertEqual(events.count, 1)
                XCTAssertEqual(events.first?.evaluationCount, 2)
                XCTAssertEqual(events.first?.runtimeDefaultUsed, (defaultFirst && !projected) ? true : nil)
                XCTAssertEqual(events.first?.variant?.key, (defaultFirst && !projected) ? nil : "variant")
                XCTAssertEqual(events.first?.allocation?.key, (defaultFirst && !projected) ? nil : "allocation")
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
