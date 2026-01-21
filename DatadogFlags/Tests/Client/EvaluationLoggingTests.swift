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
        try skipTest()
    }

    // MARK: - EVALLOG.2: Log All Evaluations

    // EVALLOG.2: Log all evaluations when enabled, including defaults and errors (unlike exposure logging)
    func testLogsAllEvaluationsRegardlessOfDoLog() throws {
        try skipTest()
    }

    // MARK: - EVALLOG.3: Aggregation

    // EVALLOG.3: Aggregate evaluations by flag_key, variant_key, allocation_key, targeting_key, error_message, context
    func testAggregatesByCompositeKey() throws {
        try skipTest()
    }

    // EVALLOG.3: Tracks evaluation count, first/last timestamps, runtime_default_used, error_message
    func testTracksAggregationFields() throws {
        try skipTest()
    }

    // MARK: - EVALLOG.4: Event Buffering / Flushing

    // EVALLOG.4: Time-based flush with configurable interval (default 10s, min 1s, max 1min)
    func testFlushesAtConfigurableIntervalWithBoundsValidation() throws {
        try skipTest()
    }

    // EVALLOG.4: Size-based flush when aggregation map reaches limit
    func testFlushesWhenAggregationMapReachesLimit() throws {
        try skipTest()
    }

    // EVALLOG.4: Shutdown flush when SDK stops or page unloads
    func testFlushesOnShutdown() throws {
        try skipTest()
    }

    // MARK: - EVALLOG.5: Error Logging

    // EVALLOG.5: Errors logged as error.message and included in aggregation key
    func testLogsErrorMessageInAggregationKey() throws {
        try skipTest()
    }

    // MARK: - EVALLOG.6: Omit Empty Context

    // EVALLOG.6: Omit context.evaluation if targeting context contains only targetingKey
    func testOmitsContextWhenOnlyTargetingKey() throws {
        try skipTest()
    }

    // EVALLOG.6: Include context.evaluation when targeting context has additional attributes
    func testIncludesContextWhenAdditionalAttributes() throws {
        try skipTest()
    }

    // MARK: - EVALLOG.7: Targeting Key Presence

    // EVALLOG.7: Empty string "" is valid targeting key and must be included as targeting_key: ""
    func testKeepsEmptyStringTargetingKey() throws {
        try skipTest()
    }

    // EVALLOG.7: Omit targeting_key field when null or undefined
    func testOmitsNullTargetingKey() throws {
        try skipTest()
    }

    // MARK: - EVALLOG.8: Omit Undefined Optional Keys

    // EVALLOG.8: Omit variant.key, allocation.key when undefined (DEFAULT/ERROR reasons)
    func testOmitsVariantAndAllocationForRuntimeDefaults() throws {
        try skipTest()
    }

    // EVALLOG.8: Include variant.key, allocation.key when defined (normal evaluations)
    func testIncludesVariantAndAllocationForNormalEvaluations() throws {
        try skipTest()
    }

    // MARK: - EVALLOG.9: Context Changes

    // EVALLOG.9: Different targeting contexts create separate events regardless of matching results
    func testDifferentContextsCreateSeparateAggregations() throws {
        try skipTest()
    }

    // MARK: - EVALLOG.10: Timestamp Field

    // EVALLOG.10: timestamp field equals first_evaluation
    func testTimestampEqualsFirstEvaluation() throws {
        try skipTest()
    }

    // MARK: - EVALLOG.11: Aggregation Period Lifecycle

    // EVALLOG.11: Aggregation period starts at first evaluation and ends at flush
    func testAggregationPeriodLifecycle() throws {
        try skipTest()
    }

    // EVALLOG.11: After flushing, subsequent evaluations start new aggregation periods
    func testNewAggregationPeriodAfterFlush() throws {
        try skipTest()
    }

    // MARK: - EVALLOG.12: Enabled by Default

    // EVALLOG.12: Evaluation logging must be enabled by default but may be disabled
    func testEvaluationLoggingEnabledByDefaultAndCanBeDisabled() throws {
        try skipTest()
    }

    // MARK: - EVALLOG.13: Runtime Default Used

    // EVALLOG.13: runtime_default_used true for DEFAULT reason
    func testRuntimeDefaultUsedForDefaultReason() throws {
        try skipTest()
    }

    // EVALLOG.13: runtime_default_used true for ERROR reason
    func testRuntimeDefaultUsedForErrorReason() throws {
        try skipTest()
    }

    // EVALLOG.13: runtime_default_used omitted when false
    func testRuntimeDefaultUsedOmittedWhenFalse() throws {
        try skipTest()
    }
}
