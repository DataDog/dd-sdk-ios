/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A `FeatureBaggage` holds any codable value.
///
/// Values are uniquely identified by key as `String`, the value type is validated on `get`
/// either explicity, when specified, or inferred.
///
/// ## Creates a Feature Baggage
/// Create a baggage by providing an `Encodable` value.
///
/// The example below shows how to create a baggage from an instance of a simple `GroceryProduct`:
///
///     struct GroceryProduct: Encodable {
///         var name: String
///         var points: Int
///         var description: String?
///     }
///
///     let pear = GroceryProduct(name: "Pear", points: 250, description: "A ripe pear.")
///     let baggage = FeatureBaggage(pear)
///
/// The `pear` is stored as a dictionary within the baggage:
///
///     print(baggage.rawValue)
///     // ["description": Optional("A ripe pear."), "points": Optional(250), "name": Optional("Pear")]
///
/// ## Accessing Value
/// The baggage value can then be decoded to any type that follow the same schema.
///
/// The following example decodes the baggage into a new data type:
///
///     struct CartItem: Decodable {
///         var name: String
///         var points: Int
///     }
///
///     let item: CartItem = try baggage.decode()
///
///     print(item)
///     // CartItem(name: "Pear", points: 250)
///
/// A Feature Baggage does not ensure thread-safety of values that holds references, make
/// sure that any value can be accessibe from any thread.
@available(*, deprecated, message: "FeatureBaggage has performance implications and will be removed.")
public final class FeatureBaggage {
    /// The raw value contained in the baggage.
    @ReadWriteLock
    private var rawValue: Any?

    /// The underlying encoding process.
    private let _encode: () throws -> Any?

    /// Creates an instance initialized with the given encodable.
    public init<Value>(_ value: Value) where Value: Encodable {
        let encoder = AnyEncoder()
        self._encode = { try encoder.encode(value) }
    }

    /// Encodes the baggage value to `Any?`
    ///
    /// - Returns: The encoded baggage value.
    public func encode() throws -> Any? {
        // lazily encode to save from encoding
        // if the value is never decoded.
        if let rawValue = self.rawValue {
            return rawValue
        }
        let rawValue = try _encode()
        self.rawValue = rawValue
        return rawValue
    }

    /// Decodes the value stored in the baggage.
    ///
    /// - Parameters:
    ///   - type: The expected value type.
    /// - Returns: The decoded baggage.
    public func decode<Value>(type: Value.Type = Value.self) throws -> Value where Value: Decodable {
        let decoder = AnyDecoder()
        return try decoder.decode(from: encode())
    }
}
