/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public protocol FlagsClientInternal: AnyObject {
    /// Evaluates like `getDetails(key:defaultValue:)`, records and sends the exposure the same way,
    /// and returns the exposure decision for the Datadog OpenFeature provider's exposure hook.
    /// Returns nil for a client that cannot evaluate.
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func getDetailsWithExposure<T>(key: String, defaultValue: T) -> FlagDetailsWithExposure<T>? where T: Equatable, T: FlagValue

    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func getFlagAssignments() -> [String: FlagAssignment]?

    /// Returns the readable assignments and the `observeFullEvaluationData` consent of the configuration they came from.
    /// Returns nil in the error state and when the readable configuration is missing or obfuscated.
    /// Cache both together, and use that consent for missing-flag evaluations.
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func getFlagAssignmentsWithConsent() -> (assignments: [String: FlagAssignment], observeFullEvaluationData: Bool)?

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

    /// Records only an evaluation event. A missing assignment represents a runtime default and reports in protected mode.
    /// For a present assignment, its `observeFullEvaluationData` selects the mode: full mode sends the raw targeting key
    /// and the context attributes, and protected mode sends the hashed key and omits the attributes.
    /// Respects the client's telemetry opt-out configuration using the supplied context.
    /// `errorCode` must be an OpenFeature error code; unrecognized codes are reported as `GENERAL`.
    /// Does not fetch configuration, record an exposure, or report to RUM.
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func sendFlagEvaluationEvent(key: String, assignment: FlagAssignment?, context: FlagsEvaluationContext, errorCode: String?)

    /// Records only an evaluation event with the consent the caller captured with its assignments, never the
    /// current configuration. A nil `telemetryTargetingKey` omits the key; the context still controls opt-out.
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func sendFlagEvaluationEvent(
        key: String,
        assignment: FlagAssignment?,
        context: FlagsEvaluationContext,
        telemetryTargetingKey: String?,
        observeFullEvaluationData: Bool,
        errorCode: String?
    )

    /// Records only a RUM flag annotation, respecting the client's telemetry opt-out configuration.
    /// Does not fetch configuration, record an exposure, or record an evaluation event.
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func sendFlagRUMEvaluation(key: String, variant: String, context: FlagsEvaluationContext)

    /// Records the exposure of an assignment that the caller evaluated, in the cache that native evaluations use.
    /// `context` is the context the caller captured with the assignment; `nil` means the evaluation has no subject.
    /// With `sendToDatadog` set to `false`, the call records in the cache and writes no event.
    /// Does not read the client's assignments, record an evaluation event, or report to RUM.
    /// > Warning: This is an internal method and can break in the future.
    @_spi(Internal)
    func admitSnapshotExposure(
        key: String,
        assignment: FlagAssignment,
        context: FlagsEvaluationContext?,
        sendToDatadog: Bool
    ) -> FlagSnapshotExposureDecision
}

extension FlagsClientInternal {
    @_spi(Internal)
    public func getDetailsWithExposure<T>(key: String, defaultValue: T) -> FlagDetailsWithExposure<T>? where T: Equatable, T: FlagValue {
        nil
    }

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

    @_spi(Internal)
    public func admitSnapshotExposure(
        key: String,
        assignment: FlagAssignment,
        context: FlagsEvaluationContext?,
        sendToDatadog: Bool
    ) -> FlagSnapshotExposureDecision {
        .unavailable
    }
}

extension FlagsClientInternal {
    @_spi(Internal)
    public func getFlagAssignmentsWithConsent() -> (assignments: [String: FlagAssignment], observeFullEvaluationData: Bool)? {
        nil
    }

    @_spi(Internal)
    public func sendFlagEvaluationEvent(
        key: String,
        assignment: FlagAssignment?,
        context: FlagsEvaluationContext,
        telemetryTargetingKey: String?,
        observeFullEvaluationData: Bool,
        errorCode: String?
    ) {
        // no-op
    }
}

/// The result of `admitSnapshotExposure(key:assignment:context:sendToDatadog:)`.
@_spi(Internal)
public enum FlagSnapshotExposureDecision: Equatable {
    /// The cache recorded a new or changed assignment for the subject and flag. A record-only call is admitted too.
    case admitted
    /// The cache already held this allocation, variant and serial ID for the subject and flag.
    case duplicate
    /// The evaluation has no subject, logs no exposures, or has a blank allocation key or variant.
    case ineligible
    /// The client cannot decide: it lacks support, the tracking consent is other than granted,
    /// or the native context policy rejects the captured context.
    case unavailable
}

/// The exposure decision of one evaluation, for the Datadog OpenFeature provider.
@_spi(Internal)
public struct FlagExposureDecision: Equatable {
    /// A successful evaluation of an allocation that logs exposures, with a non-blank allocation key and variant.
    public let isExposure: Bool
    /// For an exposure, this client's exposure cache holds the same allocation, variant and serial ID
    /// for the subject and flag.
    public let isCacheHit: Bool
    /// The targeting key of the evaluation, or `nil` for an evaluation made before any context was set.
    public let targetingKey: String?
    /// `HOOK` features of the selected split, keyed by feature key without prefix.
    public let features: [String: AnyValue]

    /// A new exposure: `isExposure` and a cache miss.
    public var shouldSend: Bool { isExposure && !isCacheHit }

    public init(isExposure: Bool, isCacheHit: Bool, targetingKey: String?, features: [String: AnyValue]) {
        self.isExposure = isExposure
        self.isCacheHit = isCacheHit
        self.targetingKey = targetingKey
        self.features = features
    }
}

/// An evaluation result with its exposure decision.
@_spi(Internal)
public struct FlagDetailsWithExposure<T: Equatable> {
    public let details: FlagDetails<T>
    public let exposure: FlagExposureDecision

    public init(details: FlagDetails<T>, exposure: FlagExposureDecision) {
        self.details = details
        self.exposure = exposure
    }
}
