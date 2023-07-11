/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A `FeatureBaggage` holds keyed values and adds semantics for type-safe access.
///
/// Values are uniquely identified by key as `String`, the value type is validated on `get`
/// either explicity, when specified, or inferred.
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
/// Values are accessible using `subscript` methods with support for dynamic member
/// lookup.
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
/// A Feature Baggage does not ensure thread-safety of values that holds references, make
/// sure that any value can be accessibe from any thread.
@dynamicMemberLookup
public struct FeatureBaggage {
    /// The attributes dictionary.
    public private(set) var attributes: [String: Any]

    /// A Boolean value indicating whether the baggage is empty.
    public var isEmpty: Bool {
        attributes.isEmpty
    }

    /// Creates an instance initialized with the given key-value pairs.
    public init(_ attributes: [String: Any]) {
        let encoder = AnyEncoder()
        self.attributes = attributes
            .compactMapValues {
                if $0 is Encodable {
                    return try? encoder.encode(AnyEncodable($0))
                }

                return $0
            }
    }

    /// Returns the value stored in the baggage for the given key.
    ///
    /// - Parameters:
    ///   - key: The key to find in the dictionary.
    ///   - type: The expected value type.
    /// - Returns: The value associated with `key` if `key` is in the attributes.
    ///   `nil` otherwise.
    public func value<T>(forKey key: String, type: T.Type = T.self) -> T? {
        attributes[key] as? T
    }

    /// Decodes the value stored in the baggage for the given key.
    ///
    /// - Parameters:
    ///   - key: The key to find in the dictionary.
    ///   - type: The expected value type.
    /// - Returns: The value associated with `key` if `key` is in the attributes.
    ///   `nil` otherwise.
    public func decodeValue<T>(forKey key: String, type: T.Type = T.self) throws -> T? where T: Decodable {
        let decoder = AnyDecoder()
        return try decoder.decode(from: attributes[key])
    }

    /// Updates the value stored in the baggage for the given key, or adds a
    /// new key-value pair if the key does not exist.
    ///
    /// Use this method instead of key-based subscribing when you need to know
    /// whether the baggage was successfully updated.
    ///
    ///     var baggage = ["Heliotrope": 296, "Coral": 16, "Aquamarine": 156]
    ///     baggage.updateValue(18, forKey: "Coral")
    ///
    /// If the given key is not present in the dictionary, this method adds the
    /// key-value pair.
    ///
    /// - Parameters:
    ///   - value: The new value to add to the dictionary.
    ///   - key: The key to associate with `value`. If `key` already exists in
    ///     the dictionary, `value` replaces the existing associated value. If
    ///     `key` isn't already a key of the dictionary, the `(key, value)` pair
    ///     is added.
    public mutating func updateValue(_ value: Any?, forKey key: String) {
        attributes[key] = value
    }

    /// Encodes and updates the value stored in the baggage for the given key, or adds a
    /// new key-value pair if the key does not exist.
    ///
    /// Use this method instead of key-based subscribing when you need to know
    /// whether the baggage was successfully updated. If the update fails, an error
    /// will be thrown.
    ///
    ///     var baggage = ["Heliotrope": 296, "Coral": 16, "Aquamarine": 156]
    ///     do {
    ///         baggage.updateValue(18, forKey: "Coral")
    ///     } catch {
    ///         print(error)
    ///     }
    ///
    /// If the given key is not present in the dictionary, this method adds the
    /// key-value pair.
    ///
    /// - Parameters:
    ///   - value: The new encodable value to add to the dictionary.
    ///   - key: The key to associate with `value`. If `key` already exists in
    ///     the dictionary, `value` replaces the existing associated value. If
    ///     `key` isn't already a key of the dictionary, the `(key, value)` pair
    ///     is added.
    public mutating func encodeValue<T>(_ value: T, forKey key: String) throws where T: Encodable {
        let encoder = AnyEncoder()
        attributes[key] = try encoder.encode(value)
    }

    /// Returns a  dictionary containing only the key-value pairs that have
    /// non-`nil` values as the result of transformation by the given closure.
    ///
    /// Use this method to receive a attributes with non-optional values when
    /// your transformation produces optional values.
    ///
    /// - Parameter transform: A closure that transforms a value. `transform`
    ///   accepts each value of the dictionary as its parameter and returns an
    ///   optional transformed value of the same or of a different type.
    /// - Returns: A dictionary containing the keys and non-`nil` transformed
    ///   values of this dictionary.
    public func compactMapValues<T>(_ transform: (Any) throws -> T?) rethrows -> [String: T] {
        try attributes.compactMapValues(transform)
    }

    /// Accesses the value associated with the given key for reading an attribute.
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
    /// - Parameters:
    ///   - key: The key to find in the dictionary.
    ///   - type: The expected value type.
    /// - Returns: The value associated with `key` if `key` is in the attributes.
    ///   `nil` otherwise.
    public subscript<T>(key: String, type t: T.Type = T.self) -> T? where T: Decodable {
        try? decodeValue(forKey: key, type: t)
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
        get { value(forKey: key, type: t) }
        set { updateValue(newValue, forKey: key) }
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
    public subscript<T>(key: String, type t: T.Type = T.self) -> T? where T: Codable {
        get { try? decodeValue(forKey: key, type: t) }
        set { try? encodeValue(newValue, forKey: key) }
    }

    /// Accesses the value associated with the given key for reading an attribute type.
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
    /// - Parameter key: The key to find in the dictionary.
    /// - Returns: The value associated with `key` if `key` is in the attributes.
    ///   `nil` otherwise.
    public subscript<T>(dynamicMember key: String) -> T? where T: Decodable {
        try? decodeValue(forKey: key, type: T.self)
    }

    /// Accesses the value associated with the given key for reading and writing
    /// an attribute type.
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
        get { value(forKey: key, type: T.self) }
        set { updateValue(newValue, forKey: key) }
    }

    /// Accesses the value associated with the given key for reading and writing
    /// an attribute type.
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
    public subscript<T>(dynamicMember key: String) -> T? where T: Codable {
        get { try? decodeValue(forKey: key, type: T.self) }
        set { try? encodeValue(newValue, forKey: key) }
    }

    /// Merges with the values of another FeatureBaggage.
    ///
    /// - Parameter baggage: The FeatureBaggage to merge.
    public mutating func merge(with baggage: FeatureBaggage) {
        attributes.merge(baggage.attributes) { $1 }
    }
}

extension FeatureBaggage: ExpressibleByDictionaryLiteral {
    /// Creates an instance initialized with the given key-value pairs.
    public init(dictionaryLiteral elements: (String, Any?)...) {
        let encoder = AnyEncoder()
        self.attributes = elements.reduce(into: [:]) { attributes, element in
            attributes[element.0] = try? encoder.encode(AnyEncodable(element.1))
        }
    }
}
