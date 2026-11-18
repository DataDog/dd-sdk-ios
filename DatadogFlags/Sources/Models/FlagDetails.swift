/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// An error that occurs during feature flag evaluation.
///
/// Indicates why a flag evaluation may have failed or returned a default value.
public enum FlagEvaluationError: Error {
    /// The feature flag provider is not ready to evaluate flags.
    case providerNotReady

    /// The requested feature flag was not found.
    case flagNotFound

    /// The flag value type doesn't match the requested type.
    case typeMismatch

    /// The evaluation context is invalid, for example an invalid experimentation opt-out timestamp.
    case invalidContext

    /// The provider cannot evaluate the flag because the current subject has no authorized assignments.
    case general
}

/// Detailed information about a feature flag evaluation.
///
/// `FlagDetails` contains both the evaluated flag value and metadata about the evaluation,
/// including the variant served, evaluation reason, and any errors that occurred.
///
/// Use this type when you need access to evaluation metadata beyond just the flag value:
///
/// ```swift
/// let details = client.getBooleanDetails(key: "new-feature", defaultValue: false)
///
/// if details.value {
///     // Feature is enabled
///     print("Using variant: \(details.variant ?? "default")")
/// }
///
/// if let error = details.error {
///     print("Evaluation error: \(error)")
/// }
/// ```
public struct FlagDetails<T>: Equatable where T: Equatable {
    /// The feature flag key that was evaluated.
    public var key: String

    /// The evaluated flag value.
    ///
    /// This is either the flag's assigned value or the default value if evaluation failed.
    public var value: T

    /// The variant key for the evaluated flag.
    ///
    /// Variants identify which version of the flag was served. Returns `nil` if the flag
    /// was not found or if the default value was used.
    ///
    /// ```swift
    /// let details = client.getStringDetails(key: "button-text", defaultValue: "Click")
    /// print("Served variant: \(details.variant ?? "default")")
    /// ```
    public var variant: String?

    /// The reason why this evaluation result was returned.
    ///
    /// Provides context about how the flag was evaluated, such as "TARGETING_MATCH" or "DEFAULT".
    /// Assignments restored from disk report "CACHED"; network assignments retain their response reason.
    /// Returns `nil` when evaluation fails.
    public var reason: String?

    /// The error that occurred during evaluation, if any.
    ///
    /// Returns `nil` if evaluation succeeded. Check this property to determine if the returned
    /// value is from a successful evaluation or a fallback to the default value.
    public var error: FlagEvaluationError?

    /// The allocation key associated with this flag evaluation.
    ///
    /// Identifies the allocation bucket used when evaluating the flag. `nil` if the flag
    /// was not found, evaluation failed, or no allocation was associated with this evaluation.
    public var allocationKey: String?

    /// Internal evaluation-time consent for adapters. Never reconstructed from live configuration.
    @_spi(Internal)
    public var observeFullEvaluationData: Bool = false

    /// Metadata of the split that served the value.
    ///
    /// Holds one `__dd_feature.<key>` entry, for example `__dd_feature.holdout.key`, for each feature that the
    /// split sends to customer code. Values are `.string`, `.double` or `.bool`. The `__dd_feature.` prefix
    /// is the stable contract. A failed evaluation has an empty dictionary.
    public var flagMetadata: [String: AnyValue] = [:]

    /// Creates detailed flag evaluation information.
    ///
    /// - Parameters:
    ///   - key: The feature flag key.
    ///   - value: The evaluated or default value.
    ///   - variant: The variant key served, if any.
    ///   - reason: The evaluation reason, if available.
    ///   - error: Any error that occurred during evaluation.
    ///   - allocationKey: The allocation key for the evaluation, or `nil` if not available.
    public init(
        key: String,
        value: T,
        variant: String? = nil,
        reason: String? = nil,
        error: FlagEvaluationError? = nil,
        allocationKey: String? = nil
    ) {
        self.key = key
        self.value = value
        self.variant = variant
        self.reason = reason
        self.error = error
        self.allocationKey = allocationKey
    }

    /// Compares the public evaluation result: key, value, variant, reason, error, allocation key and flag metadata.
    public static func == (lhs: FlagDetails<T>, rhs: FlagDetails<T>) -> Bool {
        lhs.key == rhs.key
            && lhs.value == rhs.value
            && lhs.variant == rhs.variant
            && lhs.reason == rhs.reason
            && lhs.error == rhs.error
            && lhs.allocationKey == rhs.allocationKey
            && lhs.flagMetadata == rhs.flagMetadata
    }
}

/// Receives every flag evaluation, with the exposure verdict that the SDK uses for Datadog.
///
/// Use it to record exposures in your own data store, with the same deduplication as Datadog:
///
/// ```swift
/// var configuration = Flags.Configuration(trackExposures: false)
/// configuration.exposureHook = ExposureHook { evaluation in
///     guard evaluation.shouldSend else { return }
///     warehouse.enqueue(evaluation.flagKey, evaluation.variant, evaluation.features)
/// }
/// Flags.enable(with: configuration)
/// ```
///
/// The callback runs synchronously on the thread that evaluated the flag, including the main thread.
/// Keep it short and move I/O to another queue. The SDK catches and logs an error thrown by the callback
/// and returns the evaluation result unchanged. The hook observes evaluations; the SDK records exposures.
/// The callback is immutable and the error flag is lock-protected, so the hook is safe to share across threads.
public final class ExposureHook: @unchecked Sendable {
    private let callback: @Sendable (ExposureEvaluation) throws -> Void
    @ReadWriteLock
    private var hasLoggedError = false

