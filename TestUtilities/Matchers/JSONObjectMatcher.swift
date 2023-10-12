/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public enum JSONMatcherException: Error {
    case objectException(String)
    case arrayException(String)
}

/// A type-safe matcher for dynamic `[String: Any]` JSON objects.
public class JSONObjectMatcher {
    public let object: [String: Any]

    /// Creates a matcher for a given JSON object.
    /// - Parameter object: The JSON object.
    public init(object: [String: Any]) {
        self.object = object
    }

    /// Returns a JSON object matcher for the object at the specified key-path.
    /// - Parameter keyPath: The key-path.
    /// - Returns: A JSON object matcher for the nested JSON object.
    ///
    /// Throws an error if the element at `keyPath` is not a JSON object.
    public func object(_ keyPath: String) throws -> JSONObjectMatcher { .init(object: try value(keyPath)) }

    /// Returns a JSON array matcher for the array at the specified key-path.
    /// - Parameter keyPath: The key-path.
    /// - Returns: A JSON array matcher for the nested JSON array.
    ///
    /// Throws an error if the element at `keyPath` is not a JSON array.
    public func array(_ keyPath: String) throws -> JSONArrrayMatcher { .init(array: try value(keyPath)) }

    /// Casts the value at the specified key-path to the expected type.
    /// - Parameter keyPath: The key-path.
    /// - Returns: The value at the key-path casted to the expected type.
    ///
    /// Throws an error if the element at `keyPath` cannot be represented as the expected type.
    public func value<T>(_ keyPath: String) throws -> T {
        guard let any = (object as NSDictionary).value(forKeyPath: keyPath) else {
            throw JSONMatcherException.objectException("No value for key path `\(keyPath)`")
        }
        guard let value = any as? T else {
            throw JSONMatcherException.objectException("Cannot cast value for key path `\(keyPath)` to type `\(T.self)`: \(String(describing: any))")
        }
        return value
    }
}

/// A type-safe matcher for dynamic `[Any]` JSON arrays.
public class JSONArrrayMatcher {
    public let array: [Any]

    /// Creates a matcher for a given JSON array.
    /// - Parameter array: The JSON array.
    public init(array: [Any]) {
        self.array = array
    }

    /// Returns a JSON object matcher for the element at the specified index.
    /// - Parameter index: The index.
    /// - Returns: A JSON object matcher for the nested JSON object.
    ///
    /// Throws an error if the element at the given index is not a JSON object.
    public func object(at index: Int) throws -> JSONObjectMatcher { .init(object: try value(at: index)) }

    /// Returns a JSON object matchers for all elements in this array.
    /// - Returns: An array of JSON object matchers.
    ///
    /// Throws an error if the any of elements is not a JSON object.
    public func objects() throws -> [JSONObjectMatcher] {
        return try array.enumerated().map { idx, element in
            guard let object = element as? [String: Any] else {
                throw JSONMatcherException.arrayException("Element at index `\(idx)` is not a JSON object: \(String(describing: element))")
            }
            return JSONObjectMatcher(object: object)
        }
    }

    /// Returns a JSON array matcher for the element at the specified index.
    /// - Parameter index: The index.
    /// - Returns: A JSON array matcher for the nested JSON array.
    ///
    /// Throws an error if the element at the given index is not a JSON array.
    public func array(at index: Int) throws -> JSONArrrayMatcher { .init(array: try value(at: index)) }

    /// Casts the element at the specified index to the expected type.
    /// - Parameter index: The index.
    /// - Returns: The element at the index casted to the expected type.
    ///
    /// Throws an error if the element at the given index cannot be represented as the expected type
    /// or if the index is out of bounds.
    public func value<T>(at index: Int) throws -> T {
        guard index < array.count else {
            throw JSONMatcherException.arrayException("Array index `\(index)` is out of bounds - the array has only \(array.count) items")
        }
        guard let value = array[index] as? T else {
            throw JSONMatcherException.arrayException("Cannot cast element at index `\(index)` to type `\(T.self)`: \(String(describing: array[index]))")
        }
        return value
    }

    /// Casts all elements in this array to the expected type.
    /// - Returns: Array elements casted to the expected type.
    ///
    /// Throws an error if any of the elements cannot be represented as the expected type.
    public func values<T>() throws -> [T] {
        return try array.map { element in
            guard let value = element as? T else {
                throw JSONMatcherException.arrayException("Cannot cast array element \(String(describing: element)) to type `\(T.self)`")
            }
            return value
        }
    }

    /// The number of elements in the array.
    public var count: Int { array.count }
}
