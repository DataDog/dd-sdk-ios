/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

private extension CodingUserInfoKey {
    static let shouldRecoverAttributeFailures = CodingUserInfoKey(
        rawValue: "com.datadoghq.should-recover-attribute-failures"
    )
}

private struct RecoverableAttributeEncodingError: Error {}

public extension Encoder {
    /// Whether attribute failures should be isolated from the enclosing value.
    @_spi(Internal)
    var shouldRecoverAttributeFailures: Bool {
        guard let key = CodingUserInfoKey.shouldRecoverAttributeFailures else {
            return false
        }
        return userInfo[key] as? Bool ?? false
    }
}

public extension DatadogExtension where ExtendedType == JSONEncoder {
    /// Encodes directly, then retries once with individual attributes isolated if one fails.
    /// Values reached during the first attempt can execute their `encode(to:)` implementation twice.
    @_spi(Internal)
    func encodeWithAttributeRecovery<T: Encodable>(_ value: T) throws -> Data {
        guard let recoveryKey = CodingUserInfoKey.shouldRecoverAttributeFailures else {
            return try type.encode(value)
        }

        let previousValue = type.userInfo[recoveryKey]
        type.userInfo[recoveryKey] = nil
        defer { type.userInfo[recoveryKey] = previousValue }

        do {
            return try type.encode(value)
        } catch is RecoverableAttributeEncodingError {
            type.userInfo[recoveryKey] = true
            return try type.encode(value)
        }
    }
}

public extension KeyedEncodingContainer {
    /// Encodes an attribute, catching and logging any encoding failures.
    /// If encoding fails, the attribute is replaced with `null` and an error is logged.
    /// This prevents a single malformed attribute from causing the entire event to be dropped.
    ///
    /// - Parameters:
    ///   - value: The encodable value to encode
    ///   - key: The coding key for this attribute
    ///   - attributeName: The name of the attribute as known by the customer (for error reporting)
    ///   - context: The context of this attribute (custom, userInfo, accountInfo, or internal)
    mutating func encodeAttribute<T: Encodable>(
        _ value: T,
        forKey key: Key,
        attributeName: String,
        context: AttributeEncodingContext = .custom
    ) {
        do {
            // A referencing encoder confines partial writes to this key while preserving the
            // event encoder's coding path, strategies, and user info.
            let attributeEncoder = superEncoder(forKey: key)
            try encodeAttributeValue(value, to: attributeEncoder)
        } catch {
            // `superEncoder(forKey:)` reserves the key, so replace any partial value with null.
            try? encodeNil(forKey: key)
            DD.logger.error(
                "Failed to encode \(context.errorMessagePrefix)attribute '\(attributeName)'. "
                    + "This attribute will be encoded as null.",
                error: error
            )
        }
    }

    /// Encodes directly during the initial pass and isolates attribute failures during recovery.
    @_spi(Internal)
    mutating func encodeAttribute<T: Encodable>(
        _ value: T,
        forKey key: Key,
        attributeName: String,
        context: AttributeEncodingContext,
        shouldRecover: Bool
    ) throws {
        if shouldRecover {
            encodeAttribute(
                value,
                forKey: key,
                attributeName: attributeName,
                context: context
            )
            return
        }

        do {
            try encode(value, forKey: key)
        } catch {
            throw RecoverableAttributeEncodingError()
        }
    }
}

private extension KeyedEncodingContainer {
    /// Encodes through the encoder's container to preserve its strategies and specialized handling.
    func encodeAttributeValue<T: Encodable>(_ value: T, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
