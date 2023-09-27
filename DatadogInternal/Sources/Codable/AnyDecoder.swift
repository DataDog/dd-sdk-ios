/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An object that decodes instances of a `Any` type.
///
/// The example below shows how to decode an instance of a simple `GroceryProduct`
/// type from a `Any` object. The type adopts `Codable` so that it's decodable using a
/// `AnyDecoder` instance.
///
///     struct GroceryProduct: Codable {
///         var name: String
///         var points: Int
///         var description: String?
///     }
///
///     let dictionary: [String: Any] = [
///         "name": "Durian",
///         "points": 600,
///         "description": "A fruit with a distinctive scent."
///     ]
///
///     let decoder = AnyDecoder()
///     let product = try decoder.decode(GroceryProduct.self, from: dictionary)
///
///     print(product.name) // Prints "Durian"
///
open class AnyDecoder {
    /// Initializes `self`.
    public init() { }

    /// Decodes a top-level any value to the given type.
    ///
    /// - parameter type: The type of the value to decode.
    /// - parameter object: The object to decode from.
    /// - returns: A value of the requested type.
    /// - throws: `DecodingError.dataCorrupted` if values requested from the payload are corrupted, or if the given data is not valid JSON.
    /// - throws: An error if any value throws an error during decoding.
    open func decode<T>(_ type: T.Type = T.self, from any: Any?) throws -> T where T: Decodable {
        // swiftlint:disable:previous function_default_parameter_at_end
        let container = _AnyDecoder.SingleValueContainer(any)
        return try container.decode(T.self)
    }
}

// swiftlint:enable closing_brace_whitespace
// MARK: - Internal Decoder
private class _AnyDecoder: Decoder {
    /// The path of coding keys taken to get to this point in decoding.
    let codingPath: [CodingKey]

    /// The source value.
    let value: Any?

    /// Any contextual information set by the user for decoding.
    let userInfo: [CodingUserInfoKey: Any] = [:]

    init(_ value: Any?, path: [CodingKey] = []) {
        self.value = value
        codingPath = path
    }

