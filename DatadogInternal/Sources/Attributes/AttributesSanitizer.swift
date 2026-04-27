/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Common attributes sanitizer for all features.
public struct AttributesSanitizer {
    public struct Constraints {
        /// Maximum number of nested levels in attribute name. E.g. `person.address.street` has 3 levels.
        /// If attribute name exceeds this number, extra levels are escaped by using `_` character (`one.two.(...).nine.ten_eleven_twelve`).
        public static let maxNestedLevelsInAttributeName: Int = 10
        /// Maximum number of attributes in log.
        /// If this number is exceeded, extra attributes will be ignored.
        public static let maxNumberOfAttributes: Int = 256
        /// Maximum length of a string attribute value, measured in UTF-16 code units (Swift `String.utf16.count`).
        /// Values exceeding this will be truncated. This matches the backend hard limit — the backend measures
        /// length using Java's `String.length()`, which counts UTF-16 code units. For ASCII and most accented
        /// characters this is equivalent to Swift's `String.count`, but emoji may differ
        /// (e.g. 👩🏻 = 1 grapheme cluster but 4 UTF-16 code units).
        public static let maxAttributeValueLength: Int = 25_600
    }

    let featureName: String

    public init(featureName: String) {
        self.featureName = featureName
    }

    // MARK: - Attribute keys sanitization

    /// Attribute keys can only have `Constants.maxNestedLevelsInAttributeName` levels.
    /// Extra levels are escaped with "_", e.g.:
    ///
    ///     one.two.three.four.five.six.seven.eight.nine.ten.eleven
    ///
    /// becomes:
    ///
    ///     one.two.three.four.five.six.seven.eight_nine_ten_eleven
    ///
    public func sanitizeKeys<Value>(for attributes: [String: Value], prefixLevels: Int = 0) -> [String: Value] {
        let sanitizedAttributes: [(String, Value)] = attributes.map { key, value in
            let sanitizedName = sanitize(attributeKey: key, prefixLevels: prefixLevels)
            if sanitizedName != key {
                DD.logger.warn(
                    """
                    \(featureName) attribute '\(key)' was modified to '\(sanitizedName)' to match Datadog constraints.
                    """
                )
                return (sanitizedName, value)
            } else {
                return (key, value)
            }
        }
        return Dictionary(uniqueKeysWithValues: sanitizedAttributes)
    }

    private func sanitize(attributeKey: String, prefixLevels: Int = 0) -> String {
        var dotsCount = prefixLevels
        var sanitized = ""
        for char in attributeKey {
            if char == "." {
                dotsCount += 1
                sanitized.append(dotsCount >= Constraints.maxNestedLevelsInAttributeName ? "_" : char)
            } else {
                sanitized.append(char)
            }
        }
        return sanitized
    }

    // MARK: - Attribute values sanitization

    /// Truncates string attribute values exceeding `Constraints.maxAttributeValueLength`.
    public func sanitizeValues(for attributes: [String: Encodable]) -> [String: Encodable] {
        return Dictionary(uniqueKeysWithValues: attributes.map { key, value in
            guard let string = value.dd.decode(String.self),
                  string.utf16.count > Constraints.maxAttributeValueLength else {
                return (key, value)
            }
            DD.logger.warn(
                """
                \(featureName) attribute '\(key)' value was truncated from \(string.utf16.count) to \
                \(Constraints.maxAttributeValueLength) UTF-16 code units to match Datadog constraints.
                """
            )
            var utf16Count = 0
            let truncated = string.prefix(while: { char in
                let newCount = utf16Count + char.utf16.count
                guard newCount <= Constraints.maxAttributeValueLength else {
                    return false
                }
                utf16Count = newCount
                return true
            })
            return (key, String(truncated))
        })
    }

    // MARK: - Attributes count limitting

    /// Removes attributes exceeding the `count` limit.
    public func limitNumberOf<Value>(attributes: [String: Value], to count: Int) -> [String: Value] {
        if attributes.count > count {
            let extraAttributesCount = attributes.count - count
            DD.logger.warn(
                """
                Number of \(featureName) attributes exceeds the limit of \(Constraints.maxNumberOfAttributes).
                \(extraAttributesCount) attribute(s) will be ignored.
                """
            )
            return Dictionary(uniqueKeysWithValues: attributes.dropLast(extraAttributesCount))
        } else {
            return attributes
        }
    }
}
