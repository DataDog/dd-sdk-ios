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

/// Validates compliance with the evaluation logging (EVALLOG) specifications,
/// which define how flag evaluations are tracked, aggregated, and sent to the backend.
class EvaluationLoggingTests: XCTestCase {
    // MARK: - Helper to skip tests

    private func skipTest() throws {
        throw XCTSkip("EVALLOG tests not yet implemented")
    }

    // MARK: - EVALLOG.1: EVP Intake

    // EVALLOG.1: SDK must send evaluation events to EVP intake with application/json and batched schema
    func testSendsToEVPIntakeWithBatchedJsonFormat() throws {
        // Given
        let mockEvent = FlagEvaluationEvent(
            timestamp: 1_234_567_890,
            flag: .init(key: "test-flag"),
            firstEvaluation: 1_234_567_890,
            lastEvaluation: 1_234_567_900,
            evaluationCount: 5,
            variant: .init(key: "variant-a"),
            allocation: .init(key: "allocation-1"),
            targetingRule: nil,
            targetingKey: "user-123",
            runtimeDefaultUsed: nil,
            error: nil,
            context: nil
        )

        let eventData = try JSONEncoder().encode(mockEvent)
        let events = [Event(data: eventData)]

        let builder = EvaluationRequestBuilder(
            customIntakeURL: nil,
            telemetry: NOPTelemetry()
        )

        // When
        func url(for site: DatadogSite) -> String {
            // swiftlint:disable:next force_try
            let request = try! builder.request(for: events, with: .mockWith(site: site), execution: .mockAny())
            return request.url!.absoluteStringWithoutQuery!
        }

        // Then - Verify EVP intake endpoint
        XCTAssertEqual(url(for: .us1), "https://browser-intake-datadoghq.com/api/v2/flagevaluation")
        XCTAssertEqual(url(for: .us3), "https://browser-intake-us3-datadoghq.com/api/v2/flagevaluation")
        XCTAssertEqual(url(for: .us5), "https://browser-intake-us5-datadoghq.com/api/v2/flagevaluation")
        XCTAssertEqual(url(for: .eu1), "https://browser-intake-datadoghq.eu/api/v2/flagevaluation")
        XCTAssertEqual(url(for: .ap1), "https://browser-intake-ap1-datadoghq.com/api/v2/flagevaluation")
        XCTAssertEqual(url(for: .ap2), "https://browser-intake-ap2-datadoghq.com/api/v2/flagevaluation")
        XCTAssertEqual(url(for: .us1_fed), "https://browser-intake-ddog-gov.com/api/v2/flagevaluation")

        // Then - Verify Content-Type and batched schema
        let request = try builder.request(for: events, with: .mockAny(), execution: .mockAny())
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")

        let httpBodyData = try XCTUnwrap(request.httpBody)
        let decodedBatch = try JSONDecoder().decode(BatchedFlagEvaluations.self, from: httpBodyData)

        XCTAssertNotNil(decodedBatch.context)
        XCTAssertEqual(decodedBatch.flagEvaluations.count, 1)
        XCTAssertEqual(decodedBatch.flagEvaluations.first?.flag.key, "test-flag")
    }

    // MARK: - EVALLOG.2: Log All Evaluations

