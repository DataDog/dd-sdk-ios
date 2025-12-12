/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

// swiftlint:disable duplicate_imports
#if COCOAPODS
import KSCrash
#elseif swift(>=6.0)
internal import KSCrashRecording
#else
@_implementationOnly import KSCrashRecording
#endif
// swiftlint:enable duplicate_imports

internal typealias CrashFieldDictionary = [CrashField: Any]

/// Extension providing type-safe accessors for nested crash report dictionaries.
///
/// This extension offers multiple ways to access values in a crash report dictionary:
/// - Single-key subscripts with optional or default values
/// - Variadic subscripts for accessing nested values
/// - Throwable `value` functions for required fields
///
/// ## Example Usage
///
/// ```swift
/// // Optional access
/// let type: String? = dict[.crash, .error, .type]
///
/// // With default value
/// let type: String = dict[.crash, .error, .type, defaultValue: "Unknown"]
///
/// // Throwable access for required fields
/// let type: String = try dict.value(forKey: .crash, .error, .type)
/// ```
extension CrashFieldDictionary {
    // swiftlint:disable function_default_parameter_at_end

    /// Creates a typed `CrashDictionary` from an untyped string-keyed dictionary.
    ///
    /// This initializer recursively converts nested dictionaries and arrays of dictionaries
    /// from their untyped `[String: Any]` representation to the typed `CrashDictionary` format.
    ///
    /// - Parameter dict: The untyped crash report dictionary to convert
    init(from dict: [String: Any]) {
        self = dict.reduce(into: [:]) { result, field in
            let key = CrashField(rawValue: field.key)
            switch field.value {
            case let value as [String: Any]:
                result[key] = CrashFieldDictionary(from: value)
            case let value as [[String: Any]]:
                result[key] = value.map(CrashFieldDictionary.init(from:))
            default:
                result[key] = field.value
            }
        }
    }

    /// Retrieves an optional nested value using a key path, throwing only if type mismatch occurs.
    ///
    /// - Parameters:
    ///   - type: The expected type of the final value
    ///   - first: The first key to access
    ///   - rest: The remaining keys to traverse the nested dictionaries
    /// - Returns: The value at the nested path, or `nil` if any key in the path is missing
    /// - Throws: `CrashReportException` if the value exists but cannot be cast to the expected type
    ///
    /// Example:
    /// ```swift
    /// let type: String? = try dict.valueIfPresent(forKey: .crash, .error, .type)
    /// // Returns nil if crash.error.type is missing
    /// // Throws if crash.error.type exists but is not a String
    /// ```
    func valueIfPresent<T>(_ type: T.Type = T.self, forKey first: Key, _ rest: Key...) throws -> T? {
        let path = [first] + rest
        guard let rawValue = value(atPath: path) else {
            return nil
        }

        guard let result = rawValue as? T else {
            let keyPath = path.map(\.rawValue).joined(separator: ".")
            throw CrashReportException(description: "KSCrash report field has invalid type: \(keyPath)")
        }

        return result
    }

    /// Retrieves a required nested value using a key path, throwing if not found.
    ///
    /// - Parameters:
    ///   - type: The expected type of the final value
    ///   - first: The first key to access
    ///   - rest: The remaining keys to traverse the nested dictionaries
    /// - Returns: The value at the nested path
    /// - Throws: `CrashReportException` if any key in the path is missing or type mismatch occurs
    ///
    /// Example:
    /// ```swift
    /// let type: String = try dict.value(forKey: .crash, .error, .type)
    /// // Throws if crash.error.type is missing or not a String
    /// ```
    func value<T>(_ type: T.Type = T.self, forKey first: Key, _ rest: Key...) throws -> T {
        let path = [first] + rest
        guard let value = value(atPath: path) as? T else {
            let keyPath = path.map(\.rawValue).joined(separator: ".")
            throw CrashReportException(description: "KSCrash report missing or invalid field: \(keyPath)")
        }

        return value
    }

    /// Sets a value at a nested key path, creating intermediate dictionaries as needed.
    ///
    /// This method allows setting values deep in the dictionary hierarchy using a variadic
    /// key path. If intermediate dictionaries don't exist, they are created automatically.
    /// The value is provided as an autoclosure, which is only evaluated if needed.
    ///
    /// - Parameters:
    ///   - first: The first key in the path
    ///   - rest: The remaining keys to traverse the nested dictionaries
    ///   - value: An autoclosure that provides the value to set
    ///
    /// Example:
    /// ```swift
    /// var dict: CrashDictionary = [:]
    /// dict.setValue(forKey: .crash, .error, .type, value: "SIGSEGV")
    /// // Creates: [.crash: [.error: [.type: "SIGSEGV"]]]
    /// ```
    mutating func setValue(forKey first: Key, _ rest: Key..., value: @autoclosure () -> Any) {
        let path = [first] + rest
        setValue(atPath: path, value: value())
    }

    /// Helper function to recursively set a value at a nested key path.
    ///
    /// This function navigates through the dictionary structure, creating intermediate
    /// dictionaries as needed, and sets the value at the final key.
    ///
    /// - Parameters:
    ///   - path: The array of keys representing the path to the target location
    ///   - value: The value to set at the path
    private mutating func setValue(atPath path: [Key], value: Any) {
        guard let first = path.first else {
            return
        }

        if path.count == 1 {
            // Base case: set the value at the final key
            self[first] = value
        } else {
            // Recursive case: create or update nested dictionary
            let rest = Array(path.dropFirst())
            var nestedDict = self[first] as? CrashFieldDictionary ?? [:]
            nestedDict.setValue(atPath: rest, value: value)
            self[first] = nestedDict
        }
    }

    /// Retrieves a value at a nested key path by traversing the dictionary structure.
    ///
    /// This helper function navigates through nested dictionaries following the provided
    /// key path. If any key in the path is missing or the structure is not a dictionary
    /// at any intermediate level, it returns nil.
    ///
    /// - Parameter path: The array of keys representing the path to traverse
    /// - Returns: The value at the specified path, or nil if the path is invalid
    private func value(atPath path: [Key]) -> Any? {
        var current: Any? = self

        for key in path {
            guard let dict = current as? CrashFieldDictionary else {
                return nil
            }
            current = dict[key]
        }

        return current
    }

    // swiftlint:enable function_default_parameter_at_end
}

/// Extension providing custom `CrashField` keys used by Datadog crash reporting.
extension CrashField {
    /// Creates a custom crash field with the specified string key.
    ///
    /// - Parameter key: The string key for the field
    /// - Returns: A new `CrashField` with the given key
    static func key(_ key: String) -> Self { .init(rawValue: key) }

    /// The parent process name field.
    static var parentProcessName: Self { .key("parent_process_name") }

    /// Flag indicating whether a backtrace has been truncated.
    static var truncated: Self { .key("truncated") }
}
