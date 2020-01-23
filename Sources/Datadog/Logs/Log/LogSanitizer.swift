import Foundation

/// Sanitizes `Log` representation received from the user, so it can match Datadog log constraints.
internal struct LogSanitizer {
    struct Constraints {
        /// Attribute names reserved for Datadog.
        /// If any of those is used by user, the attribute will be ignored.
        static let reservedAttributeNames: Set<String> = [
            "host", "message", "status", "service", "source", "date", "error.kind", "error.message", "error.stack", "ddtags"
        ]
        /// Maximum number of nested levels in attribute name. E.g. `person.address.street` has 3 levels.
        /// If attribute name exceeds this number, extra levels are escaped by using `_` character (`one.two.(...).nine.ten_eleven_twelve`).
        static let maxNestedLevelsInAttributeName: Int = 9
        /// Maximum number of attributes in log.
        /// If this number is exceeded, extra attributes will be ignored.
        static let maxNumberOfAttributes: Int = 256
    }

    func sanitize(log: Log) -> Log {
        return Log(
            date: log.date,
            status: log.status,
            message: log.message,
            service: log.service,
            attributes: sanitize(attributes: log.attributes)
        )
    }

    // MARK: - Attributes sanitization

    private func sanitize(attributes rawAttributes: [String: EncodableValue]?) -> [String: EncodableValue]? {
        if let rawAttributes = rawAttributes {
            var attributes = removeInvalidAttributes(rawAttributes)
            attributes = removeReservedAttributes(attributes)
            attributes = sanitizeAttributeNames(attributes)
            attributes = limitToMaxNumberOfAttributes(attributes)
            return attributes
        } else {
            return nil
        }
    }

    private func removeInvalidAttributes(_ attributes: [String: EncodableValue]) -> [String: EncodableValue] {
        return attributes.filter { attribute in
            if attribute.key.isEmpty {
                userLogger.error("Attribute key is empty. This attribute will be ignored.")
                return false
            }
            return true
        }
    }

    private func removeReservedAttributes(_ attributes: [String: EncodableValue]) -> [String: EncodableValue] {
        return attributes.filter { attribute in
            if Constraints.reservedAttributeNames.contains(attribute.key) {
                userLogger.error("'\(attribute.key)' is a reserved attribute name. This attribute will be ignored.")
                return false
            }
            return true
        }
    }

    private func sanitizeAttributeNames(_ attributes: [String: EncodableValue]) -> [String: EncodableValue] {
        let sanitizedAttributes: [(String, EncodableValue)] = attributes.map { name, value in
            let sanitizedName = sanitize(attributeName: name)
            if sanitizedName != name {
                userLogger.error("'\(name)' attribute was modified to '\(sanitizedName)' to match Datadog constraints.")
                return (sanitizedName, value)
            } else {
                return (name, value)
            }
        }
        return Dictionary(uniqueKeysWithValues: sanitizedAttributes)
    }

    private func sanitize(attributeName: String) -> String {
        // Attribute name can have only `Constants.maxNestedLevelsInAttributeName` levels. Escape extra levels with "_".
        var dotsCount = 0
        var sanitized = ""
        for char in attributeName {
            if char == "." {
                dotsCount += 1
                sanitized.append(dotsCount > Constraints.maxNestedLevelsInAttributeName ? "_" : char)
            } else {
                sanitized.append(char)
            }
        }
        return sanitized
    }

    private func limitToMaxNumberOfAttributes(_ attributes: [String: EncodableValue]) -> [String: EncodableValue] {
        // limit to `Constants.maxNumberOfAttributes` attributes.
        if attributes.count > Constraints.maxNumberOfAttributes {
            let extraAttributesCount = attributes.count - Constraints.maxNumberOfAttributes
            userLogger.error("Number of attributes exceeds the limit of \(Constraints.maxNumberOfAttributes). \(extraAttributesCount) attribute(s) will be ignored.")
            return Dictionary(uniqueKeysWithValues: attributes.dropLast(extraAttributesCount))
        } else {
            return attributes
        }
    }
}