    /// Creates a hook that calls `callback` after each flag evaluation.
    public init(_ callback: @escaping @Sendable (ExposureEvaluation) throws -> Void) {
        self.callback = callback
    }

    internal func notify(_ evaluation: ExposureEvaluation) {
        do {
            try callback(evaluation)
        } catch {
            var isFirstError = false
            _hasLoggedError.mutate { hasLoggedError in
                isFirstError = !hasLoggedError
                hasLoggedError = true
            }
            if isFirstError {
                DD.logger.warn("`ExposureHook` callback failed. Later failures are logged at debug level.", error: error)
            } else {
                DD.logger.debug("`ExposureHook` callback failed.", error: error)
            }
        }
    }
}

/// A completed flag evaluation, as seen by ``ExposureHook``.
///
/// The SDK creates every value; the initializer stays internal, as in the other Datadog client SDKs.
public struct ExposureEvaluation {
    /// The evaluated flag key.
    public let flagKey: String

    /// The served variant, or `nil` when evaluation failed.
    public let variant: String?

    /// The allocation that served the value, or `nil` when evaluation failed.
    public let allocationKey: String?

    /// The targeting key of ``evaluationContext``, or `nil` for an evaluation made before any context was set.
    public let targetingKey: String?

    /// The evaluation context used for the evaluation.
    public let evaluationContext: FlagsEvaluationContext

    /// The evaluation error, or `nil` for a successful evaluation.
    public let error: FlagEvaluationError?

    /// Features that the split sends to customer code, keyed by feature key (for example `holdout.key`).
    /// Values are `.string`, `.double` or `.bool`.
    public let features: [String: AnyValue]

    /// `true` for a successful evaluation of an allocation that logs exposures, repeats included.
    public let isExposure: Bool

    /// `true` when the subject was already exposed to the same flag, allocation, variant and split.
    public let isCacheHit: Bool

    /// `true` for a new exposure (`isExposure` and a cache miss): exactly what the SDK sends to Datadog
    /// when `Flags.Configuration.trackExposures` is enabled.
    public var shouldSend: Bool { isExposure && !isCacheHit }

    internal init(
        flagKey: String,
        variant: String?,
        allocationKey: String?,
        evaluationContext: FlagsEvaluationContext,
        error: FlagEvaluationError?,
        features: [String: AnyValue],
        isExposure: Bool,
        isCacheHit: Bool
    ) {
        self.flagKey = flagKey
        self.variant = variant
        self.allocationKey = allocationKey
        self.targetingKey = evaluationContext.hasTargetingKey ? evaluationContext.targetingKey : nil
        self.evaluationContext = evaluationContext
        self.error = error
        self.features = features
        self.isExposure = isExposure
        self.isCacheHit = isCacheHit
    }
}

/// A side-effect-free snapshot of cached precomputed feature flag assignments.
///
/// `FlagsSnapshot` is intended for diagnostics and export use cases. Reading a snapshot does not record
/// evaluations, exposures, or RUM feature flag evaluations. A snapshot may include assignments that have not
/// been evaluated through ``FlagsClientProtocol/getValue(key:defaultValue:)`` or
/// ``FlagsClientProtocol/getDetails(key:defaultValue:)``.
@available(*, message: "This API is in preview and may change in future releases")
public struct FlagsSnapshot: Equatable, Encodable {
    /// The cached precomputed assignments, keyed by feature flag key.
    public let assignments: [String: FlagSnapshot]

    /// Creates a feature flag snapshot.
    ///
    /// - Parameter assignments: The cached precomputed assignments, keyed by feature flag key.
    public init(assignments: [String: FlagSnapshot]) {
        self.assignments = assignments
    }
}

/// A side-effect-free snapshot of a cached precomputed feature flag assignment.
///
/// `FlagSnapshot` contains the value and metadata cached for a single feature flag. Reading a snapshot does not
/// record evaluations, exposures, or RUM feature flag evaluations.
@available(*, message: "This API is in preview and may change in future releases")
public struct FlagSnapshot: Equatable, Encodable {
    /// The assigned flag value.
    public let value: AnyValue

    /// The variant key for the assigned flag.
    public let variant: String

    /// The reason why this assignment was returned. Disk-restored assignments report "CACHED".
    public let reason: String

    /// Creates a feature flag assignment snapshot.
    ///
    /// - Parameters:
    ///   - value: The assigned flag value.
    ///   - variant: The variant key for the assigned flag.
    ///   - reason: The reason why this assignment was returned.
    public init(
        value: AnyValue,
        variant: String,
        reason: String
    ) {
        self.value = value
        self.variant = variant
        self.reason = reason
    }

    internal init?(_ assignment: FlagAssignment) {
        guard let value = assignment.variation.snapshotValue else {
            return nil
        }

        self.init(
            value: value,
            variant: assignment.variationKey,
            reason: assignment.reason
        )
    }
}

private extension FlagAssignment.Variation {
    var snapshotValue: AnyValue? {
        switch self {
        case .boolean(let value):
            return .bool(value)
        case .string(let value):
            return .string(value)
        case .integer(let value):
            return .int(value)
        case .double(let value):
            return .double(value)
        case .object(let value):
            return value
        case .unknown:
            return nil
        }
    }
}
