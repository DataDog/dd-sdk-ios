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

    /// Creates detailed flag evaluation information.
    ///
    /// - Parameters:
    ///   - key: The feature flag key.
    ///   - value: The evaluated or default value.
    ///   - variant: The variant key served, if any.
    ///   - reason: The evaluation reason, if available.
    ///   - error: Any error that occurred during evaluation.
    public init(
        key: String,
        value: T,
        variant: String? = nil,
        reason: String? = nil,
        error: FlagEvaluationError? = nil
    ) {
        self.key = key
        self.value = value
        self.variant = variant
        self.reason = reason
        self.error = error
    }
}
