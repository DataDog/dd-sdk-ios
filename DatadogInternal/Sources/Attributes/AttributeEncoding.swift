/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Context for attribute encoding, used to provide clearer error messages to customers.
public enum AttributeEncodingContext {
    /// User-provided custom attribute
    case custom
    /// User info extra attribute (usr.*)
    case userInfo
    /// Account info extra attribute (account.*)
    case accountInfo
    /// Internal SDK attribute
    case `internal`

    public var errorMessagePrefix: String {
        switch self {
        case .custom:
            return ""
        case .userInfo:
            return "user info "
        case .accountInfo:
            return "account "
        case .internal:
            return "internal "
        }
    }
}

public extension KeyedEncodingContainer {
    /// Encodes an attribute, catching and logging any encoding failures.
    /// If encoding fails, the attribute is skipped and an error is logged, but execution continues.
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
            try encode(value, forKey: key)
        } catch {
            let contextPrefix = context.errorMessagePrefix
            DD.logger.error(
                "Failed to encode \(contextPrefix)attribute '\(attributeName)': \(error). This attribute will be dropped from the event."
            )
        }
    }
}