    /// Returns the data stored in this decoder as represented in a container
    /// keyed by the given key type.
    ///
    /// - parameter type: The key type to use for the container.
    /// - returns: A keyed decoding container view into this decoder.
    /// - throws: `DecodingError.typeMismatch` if the encountered stored value is
    ///   not a keyed container.
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        let container = try KeyedContainer<Key>(value, path: codingPath)
        return KeyedDecodingContainer(container)
    }

    /// Returns the data stored in this decoder as represented in a container
    /// appropriate for holding values with no keys.
    ///
    /// - returns: An unkeyed container view into this decoder.
    /// - throws: `DecodingError.typeMismatch` if the encountered stored value is
    ///   not an unkeyed container.
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        try UnkeyedContainer(value, path: codingPath)
    }

    /// Returns the data stored in this decoder as represented in a container
    /// appropriate for holding a single primitive value.
    ///
    /// - returns: A single value container view into this decoder.
    /// - throws: `DecodingError.typeMismatch` if the encountered stored value is
    ///   not a single value container.
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        SingleValueContainer(value, path: codingPath)
    }

    /// A type that provides a view into an encoder's storage and is used to hold
    /// the encoded properties of an encodable type in a keyed manner.
    struct KeyedContainer<Key>: KeyedDecodingContainerProtocol where Key: CodingKey {
        /// The path of coding keys taken to get to this point in encoding.
        let codingPath: [CodingKey]

        /// The source dictionary.
        let dict: [String: Any?]

        init(_ any: Any?, path: [CodingKey] = []) throws {
            guard let dict = any as? [String: Any?] else {
                let context = DecodingError.Context(
                    codingPath: path,
                    debugDescription: "Invalid conversion of '\(String(describing: any))' to Dictionary."
                )

                throw DecodingError.typeMismatch([String: Any?].self, context)
            }

            self.dict = dict
            self.codingPath = path
        }

        /// All the keys the `Decoder` has for this container.
        ///
        /// Different keyed containers from the same `Decoder` may return different
        /// keys here; it is possible to encode with multiple key types which are
        /// not convertible to one another. This should report all keys present
        /// which are convertible to the requested type.
        var allKeys: [Key] {
            dict.keys.compactMap { Key(stringValue: $0) }
        }

        /// Returns a Boolean value indicating whether the decoder contains a value
        /// associated with the given key.
        ///
        /// The value associated with `key` may be a null value as appropriate for
        /// the data format.
        ///
        /// - parameter key: The key to search for.
        /// - returns: Whether the `Decoder` has an entry for the given key.
        func contains(_ key: Key) -> Bool {
            dict[key.stringValue] != nil
        }

        func value(forKey key: Key) throws -> Any? {
            if let value = dict[key.stringValue] {
                return value
            }

            let context = DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "No value associated with key \(key.stringValue)."
            )

            throw DecodingError.keyNotFound(key, context)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decodeNil(forKey key: Key) throws -> Bool {
            try nestedSingleValueContainer(forKey: key).decodeNil()
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: String.Type, forKey key: Key) throws -> String {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Decodes a value of the given type for the given key.
        ///
        /// - parameter type: The type of value to decode.
        /// - parameter key: The key that the decoded value is associated with.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
            try nestedSingleValueContainer(forKey: key).decode(type)
        }

        /// Returns the data stored for the given key as represented in a container
        /// keyed by the given key type.
        ///
        /// - parameter type: The key type to use for the container.
        /// - parameter key: The key that the nested container is associated with.
        /// - returns: A keyed decoding container view into `self`.
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
            let container = try KeyedContainer<NestedKey>(value(forKey: key), path: codingPath + [key])
            return KeyedDecodingContainer(container)
        }

        /// Returns the data stored for the given key as represented in an unkeyed
        /// container.
        ///
        /// - parameter key: The key that the nested container is associated with.
        /// - returns: An unkeyed decoding container view into `self`.
        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            try UnkeyedContainer(value(forKey: key), path: codingPath + [key])
        }

        /// Returns the data stored for the given key as represented in an single value
        /// container.
        ///
        /// - parameter key: The key that the nested container is associated with.
        /// - returns: An single value decoding container view into `self`.
        func nestedSingleValueContainer(forKey key: Key) throws -> SingleValueDecodingContainer {
            try SingleValueContainer(value(forKey: key), path: codingPath + [key])
        }

        /// Returns a `Decoder` instance for decoding `super` from the container
        /// associated with the default `super` key.
        ///
        /// Equivalent to calling `superDecoder(forKey:)` with
        /// `Key(stringValue: "super", intValue: 0)`.
        ///
        /// - returns: A new `Decoder` to pass to `super.init(from:)`.
        func superDecoder() throws -> Decoder {
            _AnyDecoder(dict, path: codingPath)
        }

        /// Returns a `Decoder` instance for decoding `super` from the container
        /// associated with the given key.
        ///
        /// - parameter key: The key to decode `super` for.
        /// - returns: A new `Decoder` to pass to `super.init(from:)`.
        func superDecoder(forKey key: Key) throws -> Decoder {
            try _AnyDecoder(value(forKey: key), path: codingPath + [key])
        }
    }

    /// A type that provides a view into a decoder's storage and is used to hold
    /// the encoded properties of a decodable type sequentially, without keys.
    struct UnkeyedContainer: UnkeyedDecodingContainer {
        /// The path of coding keys taken to get to this point in decoding.
        let codingPath: [CodingKey]

        /// The number of elements contained within this container.
        ///
        /// If the number of elements is unknown, the value is `nil`.
        var count: Int? { array.count }

        /// A Boolean value indicating whether there are no more elements left to be
        /// decoded in the container.
        var isAtEnd: Bool { currentIndex >= array.count }

        /// The current decoding index of the container (i.e. the index of the next
        /// element to be decoded.) Incremented after every successful decode call.
        private(set) var currentIndex: Int = 0

        /// The source array.
        private let array: [Any?]

        init(_ any: Any?, path: [CodingKey] = []) throws {
            guard let array = any as? [Any?] else {
                let context = DecodingError.Context(
                    codingPath: path,
                    debugDescription: "Invalid conversion of '\(String(describing: any))' to Array."
                )

                throw DecodingError.typeMismatch([Any?].self, context)
            }

            self.array = array
            self.codingPath = path
        }

        /// Decodes a null value.
        ///
        /// If the value is not null, does not increment currentIndex.
        ///
        /// - returns: Whether the encountered value was null.
        mutating func decodeNil() throws -> Bool {
            if try nestedSingleValueContainer().decodeNil() {
                return true
            }

            currentIndex -= 1
            return false
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: Bool.Type) throws -> Bool {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: String.Type) throws -> String {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: Double.Type) throws -> Double {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: Float.Type) throws -> Float {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: Int.Type) throws -> Int {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: Int8.Type) throws -> Int8 {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: Int16.Type) throws -> Int16 {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: Int32.Type) throws -> Int32 {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: Int64.Type) throws -> Int64 {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: UInt.Type) throws -> UInt {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
            try nestedSingleValueContainer().decode(type)
        }

        /// Decodes a value of the given type.
        ///
        /// - parameter type: The type of value to decode.
        /// - returns: A value of the requested type, if present for the given key
        ///   and convertible to the requested type.
        mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
            try nestedSingleValueContainer().decode(type)
        }

        private mutating func next() throws -> Any? {
            defer { currentIndex += 1 }

            if isAtEnd {
                let context = DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Unkeyed container is at end."
                )

                throw DecodingError.valueNotFound(Any.self, context)
            }

            return array[currentIndex]
        }

        /// Decodes a nested container keyed by the given type.
        ///
        /// - parameter type: The key type to use for the container.
        /// - returns: A keyed decoding container view into `self`.
        mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
            let container = try KeyedContainer<NestedKey>(next(), path: codingPath)
            return KeyedDecodingContainer(container)
        }

        /// Decodes an unkeyed nested container.
        ///
        /// - returns: An unkeyed decoding container view into `self`.
        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            try UnkeyedContainer(next(), path: codingPath)
        }

        /// Decodes an single value nested container.
        ///
        /// - returns: An unkeyed decoding container view into `self`.
        mutating func nestedSingleValueContainer() throws -> SingleValueDecodingContainer {
            try SingleValueContainer(next(), path: codingPath)
        }

        /// Decodes a nested container and returns a `Decoder` instance for decoding
        /// `super` from that container.
        ///
        /// - returns: A new `Decoder` to pass to `super.init(from:)`.
        mutating func superDecoder() throws -> Decoder {
            _AnyDecoder(array, path: codingPath)
        }
    }

    /// A container that can support the storage and direct decoding of a single
    /// nonkeyed value.
    struct SingleValueContainer: SingleValueDecodingContainer, PassthroughValueDecodingContainer {
        /// The path of coding keys taken to get to this point in encoding.
        let codingPath: [CodingKey]

        let value: Any?

        init(_ value: Any?, path: [CodingKey] = []) {
            self.value = value
            self.codingPath = path
        }

        /// Decodes a null value.
        ///
        /// - returns: Whether the encountered value was null.
        func decodeNil() -> Bool {
            value == nil
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: Bool.Type) throws -> Bool {
            guard let value = value as? Bool else {
                throw DecodingError.typeMismatch(type, in: self)
            }
            return value
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: String.Type) throws -> String {
            guard let value = value as? String else {
                throw DecodingError.typeMismatch(type, in: self)
            }
            return value
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: Double.Type) throws -> Double {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: Float.Type) throws -> Float {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: Int.Type) throws -> Int {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: Int8.Type) throws -> Int8 {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: Int16.Type) throws -> Int16 {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: Int32.Type) throws -> Int32 {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: Int64.Type) throws -> Int64 {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: UInt.Type) throws -> UInt {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: UInt8.Type) throws -> UInt8 {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: UInt16.Type) throws -> UInt16 {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: UInt32.Type) throws -> UInt32 {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode(_ type: UInt64.Type) throws -> UInt64 {
            try value(as: type)
        }

        /// Decodes a single value of the given type.
        ///
        /// - parameter type: The type to decode as.
        /// - returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
            if let value = value as? T {
                return value
            }

            let decoder = _AnyDecoder(value, path: codingPath)
            return try T(from: decoder)
        }

        /// Decodes a Passthrough value.
        ///
        /// - returns: Whether the encountered value was passthrough.
        func decodePassthrough() throws -> PassthroughAnyCodable {
            guard let value = value as? PassthroughAnyCodable else {
                throw DecodingError.typeMismatch(PassthroughAnyCodable.self, in: self)
            }

            return value
        }

        /// Converts value to any `BinaryInteger`.
        ///
        /// - Parameter type: The `BinaryInteger` to convert as.
        /// - Returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        private func value<T>(as type: T.Type) throws -> T where T: BinaryInteger {
            var value: T?
            switch self.value {
            case let source as T: return source
            case let source as Int: value = T(exactly: source)
            case let source as Int8: value = T(exactly: source)
            case let source as Int16: value = T(exactly: source)
            case let source as Int32: value = T(exactly: source)
            case let source as Int64: value = T(exactly: source)
            case let source as UInt: value = T(exactly: source)
            case let source as UInt8: value = T(exactly: source)
            case let source as UInt16: value = T(exactly: source)
            case let source as UInt32: value = T(exactly: source)
            case let source as UInt64: value = T(exactly: source)
            default: break
            }

            guard let value = value else {
                throw DecodingError.typeMismatch(type, in: self)
            }

            return value
        }

        /// Converts value to any `BinaryFloatingPoint`.
        ///
        /// - Parameter type: The `BinaryFloatingPoint` to convert as.
        /// - Returns: A value of the requested type.
        /// - throws: `DecodingError.typeMismatch` if the value conversion
        ///   fails.
        private func value<T>(as type: T.Type) throws -> T where T: BinaryFloatingPoint {
            if let source = value as? T {
                return source
            }

            if let source = value as? Double {
                return T(source)
            }

            if let source = value as? Float {
                return T(source)
            }

            if let source = try? value(as: Int.self) {
                return T(source)
            }

            throw DecodingError.typeMismatch(type, in: self)
        }
    }
}

private extension DecodingError {
    /// Returns a new `.typeMismatch` error using a constructed coding path and
    /// the given container.
    ///
    /// The coding path for the returned error is the given container's coding
    /// path.
    ///
    /// - param container: The container in which the corrupted data was
    ///   accessed.
    /// - param debugDescription: A description of the error to aid in debugging.
    ///
    /// - Returns: A new `.typeMismatch` error with the given information.
    static func typeMismatch(_ type: Any.Type, in container: _AnyDecoder.SingleValueContainer) -> DecodingError {
        let context = DecodingError.Context(
            codingPath: container.codingPath,
            debugDescription: "Invalid conversion of '\(String(describing: container.value))' to \(type)."
        )

        return .typeMismatch(type, context)
    }
}

internal protocol PassthroughValueDecodingContainer where Self: SingleValueDecodingContainer {
    /// Decodes a Passthrough value.
    ///
    /// - returns: Whether the encountered value was passthrough.
    func decodePassthrough() throws -> PassthroughAnyCodable
}
