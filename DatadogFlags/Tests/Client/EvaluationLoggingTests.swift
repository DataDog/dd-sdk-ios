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
    // MARK: - Shared Test Fixtures

    /// Creates an aggregator, records multiple evaluations with time gaps, flushes, and returns the resulting event.
    /// Useful for tests that need to verify aggregation behavior with temporal data.
    private func recordAggregatedEvaluationWithTimeGaps(
        assignment: FlagAssignment = FlagAssignment(
            allocationKey: "alloc-1", variationKey: "var-1", variation: .boolean(true), reason: "MATCH", doLog: true
        ),
        context: FlagsEvaluationContext = FlagsEvaluationContext(targetingKey: "user-123", attributes: [:]),
        flagError: String? = nil
    ) throws -> (event: FlagEvaluationEvent, featureScope: FeatureScopeMock) {
        let featureScope = FeatureScopeMock()
        let dateProvider = RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC())
        let aggregator = EvaluationAggregator(
            dateProvider: dateProvider,
            featureScope: featureScope,
            flushInterval: 60.0
        )

        // Record 3 evaluations with time gaps
        aggregator.recordEvaluation(for: "test-flag", assignment: assignment, evaluationContext: context, flagError: flagError)
        Thread.sleep(forTimeInterval: 0.05)

        dateProvider.advance(bySeconds: 1)
        aggregator.recordEvaluation(for: "test-flag", assignment: assignment, evaluationContext: context, flagError: flagError)
        Thread.sleep(forTimeInterval: 0.05)

        dateProvider.advance(bySeconds: 2)
        aggregator.recordEvaluation(for: "test-flag", assignment: assignment, evaluationContext: context, flagError: flagError)

        aggregator.sendEvaluations()

        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let event = try XCTUnwrap(events.first)
        return (event, featureScope)
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
        let contextWithRUM = DatadogContext.mockWith(
            additionalContext: [RUMCoreContext.mockWith(applicationID: "rum-app-123")]
        )
        let request = try builder.request(for: events, with: contextWithRUM, execution: .mockAny())
        XCTAssertEqual(request.allHTTPHeaderFields?["Content-Type"], "application/json")

        let httpBodyData = try XCTUnwrap(request.httpBody)
        let decodedBatch = try JSONDecoder().decode(BatchedFlagEvaluations.self, from: httpBodyData)

        XCTAssertNotNil(decodedBatch.context)
        XCTAssertEqual(decodedBatch.flagEvaluations.count, 1)
        XCTAssertEqual(decodedBatch.flagEvaluations.first?.flag.key, "test-flag")

        XCTAssertEqual(decodedBatch.context?.rum?.application?.id, "rum-app-123")
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

        aggregator.sendEvaluations()

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 2, "Should log all evaluations regardless of doLog")
    }

    // EVALLOG.2: Log evaluation when provider is not ready (no context set)
    func testLogsEvaluationWhenProviderNotReady() {
        // Given
        let evaluationLogger = EvaluationLoggerMock()
        let client = FlagsClient(
            repository: FlagsRepositoryMock(
                state: nil // No context set - provider not ready
            ),
            exposureLogger: ExposureLoggerMock(),
            evaluationLogger: evaluationLogger,
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )

        // When
        let details = client.getDetails(key: "any-flag", defaultValue: false)

        // Then
        XCTAssertEqual(details.error, .providerNotReady)
        XCTAssertEqual(evaluationLogger.logEvaluationCalls.count, 1, "Should log evaluation even when provider is not ready")
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].flagKey, "any-flag")
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].error, "PROVIDER_NOT_READY")
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].context, .empty)
    }

    // EVALLOG.2: Log evaluation when flag is not found
    func testLogsEvaluationWhenFlagNotFound() {
        // Given
        let evaluationLogger = EvaluationLoggerMock()
        let client = FlagsClient(
            repository: FlagsRepositoryMock(
                state: .init(
                    flags: [:], // No flags
                    context: .init(targetingKey: "user-123", attributes: [:]),
                    date: .mockAny()
                )
            ),
            exposureLogger: ExposureLoggerMock(),
            evaluationLogger: evaluationLogger,
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )

        // When
        let details = client.getDetails(key: "non-existent-flag", defaultValue: false)

        // Then
        XCTAssertEqual(details.error, .flagNotFound)
        XCTAssertEqual(evaluationLogger.logEvaluationCalls.count, 1, "Should log evaluation even when flag is not found")
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].flagKey, "non-existent-flag")
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].error, "FLAG_NOT_FOUND")
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].assignment.reason, "DEFAULT")
    }

    // EVALLOG.2: Log evaluation when type mismatch occurs
    func testLogsEvaluationWhenTypeMismatch() {
        // Given
        let evaluationLogger = EvaluationLoggerMock()
        let client = FlagsClient(
            repository: FlagsRepositoryMock(
                state: .init(
                    flags: [
                        "string-flag": .init(
                            allocationKey: "alloc-1",
                            variationKey: "var-1",
                            variation: .string("hello"), // String type
                            reason: "MATCH",
                            doLog: true
                        )
                    ],
                    context: .init(targetingKey: "user-123", attributes: [:]),
                    date: .mockAny()
                )
            ),
            exposureLogger: ExposureLoggerMock(),
            evaluationLogger: evaluationLogger,
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )

        // When - Request as boolean (type mismatch)
        let details: FlagDetails<Bool> = client.getDetails(key: "string-flag", defaultValue: false)

        // Then
        XCTAssertEqual(details.error, .typeMismatch)
        XCTAssertEqual(evaluationLogger.logEvaluationCalls.count, 1, "Should log evaluation even when type mismatch occurs")
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].flagKey, "string-flag")
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].error, "TYPE_MISMATCH")
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].assignment.variationKey, "var-1")
    }

    // EVALLOG.2: Verify no exposure logging for error cases (only evaluation logging)
    func testNoExposureLoggingForErrorCases() {
        // Given
        let exposureLogger = ExposureLoggerMock()
        let evaluationLogger = EvaluationLoggerMock()
        let client = FlagsClient(
            repository: FlagsRepositoryMock(
                state: .init(
                    flags: [:],
                    context: .init(targetingKey: "user-123", attributes: [:]),
                    date: .mockAny()
                )
            ),
            exposureLogger: exposureLogger,
            evaluationLogger: evaluationLogger,
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )

        // When
        _ = client.getDetails(key: "non-existent-flag", defaultValue: false)

        // Then
        XCTAssertEqual(exposureLogger.logExposureCalls.count, 0, "Should NOT log exposure for flag not found")
        XCTAssertEqual(evaluationLogger.logEvaluationCalls.count, 1, "Should log evaluation for flag not found")
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

        let assignment = FlagAssignment(
            allocationKey: "alloc-1", variationKey: "var-1", variation: .boolean(true), reason: "MATCH", doLog: true
        )
        let context = FlagsEvaluationContext(targetingKey: "user-1", attributes: [:])

        // When - 3 identical + 1 different flag key
        aggregator.recordEvaluation(for: "test-flag", assignment: assignment, evaluationContext: context, flagError: nil)
        aggregator.recordEvaluation(for: "test-flag", assignment: assignment, evaluationContext: context, flagError: nil)
        aggregator.recordEvaluation(for: "test-flag", assignment: assignment, evaluationContext: context, flagError: nil)
        aggregator.recordEvaluation(for: "other-flag", assignment: assignment, evaluationContext: context, flagError: nil)

        aggregator.sendEvaluations()

        // Then
        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(events.count, 2)

        let testFlagEvent = try XCTUnwrap(events.first { $0.flag.key == "test-flag" })
        let otherFlagEvent = try XCTUnwrap(events.first { $0.flag.key == "other-flag" })

        XCTAssertEqual(testFlagEvent.evaluationCount, 3, "Identical evaluations should aggregate")
        XCTAssertEqual(otherFlagEvent.evaluationCount, 1)
    }

    // EVALLOG.3: Tracks evaluation count and first/last timestamps
    func testTracksAggregationFields() throws {
        // Given/When
        let (event, featureScope) = try recordAggregatedEvaluationWithTimeGaps()

        // Then - EVALLOG.3: Should track evaluation count
        XCTAssertEqual(event.evaluationCount, 3)
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "Should aggregate into single event")

        // Then - EVALLOG.3: Should track first and last timestamps
        XCTAssertLessThan(event.firstEvaluation, event.lastEvaluation)
    }

    // MARK: - EVALLOG.4: Event Buffering / Flushing

    // EVALLOG.4: Time-based flush with configurable interval (default 10s, min 1s, max 1min)
    func testDefaultEvaluationFlushInterval() throws {
        let config = Flags.Configuration()
        XCTAssertEqual(config.evaluationFlushInterval, 10.0, "Default flush interval should be 10 seconds")
    }

    func testEvaluationFlushIntervalBelowMinimumIsClamped() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let core = FeatureRegistrationCoreMock()
        let config = Flags.Configuration(evaluationFlushInterval: 0.5)

        // When
        Flags.enable(with: config, in: core)

        // Then
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            "`Flags.Configuration.evaluationFlushInterval` cannot be less than 1.0s. A value of 1.0s will be used."
        )
    }

    func testEvaluationFlushIntervalAboveMaximumIsClamped() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let core = FeatureRegistrationCoreMock()
        let config = Flags.Configuration(evaluationFlushInterval: 120.0)

        // When
        Flags.enable(with: config, in: core)

        // Then
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            "`Flags.Configuration.evaluationFlushInterval` cannot exceed 60.0s. A value of 60.0s will be used."
        )
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

        // Deallocate aggregator (deinit calls sendEvaluations)
        aggregator = nil

        // Then
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "Deinit should send pending evaluations")

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

        aggregator.sendEvaluations()

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

        aggregator.sendEvaluations()

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

        aggregator.sendEvaluations()

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

        aggregator.sendEvaluations()

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

        aggregator.sendEvaluations()

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

        aggregator.sendEvaluations()

        // Then
        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let event = try XCTUnwrap(events.first)

        XCTAssertEqual(event.variant?.key, "var-1", "Should include variant key for normal evaluations")
        XCTAssertEqual(event.allocation?.key, "alloc-1", "Should include allocation key for normal evaluations")
    }

    // MARK: - EVALLOG.9: Context Changes

    // EVALLOG.9: Different targeting contexts create separate events regardless of matching results
    func testDifferentContextValuesCreateSeparateAggregations() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60.0
        )

        let assignment = FlagAssignment(
            allocationKey: "alloc-1", variationKey: "var-1", variation: .boolean(true), reason: "MATCH", doLog: true
        )

        // When - same context keys, different values: 2x iPhone, 1x Android
        aggregator.recordEvaluation(
            for: "test-flag",
            assignment: assignment,
            evaluationContext: FlagsEvaluationContext(targetingKey: "user-1", attributes: ["device": .string("iPhone")]),
            flagError: nil
        )
        aggregator.recordEvaluation(
            for: "test-flag",
            assignment: assignment,
            evaluationContext: FlagsEvaluationContext(targetingKey: "user-1", attributes: ["device": .string("Android")]),
            flagError: nil
        )
        aggregator.recordEvaluation(
            for: "test-flag",
            assignment: assignment,
            evaluationContext: FlagsEvaluationContext(targetingKey: "user-1", attributes: ["device": .string("iPhone")]),
            flagError: nil
        )

        aggregator.sendEvaluations()

        // Then
        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(events.count, 2, "Different context values should create separate aggregations")

        let iphoneEvent = try XCTUnwrap(events.first { $0.context?.evaluation?["device"] == .string("iPhone") })
        let androidEvent = try XCTUnwrap(events.first { $0.context?.evaluation?["device"] == .string("Android") })

        XCTAssertEqual(iphoneEvent.evaluationCount, 2)
        XCTAssertEqual(androidEvent.evaluationCount, 1)
    }

    // MARK: - EVALLOG.10: Timestamp Field

    // EVALLOG.10: timestamp field equals first_evaluation
    func testTimestampEqualsFirstEvaluation() throws {
        // Given/When
        let (event, _) = try recordAggregatedEvaluationWithTimeGaps()

        // Then
        XCTAssertEqual(event.timestamp, event.firstEvaluation)
    }

    // MARK: - EVALLOG.11: Aggregation Period Lifecycle

    // EVALLOG.11: Aggregation period starts at first evaluation and ends at flush; subsequent evaluations start new periods
    func testAggregationPeriodLifecycle() throws {
        // Given
        let featureScope = FeatureScopeMock()
        let dateProvider = RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC())
        let aggregator = EvaluationAggregator(
            dateProvider: dateProvider,
            featureScope: featureScope,
            flushInterval: 100.0
        )

        // When - Period 1: record evaluations and flush
        aggregator.recordEvaluation(for: "flag-1", assignment: .mockAnyBoolean(), evaluationContext: .mockAny(), flagError: nil)
        dateProvider.advance(bySeconds: 1)
        aggregator.recordEvaluation(for: "flag-1", assignment: .mockAnyBoolean(), evaluationContext: .mockAny(), flagError: nil)

        aggregator.sendEvaluations()

        // Then - Period 1 ends with aggregated event
        let firstPeriodEvents: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(firstPeriodEvents.count, 1)
        let firstEvent = try XCTUnwrap(firstPeriodEvents.first)
        XCTAssertEqual(firstEvent.evaluationCount, 2)

        // When - Period 2: record new evaluation after flush
        dateProvider.advance(bySeconds: 10)
        aggregator.recordEvaluation(for: "flag-1", assignment: .mockAnyBoolean(), evaluationContext: .mockAny(), flagError: nil)

        aggregator.sendEvaluations()

        // Then - Period 2 starts fresh
        let allEvents: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(allEvents.count, 2, "Should have 2 events from 2 aggregation periods")

        let secondEvent = try XCTUnwrap(allEvents.last)
        XCTAssertEqual(secondEvent.evaluationCount, 1, "New period should start fresh")
        XCTAssertGreaterThan(secondEvent.firstEvaluation, firstEvent.lastEvaluation)
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

        aggregator.sendEvaluations()

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

        aggregator.sendEvaluations()

        // Then
        let events: [FlagEvaluationEvent] = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        let event = try XCTUnwrap(events.first)

        XCTAssertEqual(event.runtimeDefaultUsed, true, "runtime_default_used should be true for ERROR")
    }

    // EVALLOG.13: runtime_default_used omitted when false
    func testRuntimeDefaultUsedOmittedWhenFalse() throws {
        // Given/When - shared helper uses MATCH reason by default
        let (event, _) = try recordAggregatedEvaluationWithTimeGaps()

        // Then
        XCTAssertNil(event.runtimeDefaultUsed, "runtime_default_used should be omitted for MATCH reason")
    }
}
