import Foundation

/// Sanitizes `Log` representation received from the user, so it can match Datadog log constraints.
internal struct LogSanitizer {
    struct Constraints {
        /// Attribute names reserved for Datadog.
        /// If any of those is used by user, the attribute will be ignored.
        static let reservedAttributeNames: Set<String> = [
            "host", "message", "status", "service", "source", "error.kind", "error.message", "error.stack", "ddtags"
        ]
        /// Maximum number of nested levels in attribute name. E.g. `person.address.street` has 3 levels.
        /// If attribute name exceeds this number, extra levels are escaped by using `_` character (`one.two.(...).nine.ten_eleven_twelve`).
        static let maxNestedLevelsInAttributeName: Int = 9
        /// Maximum number of attributes in log.
        /// If this number is exceeded, extra attributes will be ignored.
        static let maxNumberOfAttributes: Int = 256
        /// Possible first characters of a valid tag name.
        /// Tags with names starting with different character will be dropped.
        static let allowedTagNameFirstCharacters: Set<Character> = [
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
            "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"
        ]
        /// Maximum lenght of the tag.
        /// Tags exceeting this lenght will be trunkated.
        static let maxTagLength: Int = 200
        /// Tag keys reserved for Datadog.
        /// If any of those is used by user, the tag will be ignored.
        static let reservedTagKeys: Set<String> = [
            "host", "device", "source", "service"
        ]
    }

    func sanitize(log: Log) -> Log {
        return Log(
            date: log.date,
            status: log.status,
            message: log.message,
            service: log.service,
            attributes: sanitize(attributes: log.attributes),
            tags: sanitize(tags: log.tags)
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
        // Attribute name cannot be empty
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
                userLogger.error("Attribute '\(name)' was modified to '\(sanitizedName)' to match Datadog constraints.")
                return (sanitizedName, value)
            } else {
                return (name, value)
            }
        }
        return Dictionary(uniqueKeysWithValues: sanitizedAttributes)
    }

    private func sanitize(attributeName: String) -> String {
        // Attribute name can only have `Constants.maxNestedLevelsInAttributeName` levels. Escape extra levels with "_".
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
        // Only `Constants.maxNumberOfAttributes` of attributes is allowed.
        if attributes.count > Constraints.maxNumberOfAttributes {
            let extraAttributesCount = attributes.count - Constraints.maxNumberOfAttributes
            userLogger.error("Number of attributes exceeds the limit of \(Constraints.maxNumberOfAttributes). \(extraAttributesCount) attribute(s) will be ignored.")
            return Dictionary(uniqueKeysWithValues: attributes.dropLast(extraAttributesCount))
        } else {
            return attributes
        }
    }

    // MARK: - Tags sanitization

    private func sanitize(tags rawTags: [String]?) -> [String]? {
        if let rawTags = rawTags {
            var tags = lowercaseTags(rawTags)
            tags = removeInvalidTags(tags)
            tags = replaceIllegalTagCharacters(tags)
            tags = removeTagTrailingCommas(tags)
            tags = limitToMaxTagLength(tags)
            tags = removeReservedTags(tags)
            return tags
        } else {
            return nil
        }
    }

    private func lowercaseTags(_ tags: [String]) -> [String] {
        return tags.map { $0.lowercased() }
    }

    private func removeInvalidTags(_ tags: [String]) -> [String] {
        return tags
            .filter { tag in
                // Tag must start with a letter
                let firstCharacter = tag.first ?? Character("")
                if Constraints.allowedTagNameFirstCharacters.contains(firstCharacter) {
                    return true
                } else {
                    userLogger.error("Tag '\(tag)' starts with an invalid character and will be ignored.")
                    return false
                }
            }
    }

    private func replaceIllegalTagCharacters(_ tags: [String]) -> [String] {
        // Convert illegal tag characters to underscode
        return tags.map { tag -> String in
            let sanitized = tag.replacingOccurrences(of: #"[^a-z0-9_:.\/-]"#, with: "_", options: .regularExpression)
            if sanitized != tag {
                userLogger.warn("Tag '\(tag)' was modified to '\(sanitized)' to match Datadog constraints.")
            }
            return sanitized
        }
    }

    private func removeTagTrailingCommas(_ tags: [String]) -> [String] {
        // If present, remove trailing commas `:`
        return tags.map { tag -> String in
            var sanitized = tag
            while sanitized.last == ":" { _ = sanitized.removeLast() }
            if sanitized != tag {
                userLogger.warn("Tag '\(tag)' was modified to '\(sanitized)' to match Datadog constraints.")
            }
            return sanitized
        }
    }

    private func limitToMaxTagLength(_ tags: [String]) -> [String] {
        return tags.map { tag -> String in
            if tag.count > Constraints.maxTagLength {
                let sanitized = String(tag.prefix(Constraints.maxTagLength))
                userLogger.warn("Tag '\(tag)' was modified to '\(sanitized)' to match Datadog constraints.")
                return sanitized
            } else {
                return tag
            }
        }
    }

    private func removeReservedTags(_ tags: [String]) -> [String] {
        return tags.filter { tag in
            if let colonIndex = tag.firstIndex(of: ":") {
                let key = String(tag.prefix(upTo: colonIndex))
                if Constraints.reservedTagKeys.contains(key) {
                    userLogger.error("'\(key)' is a reserved tag key. This tag will be ignored.")
                    return false
                } else {
                    return true
                }
            } else {
                return true
            }
        }
    }
}
