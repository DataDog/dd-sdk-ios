/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest

/// Provides set of assertions for single JSON object or collection of JSON objects.
/// Note: this file is individually referenced by integration tests project, so no dependency on other source files should be introduced.
public class JSONDataMatcher {
    let json: [String: Any]

    // MARK: - Initialization

    public init(from jsonObject: [String: Any]) {
        self.json = jsonObject
    }

    // MARK: - Full match

    public func assertItFullyMatches(jsonString: String, file: StaticString = #file, line: UInt = #line) throws {
        let thisJSON = json as NSDictionary
        let theirJSON = try jsonString.data(using: .utf8)!
            .toJSONObject(file: file, line: line) as NSDictionary // swiftlint:disable:this force_unwrapping

        XCTAssertEqual(thisJSON, theirJSON, file: file, line: line)
    }

    // MARK: - Generic matches

    /// Compares two values for a given key.
    ///
    /// Used by ``assertItMatches(jsonString:usingCustomKeyComparators:file:line:)``.
    public typealias CustomKeyComparator = (Any, Any, StaticString, UInt) throws -> Void

    /// Asserts a match between two JSON objects, using optional comparators
    /// for a specific set of keys.
    ///
    /// This is useful when two JSON objects need to be compared, but the
    /// values of one of the keys need to be compared in a more complex way
    /// than just the basic equality. For example, the tags field may have the
    /// same tags in a different order, causing a failure even if they are semantically
    /// equivalent.
    ///
    /// - parameters:
    ///   - jsonString: The JSON string to compare with the JSON object held by
    ///   this matcher.
    ///   - customKeyComparators: Dictionary of keys and comparators. Any
    ///   key present in this dictionary will be tested using its comparator. Otherwise,
    ///   the regular equality comparison is used.
    ///   - file: The file where the assertion is made. Defaults to `#file`.
    ///   - line: The line where the assertion is made in `file`. Defaults to `#line`.
    public func assertItMatches(jsonString: String, usingCustomKeyComparators customKeyComparators: [String: CustomKeyComparator], file: StaticString = #file, line: UInt = #line) throws {
        var thisJSON = json
        var theirJSON = try jsonString.data(using: .utf8)!
            .toJSONObject(file: file, line: line) // swiftlint:disable:this force_unwrapping

        try customKeyComparators.forEach { key, comparator in
            defer {
                thisJSON.removeValue(forKey: key)
                theirJSON.removeValue(forKey: key)
            }

            let thisValue = thisJSON[key]
            let theirValue = thisJSON[key]

            try comparator(thisValue as Any, theirValue as Any, file, line)
        }

        XCTAssertEqual(thisJSON as NSDictionary, theirJSON as NSDictionary, file: file, line: line)
    }

    public func assertValue<T: Equatable>(forKey key: String, equals value: T, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(json[key] as? T, value, file: file, line: line)
    }

    public func assertNoValue(forKey key: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertNil(json[key], file: file, line: line)
    }

    public func assertValue<T: Equatable>(forKeyPath keyPath: String, equals value: T, file: StaticString = #file, line: UInt = #line) {
        let dictionary = json as NSDictionary
        let dictionaryValue = dictionary.value(forKeyPath: keyPath)
        guard let jsonValue = dictionaryValue as? T else {
            XCTFail("Value at key path `\(keyPath)` is not of type `\(type(of: value))`: \(String(describing: dictionaryValue))", file: file, line: line)
            return
        }
        XCTAssertEqual(jsonValue, value, file: file, line: line)
    }

    public func assertNoValue(forKeyPath keyPath: String, file: StaticString = #file, line: UInt = #line) {
        let dictionary = json as NSDictionary
        XCTAssertNil(dictionary.value(forKeyPath: keyPath), file: file, line: line)
    }

    public func assertValue<T: Equatable>(
        forKeyPath keyPath: String,
        matches matcherClosure: (T) -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let dictionary = json as NSDictionary
        let dictionaryValue = dictionary.value(forKeyPath: keyPath)
        guard let jsonValue = dictionaryValue as? T else {
            XCTFail(
                "Can't cast value at key path `\(keyPath)` to expected type: \(String(describing: dictionaryValue))",
                file: file,
                line: line
            )
            return
        }

        XCTAssertTrue(matcherClosure(jsonValue), file: file, line: line)
    }

    public func assertValue<T>(
        forKeyPath keyPath: String,
        isTypeOf type: T.Type,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let dictionary = json as NSDictionary
        let dictionaryValue = dictionary.value(forKeyPath: keyPath)
        XCTAssertTrue((dictionaryValue as? T) != nil, file: file, line: line)
    }

    // MARK: - Values extraction

    internal struct Exception: Error {
        let description: String
    }

    /// Returns value at given key-path by casting it to expected type.
    /// Throws an error if  value at given key-path does not exist.
    public func value<T>(forKeyPath keyPath: String) throws -> T {
        let dictionary = json as NSDictionary
        guard let anyValue = dictionary.value(forKeyPath: keyPath) else {
            throw Exception(
                description: "No value for key path `\(keyPath)`"
            )
        }
        guard let tValue = anyValue as? T else {
            throw Exception(
                description: "Cannot cast value for key path `\(keyPath)` to type `\(T.self)`: \(String(describing: anyValue))"
            )
        }
        return tValue
    }

    /// Returns value at given key-path by casting it to expected type.
    /// Returns `nil` if no value at given key-path exist.
    public func valueOrNil<T>(forKeyPath keyPath: String) throws -> T? {
        let dictionary = json as NSDictionary
        guard let anyValue = dictionary.value(forKeyPath: keyPath) else {
            return nil
        }
        guard let tValue = anyValue as? T else {
            throw Exception(
                description: "Cannot cast value for key path `\(keyPath)` to type `\(T.self)`: \(String(describing: anyValue))"
            )
        }
        return tValue
    }
}
