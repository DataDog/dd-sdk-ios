/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An error tha occurs during feature flag evaluation.
///
/// Indicates why a flag evaluation may have failed or returned a default value.
public enum FlagEvaluationError: Error {
    /// The feature flag provider is not ready to evaluate flags.
    case providerNotReady

    /// The requested feature flag was not found.
    case flagNotFound

    /// The flag value type doesn't match the requested type.
    case typeMismatch
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
    /// Returns `nil` if the flag was not found.
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

    /// The reason why this assignment was returned.
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
