/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest
import TestUtilities

/// Provides set of assertions for single JSON object or collection of JSON objects.
/// Note: this file is individually referenced by integration tests project, so no dependency on other source files should be introduced.
internal class JSONDataMatcher {
    let json: [String: Any]

    // MARK: - Initialization

    init(from jsonObject: [String: Any]) {
        self.json = jsonObject
    }

    // MARK: - Full match

    func assertItFullyMatches(jsonString: String, file: StaticString = #file, line: UInt = #line) throws {
        let thisJSON = json as NSDictionary
        let theirJSON = try jsonString.data(using: .utf8)!
            .toJSONObject(file: file, line: line) as NSDictionary // swiftlint:disable:this force_unwrapping

        XCTAssertEqual(thisJSON, theirJSON, file: file, line: line)
    }

    // MARK: - Generic matches

    func assertValue<T: Equatable>(forKey key: String, equals value: T, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(json[key] as? T, value, file: file, line: line)
    }

    func assertNoValue(forKey key: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertNil(json[key], file: file, line: line)
    }

    func assertValue<T: Equatable>(forKeyPath keyPath: String, equals value: T, file: StaticString = #file, line: UInt = #line) {
        let dictionary = json as NSDictionary
        let dictionaryValue = dictionary.value(forKeyPath: keyPath)
        guard let jsonValue = dictionaryValue as? T else {
            XCTFail("Value at key path `\(keyPath)` is not of type `\(type(of: value))`: \(String(describing: dictionaryValue))", file: file, line: line)
            return
        }
        XCTAssertEqual(jsonValue, value, file: file, line: line)
    }

    func assertNoValue(forKeyPath keyPath: String, file: StaticString = #file, line: UInt = #line) {
        let dictionary = json as NSDictionary
        XCTAssertNil(dictionary.value(forKeyPath: keyPath), file: file, line: line)
    }

    func assertValue<T: Equatable>(
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

    func assertValue<T>(
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

    func value<T>(forKeyPath keyPath: String) throws -> T {
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
}
