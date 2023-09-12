/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An object that encodes instances of an `Encodable` type as `Any?`.
///
/// The example below shows how to encode an instance of a simple `GroceryProduct`
/// type to `Any` object. The type adopts `Codable` so that it's encodable as `Any`
/// using a `AnyEncoder` instance.
///
///     struct GroceryProduct: Codable {
///         var name: String
///         var points: Int
///         var description: String?
///     }
///
///     let pear = GroceryProduct(name: "Pear", points: 250, description: "A ripe pear.")
///
///     let encoder = AnyEncoder()
///
///     let object = try encoder.encode(pear)
///     print(object as! NSDictionary)
///
///     /* Prints:
///     {
///         description = "A ripe pear.";
///         name = Pear;
///         points = 250;
///     }
///     */
open class AnyEncoder {
    /// Initializes `self`.
    public init() { }

    /// Encodes the given top-level value and returns its Any representation.
    ///
    /// Depending on the value and its `Encodable` implementation the returned
    /// encoded value can be `Any`, `[Any?]`, `[String: Any?]`, or `nil`.
    ///
    /// - parameter value: The value to encode.
    /// - returns: An `Any` object containing the value.
    /// - throws: An error if any value throws an error during encoding.
    open func encode<T>(_ value: T) throws -> Any? where T: Encodable {
        let encoder = _AnyEncoder()
        try value.encode(to: encoder)
        return encoder.any
    }
}

/// A type that can encode values into a native format for external
/// representation.
private class _AnyEncoder: Encoder {
    typealias AnyEncodingStorage = (Any?) -> Void

    /// The path of coding keys taken to get to this point in encoding.
    let codingPath: [CodingKey]

    /// Any contextual information set by the user for encoding.
    let userInfo: [CodingUserInfoKey: Any] = [:]

    /// The encoded value.
    var any: Any?

    init(path: [CodingKey] = []) {
        codingPath = path
    }

