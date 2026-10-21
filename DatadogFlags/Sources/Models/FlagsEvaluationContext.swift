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
    /// An empty evaluation context used for evaluation logging when no context has been set (PROVIDER_NOT_READY).
    static let empty = FlagsEvaluationContext(targetingKey: "", attributes: [:])

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

extension FlagsEvaluationContext {
    /// Parse the customer-owned timestamp without coercing other context value types.
    internal func experimentationOptOut() throws -> Bool {
        guard let value = attributes["dd_experimentation_opt_out_at"] else {
            return false
        }
        guard case .string(let timestamp) = value else { throw FlagsError.invalidContext }
        // Require a full date, time and offset. Foundation also accepts incomplete ISO8601 dates.
        let pattern = #"^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:[Zz]|[+-][0-9]{2}:[0-9]{2})\z"#
        guard timestamp.range(of: pattern, options: .regularExpression) != nil else {
            throw FlagsError.invalidContext
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let normalized = timestamp.uppercased()
        // ISO8601DateFormatter normalizes impossible dates and timezone offsets. Reject those first.
        let fields = normalized.prefix(19).split { !$0.isNumber }.compactMap { Int($0) }
        guard fields.count == 6 else { throw FlagsError.invalidContext }
        let components = DateComponents(
            year: fields[0],
            month: fields[1],
            day: fields[2],
            hour: fields[3],
            minute: fields[4],
            second: fields[5]
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard components.isValidDate(in: calendar) else { throw FlagsError.invalidContext }
        if normalized.last != "Z" {
            let offset = normalized.suffix(5).split(separator: ":").compactMap { Int($0) }
            guard offset.count == 2, offset[0] < 24, offset[1] < 60 else { throw FlagsError.invalidContext }
        }
        if formatter.date(from: normalized) != nil {
            return true
        }
        formatter.formatOptions = [.withInternetDateTime]
        guard formatter.date(from: normalized) != nil else { throw FlagsError.invalidContext }
        return true
    }
}
