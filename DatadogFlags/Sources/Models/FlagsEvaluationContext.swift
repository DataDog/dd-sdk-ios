/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Context information used for feature flag targeting and evaluation.
///
/// The evaluation context contains user or session information that determines which flag
/// variations are returned. This typically includes a unique identifier (targeting key) and
/// optional custom attributes for more granular targeting.
///
/// You can create an evaluation context and set it on the client before evaluating flags:
///
/// ```swift
/// let context = FlagsEvaluationContext(
///     targetingKey: "user-123",
///     attributes: [
///         "email": .string("user@example.com"),
///         "plan": .string("premium"),
///         "age": .int(25),
///         "beta_tester": .bool(true)
///     ]
/// )
///
/// client.setEvaluationContext(context)
/// ```
public struct FlagsEvaluationContext: Equatable, Codable {
    /// The unique identifier used for targeting this user or session.
    ///
    /// This is typically a user ID, session ID, or device ID. The targeting key is used
    /// by the feature flag service to determine which variation to serve.
    public let targetingKey: String

    /// Custom attributes for more granular targeting.
    ///
    /// Attributes can include user properties, session data, or any other contextual information
    /// needed for flag evaluation rules. Use ``AnyValue`` to represent different data types.
    ///
    /// ```swift
    /// let context = FlagsEvaluationContext(
    ///     targetingKey: "user-123",
    ///     attributes: [
    ///         "email": .string("user@example.com"),
    ///         "plan": .string("premium"),
    ///         "signup_date": .string("2024-01-15")
    ///     ]
    /// )
    /// ```
    public let attributes: [String: AnyValue]

    /// Creates a new evaluation context.
    ///
    /// - Parameters:
    ///   - targetingKey: The unique identifier for targeting. Typically a user ID or session ID.
    ///   - attributes: Custom attributes for targeting rules. Defaults to an empty dictionary.
    public init(targetingKey: String, attributes: [String: AnyValue] = [:]) {
        self.targetingKey = targetingKey
        self.attributes = attributes
    }
}
