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
    internal func experimentationOptOut(mode: FlagsClient.ExperimentationOptOutMode) throws -> ExperimentationOptOut? {
        guard mode != .disabled else {
            return nil
        }
        guard let value = attributes["dd_experimentation_opt_out_at"] else {
            return nil
        }
        guard case .string(let timestamp) = value else { throw FlagsError.invalidContext }
        let cutoff = try OptOutInstant(rfc3339: timestamp)
        return mode == .immediate ? .immediate : .futureExperimentsOnly(cutoff: cutoff)
    }
}

internal enum ExperimentationOptOut: Equatable, Codable {
    case immediate
    case futureExperimentsOnly(cutoff: OptOutInstant)

    var wireMode: String {
        switch self {
        case .immediate: return "immediate"
        case .futureExperimentsOnly: return "future_experiments_only"
        }
    }

    static func accepts(_ response: FlagAssignmentsResponse, for policy: ExperimentationOptOut?) -> Bool {
        guard let policy else {
            // An unfiltered request must not install assignments filtered for another policy.
            return !response.hasMalformedOptOutMetadata
                && response.experimentationOptOut != true
                && response.experimentationOptOutMode == nil
                && response.experimentationOptOutAt == nil
        }
        return policy.isAcknowledged(by: response)
    }

    func isAcknowledged(by response: FlagAssignmentsResponse) -> Bool {
        switch self {
        case .immediate:
            return response.experimentationOptOut == true
                && (response.experimentationOptOutMode == wireMode
                    || (response.experimentationOptOutMode == nil && response.experimentationOptOutAt == nil))
        case .futureExperimentsOnly(let cutoff):
            guard response.experimentationOptOutMode == wireMode,
                  let acknowledged = response.experimentationOptOutAt,
                  let instant = try? OptOutInstant(rfc3339: acknowledged) else { return false }
            return instant == cutoff
        }
    }
}

/// An RFC3339 instant with nanosecond precision.
internal struct OptOutInstant: Hashable, Codable {
    /// Whole seconds since 1970-01-01T00:00:00Z.
    let seconds: Int64
    /// Nanoseconds within the second, truncated to 9 digits.
    let nanoseconds: Int32

    init(rfc3339 timestamp: String) throws {
        let input = timestamp.uppercased()
        guard let match = Self.pattern?.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else {
            throw FlagsError.invalidContext
        }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: input).map { String(input[$0]) }
        }
        let dateTime = group(1)
        let fraction = group(2)
        let offsetSign = group(3)
        let offsetHours = group(4).flatMap { Int64($0) }
        let offsetMinutes = group(5).flatMap { Int64($0) }

        // `DateFormatter` validates the calendar fields; the round trip rejects rolled-over dates such as April 31.
        guard let dateTime, let date = Self.formatter.date(from: dateTime), Self.formatter.string(from: date) == dateTime else {
            throw FlagsError.invalidContext
        }

        var offset: Int64 = 0
        if let offsetSign, let offsetHours, let offsetMinutes {
            guard offsetHours < 24, offsetMinutes < 60 else { throw FlagsError.invalidContext }
            offset = (offsetHours * 3_600 + offsetMinutes * 60) * (offsetSign == "-" ? -1 : 1)
        }

        let seconds = Int64(date.timeIntervalSince1970) - offset
        let nanosecondDigits = (fraction ?? "").prefix(9).padding(toLength: 9, withPad: "0", startingAt: 0)
        guard Self.supportedRange.contains(seconds), let nanoseconds = Int32(nanosecondDigits) else {
            throw FlagsError.invalidContext
        }
        self.seconds = seconds
        self.nanoseconds = nanoseconds
    }

    // Groups: 1 date and time, 2 fraction digits, 3 offset sign, 4 offset hours, 5 offset minutes.
    private static let pattern = try? NSRegularExpression(
        pattern: #"^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(?:\.([0-9]+))?(?:Z|([+-])([0-9]{2}):([0-9]{2}))\z"#
    )

    /// Years 0000 to 9999 in UTC.
    private static let supportedRange: Range<Int64> = -62_167_219_200..<253_402_300_800

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        // Apply Gregorian rules across the supported range, including dates before 1582.
        formatter.gregorianStartDate = Date(timeIntervalSince1970: TimeInterval(supportedRange.lowerBound))
        // The extended year field includes year zero.
        formatter.dateFormat = "uuuu-MM-dd'T'HH:mm:ss"
        formatter.isLenient = false
        return formatter
    }()
}
