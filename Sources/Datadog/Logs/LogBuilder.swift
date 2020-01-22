import Foundation

/// Builds `Log` objects.
internal struct LogBuilder {
    struct Constants {
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

    /// Service name to write in log.
    let serviceName: String
    /// Current date to write in log.
    let dateProvider: DateProvider

    func createLogWith(level: LogLevel, message: String, attributes: [String: EncodableValue]) -> Log {
        var validatedAttributes = attributes
        validatedAttributes = removeReservedAttributes(attributes)
        validatedAttributes = sanitizeAttributeNames(validatedAttributes)
        validatedAttributes = limitToMaxNumberOfAttributes(validatedAttributes)

        return Log(
            date: dateProvider.currentDate(),
            status: logStatus(for: level),
            message: message,
            service: serviceName,
            attributes: !validatedAttributes.isEmpty ? validatedAttributes : nil
        )
    }

    private func logStatus(for level: LogLevel) -> Log.Status {
        switch level {
        case .debug:    return .debug
        case .info:     return .info
        case .notice:   return .notice
        case .warn:     return .warn
        case .error:    return .error
        case .critical: return .critical
        }
    }

    // MARK: - Attributes validation

    private func removeReservedAttributes(_ attributes: [String: EncodableValue]) -> [String: EncodableValue] {
        return attributes.filter { attribute in
            if Constants.reservedAttributeNames.contains(attribute.key) {
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
                sanitized.append(dotsCount > Constants.maxNestedLevelsInAttributeName ? "_" : char)
            } else {
                sanitized.append(char)
            }
        }

        return sanitized
    }

    private func limitToMaxNumberOfAttributes(_ attributes: [String: EncodableValue]) -> [String: EncodableValue] {
        // limit to `Constants.maxNumberOfAttributes` attributes.
        if attributes.count > Constants.maxNumberOfAttributes {
            let extraAttributesCount = attributes.count - Constants.maxNumberOfAttributes
            return Dictionary(uniqueKeysWithValues: attributes.dropLast(extraAttributesCount))
        } else {
            return attributes
        }
    }
}
