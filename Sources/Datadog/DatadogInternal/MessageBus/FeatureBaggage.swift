/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A `FeatureBaggage` holds keyed values and adds semantics for type-safe access.
///
/// Values are uniquely identified by key as `String`, the value type is validated on `get` either explicity, when specified,
/// or inferred.
///
/// ## Defining a Feature Baggage
/// A baggage is expressible by dictionary literal with `Any?` value type.
///
///     var baggage: FeatureBaggage = [
///         "string": "value",
///         "integer": 1,
///         "null": nil
///     ]
///
/// ## Accessing Values
/// Values are accessible using `subscript` methods with support for dynamic member lookup.
///
///     let baggage: FeatureBaggage = [...]
///     // get by key and explicit value type
///     let string = baggage["string", type: String.self]
///     // get by key and inferred value type
///     let string: String? = baggage["string"]
///     // get dynamic member
///     let string: String? = baggage.string
///
/// A baggage can also be mutated:
///
///     var baggage: FeatureBaggage = [...]
///     baggage["string"] = "value"
///     // set dynamic member
///     baggage.string = "value"
///
/// A Feature Baggage does not ensure thread-safety of values that holds references, make sure that any value can be accessibe
/// from any thread.
@dynamicMemberLookup
public struct FeatureBaggage {
    /// The attributes dictionary.
    private var attributes: [String: Any]

    /// Creates an instance initialized with the given key-value pairs.
    public init(_ attributes: [String: Any?]) {
        self.attributes = attributes.compactMapValues { $0 }
    }

    /// Returns all attributes where the value is of type `T`.
    ///
    /// - Parameter type: The requested value type.
    /// - Returns: A dictionary of attribute where the value is of type `T`
    public func all<T>(of type: T.Type = T.self) -> [String: T] {
        attributes.compactMapValues { $0 as? T }
    }

    /// Accesses the value associated with the given key for reading and writing
    /// an attribute.
    ///
    /// This *key-based* subscript returns the value for the given key if the key
    /// with a value of type `T` is found in the attributes, or `nil` otherwise.
    ///
    /// The following example creates a new `FeatureMessageAttributes` and
    /// prints the value of a key found in the attributes object (`"coral"`).
    ///
    ///     var hues: FeatureMessageAttributes = [
    ///         "heliotrope": 296,
    ///         "coral": 16,
    ///         "aquamarine": 156
    ///     ]
    ///     print(hues["coral", type: Int.self])
    ///     // Prints "Optional(16)"
    ///     print(hues["coral", type: String.self])
    ///     // Prints "null"
    ///
    /// When you assign a value for a key and that key already exists, the
    /// attribute object overwrites the existing value. If the attribute object doesn't
    /// contain the key, the key and value are added as a new key-value pair.
    ///
    /// Here, the value for the key `"coral"` is updated from `16` to `18` and a
    /// new key-value pair is added for the key `"cerise"`.
    ///
    ///     hues["coral"] = 18
    ///     print(hues["coral", type: Int.self])
    ///     // Prints "Optional(18)"
    ///
    ///     hues["cerise"] = "ok"
    ///     print(hues["cerise", type: String.self])
    ///     // Prints "Optional("ok")"
    ///
    /// If you assign `nil` as the value for the given key, the attribute object
    /// removes that key and its associated value.
    ///
    /// - Parameters:
    ///   - key: The key to find in the dictionary.
    ///   - type: The expected value type.
    /// - Returns: The value associated with `key` if `key` is in the attributes.
    ///   `nil` otherwise.
    public subscript<T>(key: String, type t: T.Type = T.self) -> T? {
        get { attributes[key] as? T }
        set { attributes[key] = newValue }
    }

    /// Accesses `RawRepresentable` from its `RawValue` associated with the given key
    /// for reading an attribute.
    ///
    /// The attribute for the given key will be used as the `rawValue` for initializing the
    /// `RawRepresentable` type.
    ///
    /// - Parameters:
    ///   - key: The key to find in the dictionary.
    ///   - type: The expected value type.
    /// - Returns: The value associated with `key` if `rawValue` is in the attributes.
    ///   `nil` otherwise.
    public subscript<T>(key: String, type t: T.Type = T.self) -> T? where T: RawRepresentable {
        attributes[key]
            .flatMap { $0 as? T.RawValue }
            .flatMap { .init(rawValue: $0) }
        ?? attributes[key] as? T
    }

    /// Accesses the value associated with the given key for reading and writing
    /// a attribute type.
    ///
    /// This *dynamic-member-based* subscript returns the value for the given key if the key
    /// with a value of type `T` is found in the attributes, or `nil`otherwise.
    ///
    /// The following example creates a new `FeatureMessageAttributes` and
    /// prints the value of a key found in the attributes object (`"coral"`) and a key not
    /// found in the dictionary (`"cerise"`).
    ///
    ///     var hues: FeatureMessageAttributes = [
    ///         "heliotrope": 296,
    ///         "coral": 16,
    ///         "aquamarine": 156
    ///     ]
    ///     let coral: Int? = hues.coral
    ///     print(coral as? Int)
    ///     // Prints "16"
    ///     let cerise: Int? = hues.cerise
    ///     print(cerise)
    ///     // Prints "null"
    ///
    /// When you assign a value for a key and that key already exists, the
    /// attribute object overwrites the existing value. If the attribute object doesn't
    /// contain the key, the key and value are added as a new key-value pair.
    ///
    /// If you assign `nil` as the value for the given key, the attribute object
    /// removes that key and its associated value.
    ///
    /// In the following example, the key-value pair for the key `"aquamarine"`
    /// is removed from the attribute object by assigning `nil` to the
    /// dynamic-member-based subscript.
    ///
    ///     hues.aquamarine = nil
    ///     print(hues)
    ///     // Prints "["coral": 18, "heliotrope": 296, "cerise": 330]"
    ///
    /// - Parameter key: The key to find in the dictionary.
    /// - Returns: The value associated with `key` if `key` is in the attributes.
    ///   `nil` otherwise.
    public subscript<T>(dynamicMember key: String) -> T? {
        get { self[key, type: T.self] }
        set { self[key, type: T.self] = newValue }
    }

    /// Accesses `RawRepresentable` from its `RawValue` associated with the given key
    /// for reading an attribute.
    ///
    /// The attribute for the given key will be used as the `rawValue` for initializing the
    /// `RawRepresentable` type.
    ///
    /// - Parameter key: The key to find in the dictionary.
    /// - Returns: The value associated with `key` if `rawValue` is in the attributes.
    ///   `nil` otherwise.
    public subscript<T>(dynamicMember key: String) -> T? where T: RawRepresentable {
        get { self[key, type: T.self] }
        set { self[key, type: T.self] = newValue }
    }
}

extension FeatureBaggage: ExpressibleByDictionaryLiteral {
    /// Creates an instance initialized with the given key-value pairs.
    public init(dictionaryLiteral elements: (String, Any?)...) {
        self.attributes = elements.reduce(into: [:]) { attributes, element in
            attributes[element.0] = element.1
        }
    }
}
