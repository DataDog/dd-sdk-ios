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

    func testCachedReasonsPreserveDefaultAndErrorTelemetry() throws {
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
                        assignment.reasonBeforeCacheProjection = originalReason
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
                    let isDefault = originalReason == "DEFAULT" || error != nil
                    XCTAssertEqual(event.runtimeDefaultUsed, isDefault ? true : nil)
                    XCTAssertEqual(event.variant?.key, isDefault ? nil : "variant")
                    XCTAssertEqual(event.allocation?.key, isDefault ? nil : "allocation")
                    XCTAssertEqual(event.error?.message, error)
                }
            }
        }
    }

    func testCachedThenNetworkKeepsFirstRecordAggregationClassification() throws {
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(),
            featureScope: featureScope,
            flushInterval: 100
        )
        var assignment = FlagAssignment(
            allocationKey: "allocation",
            variationKey: "variant",
            variation: .boolean(true),
            reason: "CACHED",
            doLog: true
        )
        assignment.reasonBeforeCacheProjection = "DEFAULT"
        aggregator.recordEvaluation(for: "flag", assignment: assignment, evaluationContext: .mockAny(), flagError: nil)
        assignment.reasonBeforeCacheProjection = nil
        assignment.reason = "TARGETING_MATCH"
        aggregator.recordEvaluation(for: "flag", assignment: assignment, evaluationContext: .mockAny(), flagError: nil)
        aggregator.sendEvaluations()
        let events = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.evaluationCount, 2)
        XCTAssertEqual(events.first?.runtimeDefaultUsed, true)
        XCTAssertNil(events.first?.variant)
        XCTAssertNil(events.first?.allocation)
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
