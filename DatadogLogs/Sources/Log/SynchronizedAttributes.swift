/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A thread-safe container for managing attributes in a key-value format.
/// This class allows concurrent access and modification of attributes, ensuring data consistency
/// through the use of a `ReadWriteLock`. It is designed to be used in scenarios where attributes
/// need to be safely managed across multiple threads or tasks.
internal final class SynchronizedAttributes: Sendable {
    /// The underlying dictionary of attributes, wrapped in a `ReadWriteLock` to ensure thread safety.
    private let attributes: ReadWriteLock<[String: Encodable]>

    /// Initializes a new instance of `SynchronizedAttributes` with the provided dictionary.
    ///
    /// - Parameter attributes: A dictionary of initial attributes.
    init(attributes: [String: Encodable]) {
        self.attributes = .init(wrappedValue: attributes)
    }

    /// Adds or updates an attribute in the container.
    ///
    /// - Parameters:
    ///   - key: The key associated with the attribute.
    ///   - value: The value to associate with the key.
    func addAttribute(key: AttributeKey, value: AttributeValue) {
        attributes.mutate { $0[key] = value }
    }

    /// Removes an attribute from the container.
    ///
    /// - Parameter key: The key of the attribute to remove.
    func removeAttribute(forKey key: AttributeKey) {
        attributes.mutate { $0.removeValue(forKey: key) }
    }

    /// Retrieves the current dictionary of attributes.
    ///
    /// - Returns: A dictionary containing all the attributes.
    func getAttributes() -> [String: Encodable] {
        return attributes.wrappedValue
    }
}
