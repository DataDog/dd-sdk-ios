/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

/// Collection of utilities for creating values for facets configured in "Mobile - Integration" org.
struct DD {
    /// Collection of performance span names for measuring time performance of different APIs.
    ///
    /// There is a performance monitor defined for each span name from this collection.
    struct PerfSpanName {
        /// Builds the span name by extracting it from the caller method
        /// name (it removes `test_` prefix, `()` suffix and converts the name to lowercase).
        static func fromCurrentMethodName(functionName: StaticString = #function) -> String {
            return testMethodName(functionName: functionName)
        }

        // MARK: - Common

        static let sdkInitialize = "sdk_initialize"
        static let setTrackingConsent = "sdk_set_tracking_consent"

        // MARK: - Logging-specific

        static let loggerInitialize = "logs_logger_initialize"

        // MARK: - RUM-specific

        static let rumAttributeAddAttribute = "rum_globalrum_add_attribute"
        static let rumAttributeRemoveAttribute = "rum_globalrum_remove_attribute"
    }

    // MARK: - Special Attributes

    /// Special attribute added to events.
    ///
    /// There is a facet created for each produced **attribute key**.
    /// Some **attribute values** contain fixed part, which is additionally asserted in monitor.
    ///
    /// We only test `String`, `Int`, `Double` and `Bool` attributes as these are the only ones available for facets at Datadog.
    struct SpecialAttribute {
        let key: String
        let value: Encodable

        fileprivate init(key: String, value: Encodable) {
            self.key = key
            self.value = value
        }
    }

    static func specialStringAttribute() -> SpecialAttribute {
        let prefix = "customAttribute" // asserted in monitors (`@test_special_string_attribute:customAttribute*`)
        return .init(key: "test_special_string_attribute", value: prefix + .mockRandom())
    }

    static func specialIntAttribute() -> SpecialAttribute {
        let min: Int = 11 // asserted in monitors (`@test_special_int_attribute:>10`)
        return .init(key: "test_special_int_attribute", value: Int.mockRandom(min: min, max: .max))
    }

    static func specialDoubleAttribute() -> SpecialAttribute {
        let min: Double = 11.0 // asserted in monitors (`@test_special_double_attribute:>10.0`)
        return .init(key: "test_special_double_attribute", value: Double.mockRandom(min: min, max: .greatestFiniteMagnitude))
    }

    static func specialBoolAttribute() -> SpecialAttribute {
        let value: Bool = .random() // asserted in monitors (`@test_special_bool_attribute:(true OR false)`)
        return .init(key: "test_special_bool_attribute", value: value)
    }

    // MARK: - Special Tags

    /// Special tag added to events.
    ///
    /// There is a facet created for each produced **tag name**.
    /// **Tag values** contain fixed part, which is additionally asserted in monitor.
    struct SpecialTag {
        let key: String
        let value: String

        fileprivate init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    static func specialTag() -> SpecialTag {
        let prefix = "customtag" // asserted in monitors (`@test_special_tag:customtag*`)
        return .init(key: "test_special_tag", value: prefix + .mockRandom())
    }

    // MARK: - Logging-specific Attributes

    /// Attributes added to each log event.
    ///
    /// Each attributes has a facet used in monitor to assert that events are actually delivered.
    static func logAttributes(functionName: StaticString = #function) -> [AttributeKey: AttributeValue] {
        return [
            "test_method_name": testMethodName(functionName: functionName)
        ]
    }
}

/// Removes `test_` prefix, `()` suffix and converts the `functionName` to lowercase.
///
/// e.g. if called with `test_logs_logger_debug_log()`, it will return `logs_logger_debug_log`.
private func testMethodName(functionName: StaticString = #function) -> String {
    var name = "\(functionName)"
    precondition(name.hasPrefix("test_"), "Cannot read `testMethodName` from: \(name) - it must have 'test_' prefix.")
    precondition(name.hasSuffix("()"), "Cannot read `testMethodName` from: \(name) - it must have '()' suffix.")
    name.removeFirst(("test_".count))
    name.removeLast("()".count)
    return name.lowercased()
}
