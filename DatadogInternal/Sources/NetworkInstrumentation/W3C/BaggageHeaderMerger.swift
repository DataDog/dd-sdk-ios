/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Utility class for merging baggage headers according to the W3C Baggage specification.
/// See: https://www.w3.org/TR/baggage/#header-name
///
/// Notes on precedence and determinism:
/// - When merging, values from the new header always override values from the previous header for identical keys.
///   This includes the SDK-managed keys: "session.id", "user.id" and "account.id".
/// - The formatted output is deterministic: keys are sorted lexicographically to stabilize header ordering
///   (useful for debugging).
public struct BaggageHeaderMerger {
    /// Merges two baggage header values, with new values taking precedence over existing ones.
    /// - Parameters:
    ///   - previousHeader: The existing baggage header value
    ///   - newHeader: The new baggage header value to merge
    /// - Returns: A merged baggage header value
    public static func merge(previousHeader: String, with newHeader: String) -> String {
        guard previousHeader != newHeader else {
            return previousHeader
        }

        let previousHeaderDict = parseBaggageHeader(previousHeader)
        let newHeaderDict = parseBaggageHeader(newHeader)

        let mergedHeaderDict = previousHeaderDict.merging(newHeaderDict) { _, new in
            return new // New values override existing ones
        }

        return formatBaggageHeader(from: mergedHeaderDict)
    }

    /// Parses a baggage header string into a dictionary of key-value pairs.
    /// - Parameter header: The baggage header string to parse
    /// - Returns: A dictionary of key-value pairs
    private static func parseBaggageHeader(_ header: String) -> [String: String] {
        let headerFields = header.trimmingCharacters(in: .whitespaces).split(separator: ",")
        var headerDict: [String: String] = [:]

        for field in headerFields {
            if let (key, value) = extractKeyValue(from: String(field)) {
                headerDict[key] = value
            }
        }

        return headerDict
    }

    /// Formats a dictionary of key-value pairs into a baggage header string.
    /// - Parameter dict: The dictionary to format
    /// - Returns: A formatted baggage header string with keys sorted lexicographically for determinism
    private static func formatBaggageHeader(from dict: [String: String]) -> String {
        return dict
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
    }

    /// Extracts a key-value pair from a baggage field string.
    /// - Parameter field: The baggage field string
    /// - Returns: A tuple containing the key and value, or nil if parsing fails
    private static func extractKeyValue(from field: String) -> (key: String, value: String)? {
        guard let equalIndex = field.firstIndex(of: "=") else {
            return nil
        }

        let key = field[..<equalIndex].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            return nil
        }

        let value = field[field.index(after: equalIndex)...].trimmingCharacters(in: .whitespaces)

        return (key: key, value: value)
    }
}

