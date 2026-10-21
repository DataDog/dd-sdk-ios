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

    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func sendFlagEvaluation(key: String, assignment: FlagAssignment, context: FlagsEvaluationContext)
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
}