    // EVALLOG.2: Log all evaluations when enabled, including defaults and errors (unlike exposure logging)
    func testLogsAllEvaluationsRegardlessOfDoLog() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )

        // When - Record evaluations with doLog = true and doLog = false
        aggregator.recordEvaluation(
            for: "flag-with-dolog-true",
            assignment: .mockAnyBoolean(doLog: true),
            evaluationContext: .mockAny(),
            flagError: nil
        )

        aggregator.recordEvaluation(
            for: "flag-with-dolog-false",
            assignment: .mockAnyBoolean(doLog: false),
            evaluationContext: .mockAny(),
            flagError: nil
        )

        let flushExpectation = expectation(description: "Flush completes")
        aggregator.flush {
            flushExpectation.fulfill()
        }

        wait(for: [flushExpectation], timeout: 0.1)

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 2, "Should log all evaluations regardless of doLog")
    }

    // MARK: - EVALLOG.3: Aggregation

    // EVALLOG.3: Aggregate evaluations by flag_key, variant_key, allocation_key, targeting_key, error_message, context
    func testAggregatesByCompositeKey() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )

        // When - Record evaluations varying each part of composite key
        let baseAssignment = FlagAssignment(
            allocationKey: "alloc-1", variationKey: "var-1", variation: .boolean(true), reason: "MATCH", doLog: true
        )
        let baseContext = FlagsEvaluationContext(targetingKey: "user-1", attributes: [:])

        aggregator.recordEvaluation(
            for: "flag-1", assignment: baseAssignment, evaluationContext: baseContext, flagError: nil
        )
        aggregator.recordEvaluation(
            for: "flag-2", assignment: baseAssignment, evaluationContext: baseContext, flagError: nil
        )
        aggregator.recordEvaluation(
            for: "flag-1",
            assignment: FlagAssignment(
                allocationKey: "alloc-2", variationKey: "var-1", variation: .boolean(true), reason: "MATCH", doLog: true
            ),
            evaluationContext: baseContext,
            flagError: nil
        )
        aggregator.recordEvaluation(
            for: "flag-1",
            assignment: baseAssignment,
            evaluationContext: FlagsEvaluationContext(targetingKey: "user-2", attributes: [:]),
            flagError: nil
        )
        aggregator.recordEvaluation(
            for: "flag-1", assignment: baseAssignment, evaluationContext: baseContext, flagError: "error"
        )
        aggregator.recordEvaluation(
            for: "flag-1",
            assignment: baseAssignment,
            evaluationContext: FlagsEvaluationContext(targetingKey: "user-1", attributes: ["attr": .string("value")]),
            flagError: nil
        )

        let flushExpectation = expectation(description: "Flush completes")
        aggregator.flush {
            flushExpectation.fulfill()
        }
        wait(for: [flushExpectation], timeout: 0.1)

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 6)
    }

    // EVALLOG.3: Tracks evaluation count, first/last timestamps, runtime_default_used, error_message
    func testTracksAggregationFields() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let dateProvider = RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC())
        let aggregator = EvaluationAggregator(
            dateProvider: dateProvider,
            featureScope: featureScope,
            flushInterval: 60.0
        )

        let assignment = FlagAssignment(
            allocationKey: "allocation-1",
            variationKey: "variant-a",
            variation: .boolean(true),
            reason: "MATCH",
            doLog: true
        )
        let context = FlagsEvaluationContext(targetingKey: "user-123", attributes: [:])

        // When - Record with time gaps between each
        let firstExpectation = expectation(description: "First record completes")
        aggregator.recordEvaluation(
            for: "test-flag", assignment: assignment, evaluationContext: context, flagError: nil
        )
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            firstExpectation.fulfill()
        }
        wait(for: [firstExpectation], timeout: 0.1)

        dateProvider.advance(bySeconds: 1)
        aggregator.recordEvaluation(
            for: "test-flag", assignment: assignment, evaluationContext: context, flagError: nil
        )
        Thread.sleep(forTimeInterval: 0.05)

        dateProvider.advance(bySeconds: 2)
        aggregator.recordEvaluation(
            for: "test-flag", assignment: assignment, evaluationContext: context, flagError: nil
        )

        let flushExpectation = expectation(description: "Flush completes")
        aggregator.flush {
            flushExpectation.fulfill()
        }
        wait(for: [flushExpectation], timeout: 0.1)

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "Should aggregate into single event")

        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let decoded = try XCTUnwrap(events.first)

        XCTAssertEqual(decoded.evaluationCount, 3, "Should track evaluation count")
        XCTAssertEqual(decoded.timestamp, decoded.firstEvaluation, "timestamp should equal firstEvaluation")
        XCTAssertLessThan(
            decoded.firstEvaluation,
            decoded.lastEvaluation,
            "lastEvaluation should be after firstEvaluation"
        )
        XCTAssertNil(decoded.runtimeDefaultUsed, "runtimeDefaultUsed should be omitted for MATCH reason")
        XCTAssertNil(decoded.error, "Should not have error")
    }

    // MARK: - EVALLOG.4: Event Buffering / Flushing

    // EVALLOG.4: Time-based flush with configurable interval (default 10s, min 1s, max 1min)
    func testFlushesAtConfigurableIntervalWithBoundsValidation() throws {
        // NOTE: Requires configuration-level bounds validation and public API
        // Current implementation: EvaluationAggregator has flushInterval parameter (default 10s)
        // Time-based flushing behavior tested in EvaluationAggregatorTests
        try skipTest()
    }

    // EVALLOG.4: Size-based flush when aggregation map reaches limit
    func testFlushesWhenAggregationMapReachesLimit() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0,
            maxAggregations: 3
        )

        // When - Record evaluations up to the limit
        aggregator.recordEvaluation(
            for: "flag-1", assignment: .mockAnyBoolean(), evaluationContext: .mockAny(), flagError: nil
        )
        aggregator.recordEvaluation(
            for: "flag-2", assignment: .mockAnyBoolean(), evaluationContext: .mockAny(), flagError: nil
        )

        // Should not have flushed yet
        XCTAssertEqual(featureScope.eventsWritten.count, 0)

        // When - Record one more to reach the limit
        aggregator.recordEvaluation(
            for: "flag-3", assignment: .mockAnyBoolean(), evaluationContext: .mockAny(), flagError: nil
        )

        // Then
        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertEqual(featureScope.eventsWritten.count, 3, "Should auto-flush when maxAggregations reached")
    }

    // EVALLOG.4: Shutdown flush when SDK stops
    func testFlushesOnShutdown() throws {
        // Given
        let featureScope = FeatureScopeMock()
        var aggregator: EvaluationAggregator? = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )

        // When - Record evaluation (won't auto-flush with these parameters)
        aggregator?.recordEvaluation(
            for: "test-flag",
            assignment: .mockAnyBoolean(),
            evaluationContext: .mockAny(),
            flagError: nil
        )

        // Deallocate aggregator (deinit calls flush)
        aggregator = nil

        // Then
        Thread.sleep(forTimeInterval: 0.1)

        XCTAssertEqual(featureScope.eventsWritten.count, 1, "Deinit should flush pending evaluations")

        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let decoded = try XCTUnwrap(events.first)
        XCTAssertEqual(decoded.flag.key, "test-flag")
    }

    // MARK: - EVALLOG.5: Error Logging

    // EVALLOG.5: Errors logged as error.message and included in aggregation key
    func testLogsErrorMessageInAggregationKey() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )

        // When - Record same flag with different errors
        aggregator.recordEvaluation(
            for: "test-flag", assignment: .mockAnyBoolean(), evaluationContext: .mockAny(), flagError: "error-1"
        )
        aggregator.recordEvaluation(
            for: "test-flag", assignment: .mockAnyBoolean(), evaluationContext: .mockAny(), flagError: "error-2"
        )
        aggregator.recordEvaluation(
            for: "test-flag", assignment: .mockAnyBoolean(), evaluationContext: .mockAny(), flagError: "error-1"
        )

        let flushExpectation = expectation(description: "Flush completes")
        aggregator.flush {
            flushExpectation.fulfill()
        }
        wait(for: [flushExpectation], timeout: 0.1)

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 2, "Different error messages should create separate aggregations")

        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let error1Event = try XCTUnwrap(events.first { $0.error?.message == "error-1" })
        let error2Event = try XCTUnwrap(events.first { $0.error?.message == "error-2" })

        XCTAssertEqual(error1Event.evaluationCount, 2, "error-1 should be aggregated twice")
        XCTAssertEqual(error2Event.evaluationCount, 1, "error-2 should be aggregated once")
    }

    // MARK: - EVALLOG.6: Omit Empty Context

    // EVALLOG.6: Omit context.evaluation if targeting context contains only targetingKey
    func testOmitsContextWhenOnlyTargetingKey() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )
        let contextWithoutAttributes = FlagsEvaluationContext(targetingKey: "user-123", attributes: [:])

        // When
        aggregator.recordEvaluation(
            for: "test-flag",
            assignment: .mockAnyBoolean(),
            evaluationContext: contextWithoutAttributes,
            flagError: nil
        )

        let flushExpectation = expectation(description: "Flush completes")
        aggregator.flush {
            flushExpectation.fulfill()
        }
        wait(for: [flushExpectation], timeout: 0.1)

        // Then
        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let event = try XCTUnwrap(events.first)

        XCTAssertNil(event.context, "Context should be omitted when no attributes present")
    }

    // EVALLOG.6: Include context.evaluation when targeting context has additional attributes
    func testIncludesContextWhenAdditionalAttributes() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )
        let contextWithAttributes = FlagsEvaluationContext(
            targetingKey: "user-123",
            attributes: [
                "email": .string("user@example.com"),
                "plan": .string("premium"),
                "age": .int(25)
            ]
        )

        // When
        aggregator.recordEvaluation(
            for: "test-flag",
            assignment: .mockAnyBoolean(),
            evaluationContext: contextWithAttributes,
            flagError: nil
        )

        let flushExpectation = expectation(description: "Flush completes")
        aggregator.flush {
            flushExpectation.fulfill()
        }
        wait(for: [flushExpectation], timeout: 0.1)

        // Then
        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let event = try XCTUnwrap(events.first)

        XCTAssertNotNil(event.context, "Context should be included when attributes present")
        XCTAssertNotNil(event.context?.evaluation, "Context evaluation should be included")
        XCTAssertEqual(event.context?.evaluation?["email"], .string("user@example.com"))
        XCTAssertEqual(event.context?.evaluation?["plan"], .string("premium"))
        XCTAssertEqual(event.context?.evaluation?["age"], .int(25))
    }

    // MARK: - EVALLOG.7: Targeting Key Presence

    // EVALLOG.7: Empty string "" is valid targeting key and must be included as targeting_key: ""
    // Note: Swift's String type is non-optional, so null/undefined targeting key doesn't apply.
    func testKeepsEmptyStringTargetingKey() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )
        let emptyContext = FlagsEvaluationContext(targetingKey: "", attributes: [:])

        // When
        aggregator.recordEvaluation(
            for: "test-flag",
            assignment: .mockAnyBoolean(),
            evaluationContext: emptyContext,
            flagError: nil
        )

        let flushExpectation = expectation(description: "Flush completes")
        aggregator.flush {
            flushExpectation.fulfill()
        }
        wait(for: [flushExpectation], timeout: 0.1)

        // Then
        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let decoded = try XCTUnwrap(events.first)

        XCTAssertEqual(decoded.targetingKey, "", "Empty string targeting key should be preserved as empty string")
    }

    // MARK: - EVALLOG.8: Omit Undefined Optional Keys

    // EVALLOG.8: Omit variant.key, allocation.key when undefined (DEFAULT/ERROR reasons)
    func testOmitsVariantAndAllocationForRuntimeDefaults() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )

        // When - Record evaluations with DEFAULT reason
        aggregator.recordEvaluation(
            for: "default-flag",
            assignment: FlagAssignment(
                allocationKey: "alloc-1",
                variationKey: "var-1",
                variation: .boolean(false),
                reason: "DEFAULT",
                doLog: true
            ),
            evaluationContext: .mockAny(),
            flagError: nil
        )

        // When - Record evaluation with ERROR
        aggregator.recordEvaluation(
            for: "error-flag",
            assignment: FlagAssignment(
                allocationKey: "alloc-2",
                variationKey: "var-2",
                variation: .boolean(false),
                reason: "ERROR",
                doLog: true
            ),
            evaluationContext: .mockAny(),
            flagError: "Some error occurred"
        )

        let flushExpectation = expectation(description: "Flush completes")
        aggregator.flush {
            flushExpectation.fulfill()
        }
        wait(for: [flushExpectation], timeout: 0.1)

        // Then
        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(events.count, 2)

        let defaultEvent = try XCTUnwrap(events.first { $0.flag.key == "default-flag" })
        XCTAssertNil(defaultEvent.variant, "Should omit variant for DEFAULT reason")
        XCTAssertNil(defaultEvent.allocation, "Should omit allocation for DEFAULT reason")
        XCTAssertEqual(defaultEvent.runtimeDefaultUsed, true)

        let errorEvent = try XCTUnwrap(events.first { $0.flag.key == "error-flag" })
        XCTAssertNil(errorEvent.variant, "Should omit variant for ERROR with error message")
        XCTAssertNil(errorEvent.allocation, "Should omit allocation for ERROR with error message")
        XCTAssertEqual(errorEvent.runtimeDefaultUsed, true)
    }

    // EVALLOG.8: Include variant.key, allocation.key when defined (normal evaluations)
    func testIncludesVariantAndAllocationForNormalEvaluations() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )

        // When
        aggregator.recordEvaluation(
            for: "test-flag",
            assignment: FlagAssignment(
                allocationKey: "alloc-1",
                variationKey: "var-1",
                variation: .boolean(true),
                reason: "MATCH",
                doLog: true
            ),
            evaluationContext: .mockAny(),
            flagError: nil
        )

        let flushExpectation = expectation(description: "Flush completes")
        aggregator.flush {
            flushExpectation.fulfill()
        }
        wait(for: [flushExpectation], timeout: 0.1)

        // Then
        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let event = try XCTUnwrap(events.first)

        XCTAssertEqual(event.variant?.key, "var-1", "Should include variant key for normal evaluations")
        XCTAssertEqual(event.allocation?.key, "alloc-1", "Should include allocation key for normal evaluations")
    }

    // MARK: - EVALLOG.9: Context Changes

    // EVALLOG.9: Different targeting contexts create separate events regardless of matching results
    func testDifferentContextsCreateSeparateAggregations() throws {
        // Already tested in testAggregatesByCompositeKey - context is part of aggregation key
        // Different contexts create separate aggregations even with same flag and variant
        try skipTest()
    }

    // MARK: - EVALLOG.10: Timestamp Field

    // EVALLOG.10: timestamp field equals first_evaluation
    func testTimestampEqualsFirstEvaluation() throws {
        // Already tested in testTracksAggregationFields
        // Verified: decoded.timestamp == decoded.firstEvaluation
        try skipTest()
    }

    // MARK: - EVALLOG.11: Aggregation Period Lifecycle

    // EVALLOG.11: Aggregation period starts at first evaluation and ends at flush
    func testAggregationPeriodLifecycle() throws {
        // Already tested in EvaluationAggregatorTests.testFlushClearsPendingAggregations
        try skipTest()
    }

    // EVALLOG.11: After flushing, subsequent evaluations start new aggregation periods
    func testNewAggregationPeriodAfterFlush() throws {
        // Already tested in EvaluationAggregatorTests.testFlushClearsPendingAggregations
        try skipTest()
    }

    // MARK: - EVALLOG.12: Enabled by Default

    // EVALLOG.12: Evaluation logging must be enabled by default but may be disabled
    func testEvaluationLoggingEnabledByDefaultAndCanBeDisabled() throws {
        // Given
        let defaultConfig = Flags.Configuration()

        // Then
        XCTAssertTrue(defaultConfig.trackEvaluations, "Evaluation logging should be enabled by default")

        // When
        let disabledConfig = Flags.Configuration(trackEvaluations: false)

        // Then
        XCTAssertFalse(disabledConfig.trackEvaluations, "Evaluation logging should be disableable")
    }

    // MARK: - EVALLOG.13: Runtime Default Used

    // EVALLOG.13: runtime_default_used true for DEFAULT reason
    func testRuntimeDefaultUsedForDefaultReason() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )

        // When
        aggregator.recordEvaluation(
            for: "test-flag",
            assignment: FlagAssignment(
                allocationKey: "", variationKey: "", variation: .boolean(false), reason: "DEFAULT", doLog: true
            ),
            evaluationContext: .mockAny(),
            flagError: nil
        )

        let flushExpectation = expectation(description: "Flush completes")
        aggregator.flush {
            flushExpectation.fulfill()
        }
        wait(for: [flushExpectation], timeout: 0.1)

        // Then
        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let event = try XCTUnwrap(events.first)

        XCTAssertEqual(event.runtimeDefaultUsed, true, "runtime_default_used should be true for DEFAULT reason")
    }

    // EVALLOG.13: runtime_default_used true for ERROR reason
    func testRuntimeDefaultUsedForErrorReason() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )

        // When
        aggregator.recordEvaluation(
            for: "test-flag", assignment: .mockAnyBoolean(), evaluationContext: .mockAny(), flagError: "evaluation error"
        )

        let flushExpectation = expectation(description: "Flush completes")
        aggregator.flush {
            flushExpectation.fulfill()
        }
        wait(for: [flushExpectation], timeout: 0.1)

        // Then
        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let event = try XCTUnwrap(events.first)

        XCTAssertEqual(event.runtimeDefaultUsed, true, "runtime_default_used should be true for ERROR")
    }

    // EVALLOG.13: runtime_default_used omitted when false
    func testRuntimeDefaultUsedOmittedWhenFalse() throws {
        // Already tested in testTracksAggregationFields - verified runtime_default_used is nil for MATCH reason
        try skipTest()
    }
}
