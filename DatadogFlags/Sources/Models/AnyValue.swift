/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A type-safe representation of JSON values for attributes and object flags.
///
/// `AnyValue` is used to represent arbitrary JSON data in feature flag contexts, particularly for:
/// - Custom attributes in ``FlagsEvaluationContext``
/// - Object-type feature flag values
///
/// You can create `AnyValue` instances using the case constructors:
///
/// ```swift
/// let context = FlagsEvaluationContext(
///     targetingKey: "user-123",
///     attributes: [
///         "email": .string("user@example.com"),
///         "age": .int(25),
///         "premium": .bool(true),
///         "balance": .double(99.99),
///         "tags": .array([.string("beta"), .string("power-user")]),
///         "metadata": .dictionary(["level": .int(5)]),
///         "optional_field": .null
///     ]
/// )
/// ```
public enum AnyValue: Equatable, Hashable {
    /// A string value.
    case string(String)

    /// A boolean value.
    case bool(Bool)

    /// An integer value.
    case int(Int)

    /// A double-precision floating-point value.
    case double(Double)

    /// A dictionary (object) with string keys and `AnyValue` values.
    ///
    /// ```swift
    /// let config: AnyValue = .dictionary([
    ///     "timeout": .int(30),
    ///     "retries": .int(3)
    /// ])
    /// ```
    case dictionary([String: AnyValue])

    /// An array of `AnyValue` elements.
    ///
    /// ```swift
    /// let tags: AnyValue = .array([
    ///     .string("important"),
    ///     .string("urgent")
    /// ])
    /// ```
    case array([AnyValue])

    /// A null value.
    case null
}

extension AnyValue {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .string(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .bool(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .int(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .double(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .dictionary(let value):
            hasher.combine(4)
            for key in value.keys.sorted() {
                hasher.combine(key)
                hasher.combine(value[key])
            }
        case .array(let value):
            hasher.combine(5)
            for element in value {
                hasher.combine(element)
            }
        case .null:
            hasher.combine(6)
        }
    }
}

extension AnyValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode([String: AnyValue].self) {
            self = .dictionary(value)
        } else if let value = try? container.decode([AnyValue].self) {
            self = .array(value)
        } else if container.decodeNil() {
            self = .null
        } else {
            let context = DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Cannot decode AnyValue"
            )
            throw DecodingError.typeMismatch(AnyValue.self, context)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .dictionary(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
