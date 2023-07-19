/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Sanitizes `Log` representation received from the user, so it can match Datadog log constraints.
internal struct LogEventSanitizer {
    struct Constraints {
        /// Attribute names reserved for Datadog.
        /// If any of those is used by the user, the attribute will be ignored.
        static let reservedAttributeNames: Set<String> = [
            "host", "message", "status", "service", "source", "ddtags",
            "dd.trace_id", "dd.span_id", "application.id", "session.id",
            "application_id", "session_id", "view.id", "user_action.id",
        ]
        /// Allowed first character of a tag name (given as ASCII values ranging from lowercased `a` to `z`) .
        /// Tags with name starting with different character will be dropped.
        static let allowedTagNameFirstCharacterASCIIRange: [UInt8] = Array(97...122)
        /// Maximum length of the tag.
        /// Tags exceeting this length will be trunkated.
        static let maxTagLength: Int = 200
        /// Tag keys reserved for Datadog.
        /// If any of those is used by user, the tag will be ignored.
        static let reservedTagKeys: Set<String> = [
            "host", "device", "source", "service", "env"
        ]
        /// Maximum number of attributes in log.
        /// If this number is exceeded, extra attributes will be ignored.
        static let maxNumberOfTags: Int = 100
    }

    private let attributesSanitizer = AttributesSanitizer(featureName: "Log")

    func sanitize(log: LogEvent) -> LogEvent {
        let sanitizedAttributes = sanitize(attributes: log.attributes)
        let sanitizedTags = sanitize(tags: log.tags)

        var sanitizedLog = log
        sanitizedLog.attributes = sanitizedAttributes
        sanitizedLog.tags = sanitizedTags
        return sanitizedLog
    }

    // MARK: - Attributes sanitization

    private func sanitize(attributes rawAttributes: LogEvent.Attributes) -> LogEvent.Attributes {
        // Sanitizes only `userAttributes`, `internalAttributes` remain untouched
        var userAttributes = rawAttributes.userAttributes
        userAttributes = removeInvalidAttributes(userAttributes)
        userAttributes = removeReservedAttributes(userAttributes)
        userAttributes = attributesSanitizer.sanitizeKeys(for: userAttributes)
        let userAttributesLimit = AttributesSanitizer.Constraints.maxNumberOfAttributes - (rawAttributes.internalAttributes?.count ?? 0)
        userAttributes = attributesSanitizer.limitNumberOf(attributes: userAttributes, to: userAttributesLimit)

        return LogEvent.Attributes(
            userAttributes: userAttributes,
            internalAttributes: rawAttributes.internalAttributes
        )
    }

    private func removeInvalidAttributes(_ attributes: [String: Encodable]) -> [String: Encodable] {
        // Attribute name cannot be empty
        return attributes.filter { attribute in
            if attribute.key.isEmpty {
                DD.logger.error("Attribute key is empty. This attribute will be ignored.")
                return false
            }
            return true
        }
    }

    private func removeReservedAttributes(_ attributes: [String: Encodable]) -> [String: Encodable] {
        return attributes.filter { attribute in
            if Constraints.reservedAttributeNames.contains(attribute.key) {
                DD.logger.error("'\(attribute.key)' is a reserved attribute name. This attribute will be ignored.")
                return false
            }
            return true
        }
    }

    // MARK: - Tags sanitization

    private func sanitize(tags rawTags: [String]?) -> [String]? {
        if let rawTags = rawTags {
            let tags = rawTags
                .map { $0.lowercased() }
                .filter { startsWithAllowedCharacter(tag: $0) }
                .map { replaceIllegalCharactersIn(tag: $0) }
                .map { removeTrailingCommasIn(tag: $0) }
                .map { limitToMaxLength(tag: $0) }
                .filter { isNotReserved(tag: $0) }
            return limitToMaxNumberOfTags(tags)
        } else {
            return nil
        }
    }

    private func startsWithAllowedCharacter(tag: String) -> Bool {
        guard let firstCharacter = tag.first?.asciiValue else {
            DD.logger.error("Tag is empty and will be ignored.")
            return false
        }

        // Tag must start with a letter
        if Constraints.allowedTagNameFirstCharacterASCIIRange.contains(firstCharacter) {
            return true
        } else {
            DD.logger.error("Tag '\(tag)' starts with an invalid character and will be ignored.")
            return false
        }
    }

    private func replaceIllegalCharactersIn(tag: String) -> String {
        let sanitized = tag.replacingOccurrences(of: #"[^a-z0-9_:.\/-]"#, with: "_", options: .regularExpression)
        if sanitized != tag {
            DD.logger.warn("Tag '\(tag)' was modified to '\(sanitized)' to match Datadog constraints.")
        }
        return sanitized
    }

    private func removeTrailingCommasIn(tag: String) -> String {
        // If present, remove trailing commas `:`
        var sanitized = tag
        while sanitized.last == ":" { _ = sanitized.removeLast() }
        if sanitized != tag {
            DD.logger.warn("Tag '\(tag)' was modified to '\(sanitized)' to match Datadog constraints.")
        }
        return sanitized
    }

    private func limitToMaxLength(tag: String) -> String {
        if tag.count > Constraints.maxTagLength {
            let sanitized = String(tag.prefix(Constraints.maxTagLength))
            DD.logger.warn("Tag '\(tag)' was modified to '\(sanitized)' to match Datadog constraints.")
            return sanitized
        } else {
            return tag
        }
    }

    private func isNotReserved(tag: String) -> Bool {
        if let colonIndex = tag.firstIndex(of: ":") {
            let key = String(tag.prefix(upTo: colonIndex))
            if Constraints.reservedTagKeys.contains(key) {
                DD.logger.warn("'\(key)' is a reserved tag key. This tag will be ignored.")
                return false
            } else {
                return true
            }
        } else {
            return true
        }
    }

    private func limitToMaxNumberOfTags(_ tags: [String]) -> [String] {
        // Only `Constraints.maxNumberOfTags` of tags are allowed.
        if tags.count > Constraints.maxNumberOfTags {
            let extraTagsCount = tags.count - Constraints.maxNumberOfTags
            DD.logger.warn("Number of tags exceeds the limit of \(Constraints.maxNumberOfTags). \(extraTagsCount) attribute(s) will be ignored.")
            return tags.dropLast(extraTagsCount)
        } else {
            return tags
        }
    }
}