    /// Returns an encoding container appropriate for holding multiple values
    /// keyed by the given key type.
    ///
    /// You must use only one kind of top-level encoding container. This method
    /// must not be called after a call to `unkeyedContainer()` or after
    /// encoding a value through a call to `singleValueContainer()`
    ///
    /// - parameter type: The key type to use for the container.
    /// - returns: A new keyed encoding container.
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        let container = KeyedContainer<Key>(
            store: { self.any = $0 },
            dictionary: any as? [String: Any?],
            path: codingPath
        )
        self.any = container.dictionary
        return KeyedEncodingContainer(container)
    }

    /// Returns an encoding container appropriate for holding multiple unkeyed
    /// values.
    ///
    /// You must use only one kind of top-level encoding container. This method
    /// must not be called after a call to `container(keyedBy:)` or after
    /// encoding a value through a call to `singleValueContainer()`
    ///
    /// - returns: A new empty unkeyed container.
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let container = UnkeyedContainer(
            store: { self.any = $0 },
            array: any as? [Any?],
            path: codingPath
        )
        self.any = container.array
        return container
    }

    /// Returns an encoding container appropriate for holding a single primitive
    /// value.
    ///
    /// You must use only one kind of top-level encoding container. This method
    /// must not be called after a call to `unkeyedContainer()` or
    /// `container(keyedBy:)`, or after encoding a value through a call to
    /// `singleValueContainer()`
    ///
    /// - returns: A new empty single value container.
    func singleValueContainer() -> SingleValueEncodingContainer {
        SingleValueContainer(
            store: { self.any = $0 },
            path: codingPath
        )
    }

    /// A concrete container that provides a view into an encoder's storage, making
    /// the encoded properties of an encodable type accessible by keys.
    class KeyedContainer<Key>: KeyedEncodingContainerProtocol where Key: CodingKey {
        /// The path of coding keys taken to get to this point in encoding.
        var codingPath: [CodingKey]

        /// The dictionary of encoded value.
        var dictionary: [String: Any?]

        /// The storage closure to call with encoded value.
        let store: AnyEncodingStorage

        /// Creates a keyed container for encoding an `Encodable` object to
        /// a dictionary of `[String: Any?]`.
        ///
        /// - Parameters:
        ///   - store: The storage closure to call with encoded value.
        ///   - dictionary: An existing dictionary of any.
        ///   - path: The path of coding keys taken to get to this point in encoding.
        init(
            store: @escaping AnyEncodingStorage,
            dictionary: [String: Any?]? = nil,
            path: [CodingKey] = []
        ) {
            self.store = store
            self.dictionary = dictionary ?? [:]
            self.codingPath = path
        }

        /// Encodes a null value for the given key.
        ///
        /// - parameter key: The key to associate the value with.
        func encodeNil(forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encodeNil()
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: Bool, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: String, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: Double, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: Float, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: Int, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: Int8, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: Int16, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: Int32, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: Int64, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: UInt, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: UInt8, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: UInt16, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: UInt32, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode(_ value: UInt64, forKey key: Key) throws {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Encodes the given value for the given key.
        ///
        /// - parameter value: The value to encode.
        /// - parameter key: The key to associate the value with.
        func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
            try nestedSingleValueContainer(forKey: key).encode(value)
        }

        /// Stores a keyed encoding container for the given key and returns it.
        ///
        /// - parameter keyType: The key type to use for the container.
        /// - parameter key: The key to encode the container for.
        /// - returns: A new keyed encoding container.
        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
            let container = KeyedContainer<NestedKey>(
                store: { self.set($0, forKey: key) },
                path: codingPath + [key]
            )
            return KeyedEncodingContainer(container)
        }

        /// Stores an unkeyed encoding container for the given key and returns it.
        ///
        /// - parameter key: The key to encode the container for.
        /// - returns: A new unkeyed encoding container.
        func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            UnkeyedContainer(
                store: { self.set($0, forKey: key) },
                path: codingPath + [key]
            )
        }

        /// Stores an single value encoding container for the given key and returns it.
        ///
        /// - parameter key: The key to encode the container for.
        /// - returns: A new unkeyed encoding container.
        func nestedSingleValueContainer(forKey key: Key) -> SingleValueContainer {
            SingleValueContainer(
                store: { self.set($0, forKey: key) },
                path: codingPath + [key]
            )
        }

        /// Set the encoded value at the given key.
        ///
        /// - Parameters:
        ///   - any: The encoded value.
        ///   - key: The key to encode the value for.
        private func set(_ any: Any?, forKey key: Key) {
            dictionary[key.stringValue] = any
            store(dictionary)
        }

        /// Stores a new nested container for the default `super` key and returns a
        /// new encoder instance for encoding `super` into that container.
        ///
        /// Equivalent to calling `superEncoder(forKey:)` with
        /// `Key(stringValue: "super", intValue: 0)`.
        ///
        /// - returns: A new encoder to pass to `super.encode(to:)`.
        func superEncoder() -> Encoder {
            _AnyEncoder(path: codingPath)
        }

        /// Stores a new nested container for the given key and returns a new encoder
        /// instance for encoding `super` into that container.
        ///
        /// - parameter key: The key to encode `super` for.
        /// - returns: A new encoder to pass to `super.encode(to:)`.
        func superEncoder(forKey key: Key) -> Encoder {
            _AnyEncoder(path: codingPath + [key])
        }
    }

    /// A type that provides a view into an encoder's storage and is used to hold
    /// the encoded properties of an encodable type sequentially, without keys.
    class UnkeyedContainer: UnkeyedEncodingContainer {
        /// The path of coding keys taken to get to this point in encoding.
        let codingPath: [CodingKey]

        /// The number of elements encoded into the container.
        var count: Int { array.count }

        /// The array of encoded value.
        var array: [Any?]

        /// The storage closure to call with encoded value.
        let store: AnyEncodingStorage

        /// Creates a unkeyed container for encoding an `Encodable` object to
        /// an array of `[Any?]`.
        ///
        /// - Parameters:
        ///   - store: The storage closure to call with encoded value.
        ///   - array: An existing array of any.
        ///   - path: The path of coding keys taken to get to this point in encoding.
        init(
            store: @escaping AnyEncodingStorage,
            array: [Any?]? = nil,
            path: [CodingKey] = []
        ) {
            self.store = store
            self.array = array ?? []
            self.codingPath = path
        }

        /// Encodes a null value.
        func encodeNil() throws {
            try nestedSingleValueContainer().encodeNil()
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Bool) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: String) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Double) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Float) throws {
            try nestedSingleValueContainer().encode(value)
        }

        func encode(_ value: Int) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Int8) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Int16) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Int32) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Int64) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: UInt) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: UInt8) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: UInt16) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: UInt32) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: UInt64) throws {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes the given value.
        ///
        /// - parameter value: The value to encode.
        func encode<T>(_ value: T) throws where T: Encodable {
            try nestedSingleValueContainer().encode(value)
        }

        /// Encodes a nested container keyed by the given type and returns it.
        ///
        /// - parameter keyType: The key type to use for the container.
        /// - returns: A new keyed encoding container.
        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
            let container = KeyedContainer<NestedKey>(store: append, path: codingPath)
            return KeyedEncodingContainer(container)
        }

        /// Encodes an unkeyed encoding container and returns it.
        ///
        /// - returns: A new unkeyed encoding container.
        func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            UnkeyedContainer(store: append, path: codingPath)
        }

        /// Encodes an single value encoding container and returns it.
        ///
        /// - returns: A new unkeyed encoding container.
        func nestedSingleValueContainer() -> SingleValueContainer {
            SingleValueContainer(store: append, path: codingPath)
        }

        /// Encodes a nested container and returns an `Encoder` instance for encoding
        /// `super` into that container.
        ///
        /// - returns: A new encoder to pass to `super.encode(to:)`.
        func superEncoder() -> Encoder {
            _AnyEncoder(path: codingPath)
        }

        private func append(_ any: Any?) {
            array.append(any)
            store(array)
        }
    }

    /// A container that can support the storage and direct encoding of a single
    /// non-keyed value.
    struct SingleValueContainer: SingleValueEncodingContainer {
        /// The path of coding keys taken to get to this point in encoding.
        let codingPath: [CodingKey]

        /// The storage closure to call with encoded value.
        let store: AnyEncodingStorage

        /// Creates a single value container for encoding an `Encodable` object to
        /// `Any?`.
        ///
        /// - Parameters:
        ///   - store: The storage closure to call with encoded value.
        ///   - path: The path of coding keys taken to get to this point in encoding.
        init(
            store: @escaping AnyEncodingStorage,
            path: [CodingKey] = []
        ) {
            self.store = store
            self.codingPath = path
        }

        /// Encodes a null value.
        func encodeNil() throws {
            store(nil)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Bool) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: String) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Double) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Float) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Int) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Int8) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Int16) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Int32) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: Int64) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: UInt) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: UInt8) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: UInt16) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: UInt32) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode(_ value: UInt64) throws {
            store(value)
        }

        /// Encodes a single value of the given type.
        ///
        /// - parameter value: The value to encode.
        func encode<T>(_ value: T) throws where T: Encodable {
            if value is PassthroughAnyCodable {
                store(value)
            } else {
                let encoder = _AnyEncoder(path: codingPath)
                try value.encode(to: encoder)
                store(encoder.any)
            }
        }
    }
}

/// A passthrough  object will skip encoding when using the ``AnyEncoder``.
/// The object will be stored as-is in the returned `Any?` container.
///
/// Making an `Encodable` as passthrough allow to bypass encoding when the type is
/// known by multiple parties.
///
/// When decoding an object using the ``AnyDecoder``, the decoder will
/// attempt to cast the object to the expected type, a `DecodingError.typeMismatch`
/// error is raised in case of failure.
public protocol PassthroughAnyCodable { }

extension URL: PassthroughAnyCodable { }
extension Date: PassthroughAnyCodable { }
extension UUID: PassthroughAnyCodable { }
extension Data: PassthroughAnyCodable { }
