/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public protocol FlagsClientInternal: AnyObject {
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func getFlagAssignments() -> [String: FlagAssignment]?

    /// Assignments and consent must be cached together, including for missing-flag evaluations.
    @_spi(Internal)
    func getFlagAssignmentsWithConsent() -> (assignments: [String: FlagAssignment], observeFullEvaluationData: Bool)?

    /// Pass the consent captured by the bridge at evaluation time, never the current configuration.
    @_spi(Internal)
    func sendFlagEvaluation(
        key: String,
        assignment: FlagAssignment,
        context: FlagsEvaluationContext,
        observeFullEvaluationData: Bool,
        flagError: String?
    )

    /// Replays with a validated telemetry key: nil omits the key; an empty string remains present.
    /// The original context still controls exposures and subject telemetry opt-out. Its attributes
    /// are retained only when the captured consent enables full evaluation data.
    @_spi(Internal)
    func sendFlagEvaluation(
        key: String,
        assignment: FlagAssignment,
        context: FlagsEvaluationContext,
        telemetryTargetingKey: String?,
        observeFullEvaluationData: Bool,
        flagError: String?
    )

    /// Records exposure, evaluation, and RUM tracking according to the enabled native features.
    /// Use the separate operations below for independently selected tracking hooks.
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func sendFlagEvaluation(key: String, assignment: FlagAssignment, context: FlagsEvaluationContext)

    /// Records only an exposure, using the assignment and context captured by the caller.
    /// Does not fetch configuration, record an evaluation event, or report to RUM.
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func sendFlagExposure(key: String, assignment: FlagAssignment, context: FlagsEvaluationContext)

    /// Records only an evaluation event. A missing assignment represents a runtime default.
    /// Respects the client's telemetry opt-out configuration using the supplied context.
    /// `errorCode` must be an OpenFeature error code; unrecognized codes are reported as `GENERAL`.
    /// Does not fetch configuration, record an exposure, or report to RUM.
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func sendFlagEvaluationEvent(key: String, assignment: FlagAssignment?, context: FlagsEvaluationContext, errorCode: String?)

    /// Records only a RUM flag annotation, respecting the client's telemetry opt-out configuration.
    /// Does not fetch configuration, record an exposure, or record an evaluation event.
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func sendFlagRUMEvaluation(key: String, variant: String, context: FlagsEvaluationContext)
}

extension FlagsClientInternal {
    @_spi(Internal)
    public func getFlagAssignments() -> [String: FlagAssignment]? {
        // no-op
        return nil
    }

    @_spi(Internal)
    public func sendFlagEvaluation(key: String, assignment: FlagAssignment, context: FlagsEvaluationContext) {
        // no-op
    }

    @_spi(Internal)
    public func sendFlagExposure(key: String, assignment: FlagAssignment, context: FlagsEvaluationContext) {
        // no-op
    }

    @_spi(Internal)
    public func sendFlagEvaluationEvent(key: String, assignment: FlagAssignment?, context: FlagsEvaluationContext, errorCode: String?) {
        // no-op
    }

    @_spi(Internal)
    public func sendFlagRUMEvaluation(key: String, variant: String, context: FlagsEvaluationContext) {
        // no-op
    }
}

extension FlagsClientInternal {
    @_spi(Internal)
    public func getFlagAssignmentsWithConsent() -> (assignments: [String: FlagAssignment], observeFullEvaluationData: Bool)? {
        nil
    }

    @_spi(Internal)
    public func sendFlagEvaluation(
        key: String,
        assignment: FlagAssignment,
        context: FlagsEvaluationContext,
        observeFullEvaluationData: Bool,
        flagError: String?
    ) {
        // No-op for unavailable clients.
    }

    @_spi(Internal)
    public func sendFlagEvaluation(
        key: String,
        assignment: FlagAssignment,
        context: FlagsEvaluationContext,
        telemetryTargetingKey: String?,
        observeFullEvaluationData: Bool,
        flagError: String?
    ) {
        // No-op for unavailable clients.
    }
}
