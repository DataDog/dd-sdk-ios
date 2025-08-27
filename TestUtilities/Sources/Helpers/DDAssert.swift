/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * Provides Datadog specific Assertions in tests.
 * The functions pattern is based on https://github.com/apple/swift-corelibs-xctest
 */

import Foundation
import DatadogInternal
import XCTest

public enum DDAssertError: Error {
    /// An error indicating a known failure that happened in evaluated `expression()` block.
    case expectedFailure(String, keyPath: [String] = [])
}

/// This function emits a test failure if the general expression throws any error.
///
/// - Requires: This and all other DDAssert* functions must be called from
///   within a test method, as passed to `XCTMain`.
///   Assertion failures that occur outside of a test method will *not* be
///   reported as failures.

/// - Parameters:
///   - message: An optional message to use in the failure if the
///   assertion fails. If no message is supplied a default message is used.
///   - file: The file name to use in the error message if the assertion
///   fails. Default is the file containing the call to this function. It is
///   rare to provide this parameter when calling this function.
///   - line: The line number to use in the error message if the
///   assertion fails. Default is the line number of the call to this function
///   in the calling file. It is rare to provide this parameter when calling
///   this function.
///   - expression: A closure to evaluate. The expression must throw an error
///   if the evaluation fails
public func _DDEvaluateAssertion(message: @autoclosure () -> String, file: StaticString, line: UInt, expression: () throws -> Void) {
    do {
        try expression()
    } catch DDAssertError.expectedFailure(let details, let keyPath) {
        var message = message()
        // format message to: <user message> - <failure details> [at keyPath a.b.c]
        message = message.isEmpty ? details : message + " - " + details
        message = keyPath.isEmpty ? message : message + " at keyPath " + keyPath.joined(separator: ".")
        XCTFail(message, file: file, line: line)
    } catch {
        let message = message() + " - threw error \"\(error)\""
        XCTFail(message, file: file, line: line)
    }
}

private func _DDAssertReflectionEqual(_ expression1: @autoclosure () throws -> Any, _ expression2: @autoclosure () throws -> Any, keyPath: [String] = []) throws {
    let (value1, value2) = (try expression1(), try expression2())
    let mirror1 = Mirror(reflecting: value1)
    let mirror2 = Mirror(reflecting: value2)

    guard mirror1.displayStyle == mirror2.displayStyle else {
        throw DDAssertError.expectedFailure("(\"\(value1)\") and (\"\(value2)\") have different types", keyPath: keyPath)
    }

    guard mirror1.children.count == mirror2.children.count else {
        throw DDAssertError.expectedFailure("(\"\(value1)\") and (\"\(value2)\") have different number of children", keyPath: keyPath)
    }

    if mirror1.children.isEmpty && mirror2.children.isEmpty {
        guard String(describing: value1) == String(describing: value2) else { // plain values, compare debug strings
            throw DDAssertError.expectedFailure("(\"\(value1)\") is not equal to (\"\(value2)\")", keyPath: keyPath)
        }

        return
    }

    switch (mirror1.displayStyle, mirror2.displayStyle) {
    case (.dictionary?, .dictionary?): // two dictionaries
        let dictionary1 = value1 as! [AnyHashable: Any]
        let dictionary2 = value2 as! [AnyHashable: Any]

        guard dictionary1.keys.count == dictionary2.keys.count else {
            throw DDAssertError.expectedFailure("dictionaries have different number of keys", keyPath: keyPath)
        }

        for (key1, value1) in dictionary1 {
            guard let value2 = dictionary2[key1] else {
                throw DDAssertError.expectedFailure("dictionaries have different key names", keyPath: keyPath)
            }

            try _DDAssertReflectionEqual(value1, value2, keyPath: keyPath + [key1.description])
        }

        return // dictionaries are equal
    case (.set?, .set?): // two sets
        let set1 = value1 as! Set<AnyHashable>
        let set2 = value2 as! Set<AnyHashable>

        guard set1 == set2 else {
            throw DDAssertError.expectedFailure("sets are not equal", keyPath: keyPath)
        }

        return // sets are equal
    default:
        break // other than dictionary or set, continue...
    }

    for (child1, child2) in zip(mirror1.children, mirror2.children) { // compare each child
        let key = child1.label.map { [$0] } ?? []
        try _DDAssertReflectionEqual(child1.value, child2.value, keyPath: keyPath + key)
    }
}

public func DDAssertReflectionEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    _DDEvaluateAssertion(message: message(), file: file, line: line) {
        try _DDAssertReflectionEqual(expression1(), expression2())
    }
}

public func DDAssertReflectionNotEqual<T>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    _DDEvaluateAssertion(message: message(), file: file, line: line) {
        do {
            try _DDAssertReflectionEqual(expression1(), expression2())
        } catch DDAssertError.expectedFailure {
            return // expected
        }

        throw DDAssertError.expectedFailure("Reflections are equal")
    }
}

private func _DDAssertJSONEqual<T, U>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> U) throws where T: Encodable, U: Encodable {
    let (value1, value2) = (try expression1(), try expression2())

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data1: Data
    let data2: Data
    if #available(iOS 13.0, *) {
        data1 = try encoder.encode(value1)
        data2 = try encoder.encode(value2)
    } else {
        data1 = try encoder.encode(EncodingContainer(value1))
        data2 = try encoder.encode(EncodingContainer(value2))
    }
    let string1 = data1.utf8String
    let string2 = data2.utf8String
    guard string1 == string2 else {
        throw DDAssertError.expectedFailure("(\"\(string1)\") is not equal to (\"\(string2)\")")
    }
}

public func DDAssertJSONEqual(_ expression1: @autoclosure () throws -> Any, _ expression2: @autoclosure () throws -> Any, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    _DDEvaluateAssertion(message: message(), file: file, line: line) {
        try _DDAssertJSONEqual(AnyCodable(expression1()), AnyCodable(expression2()))
    }
}

public func DDAssertJSONEqual<T, U>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> U, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) where T: Encodable, U: Encodable {
    _DDEvaluateAssertion(message: message(), file: file, line: line) {
        try _DDAssertJSONEqual(expression1(), expression2())
    }
}

public func DDAssertJSONNotEqual<T, U>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> U, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) where T: Encodable, U: Encodable {
    _DDEvaluateAssertion(message: message(), file: file, line: line) {
        do {
            try _DDAssertJSONEqual(expression1(), expression2())
        } catch DDAssertError.expectedFailure {
            return // expected
        }

        throw DDAssertError.expectedFailure("JSON representation are equal")
    }
}

private func _DDAssertDictionariesEqual(_ expression1: @autoclosure () throws -> [String: Any], _ expression2: @autoclosure () throws -> [String: Any], keyPath: [String] = []) throws {
    let (dictionary1, dictionary2) = (try expression1(), try expression2())

    guard dictionary1.keys.count == dictionary2.keys.count else {
        throw DDAssertError.expectedFailure("dictionaries have different key names", keyPath: keyPath)
    }

    for (key1, value1) in dictionary1 {
        let keyPath = keyPath + [key1]

        guard let value2 = dictionary2[key1] else {
            throw DDAssertError.expectedFailure("dictionaries have different key names", keyPath: keyPath)
        }

        if let dictionary1 = value1 as? [String: Any], let dictionary2 = value2 as? [String: Any] {
            try _DDAssertDictionariesEqual(dictionary1, dictionary2, keyPath: keyPath)
        } else {
            let string1 = String(describing: value1)
            let string2 = String(describing: value2)
            guard string1 == string2 else {
                throw DDAssertError.expectedFailure("(\"\(string1)\") is not equal to (\"\(string2)\")", keyPath: keyPath)
            }
        }
    }
}

public func DDAssertDictionariesEqual(_ expression1: @autoclosure () throws -> [String: Any], _ expression2: @autoclosure () throws -> [String: Any], _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    _DDEvaluateAssertion(message: message(), file: file, line: line) {
        try _DDAssertDictionariesEqual(expression1(), expression2())
    }
}

public func DDAssertDictionariesNotEqual(_ expression1: @autoclosure () throws -> [String: Any], _ expression2: @autoclosure () throws -> [String: Any], _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    _DDEvaluateAssertion(message: message(), file: file, line: line) {
        do {
            try _DDAssertDictionariesEqual(expression1(), expression2())
        } catch DDAssertError.expectedFailure {
            return // expected
        }

        throw DDAssertError.expectedFailure("Dictionaries are equal")
    }
}

public func DDAssertThrowsError<T, E: Error>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line, _ errorHandler: (_ error: E) -> Void = { _ in }) {
    _DDEvaluateAssertion(message: message(), file: file, line: line) {
        do {
             let result = try expression()
             throw DDAssertError.expectedFailure("Did not throw an error (returned `\(result)` instead)")
         } catch let error as E {
             errorHandler(error) // expected
         } catch let error as DDAssertError {
             throw error
         } catch {
             throw DDAssertError.expectedFailure("Did throw an error but it is not of `\(E.self)` type (got `\(type(of: error))` instead)")
         }
    }
}

/// Asserts that an optional floating-point value is equal to a non-optional one within a given accuracy.
/// Allows the first parameter to be optional and skips unwrapping boilerplate in tests.
public func DDAssertEqual<T: FloatingPoint>(_ expression1: T?, _ expression2: T, accuracy: T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    _DDEvaluateAssertion(message: message(), file: file, line: line) {
        guard let unwrapped = expression1 else {
            throw DDAssertError.expectedFailure("Expected non-nil value in first argument, got `nil`.")
        }
        XCTAssertEqual(unwrapped, expression2, accuracy: accuracy, message(), file: file, line: line)
    }
}

/// Asserts that two dates are equal within a given accuracy.
/// Allows the first parameter to be optional and skips unwrapping boilerplate in tests.
public func DDAssertEqual(_ date1: Date?, _ date2: Date, accuracy: TimeInterval, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    _DDEvaluateAssertion(message: message(), file: file, line: line) {
        guard let date1 = date1 else {
            throw DDAssertError.expectedFailure("Expected non-nil date in first argument, got `nil`.")
        }
        XCTAssertEqual(date1.timeIntervalSince1970, date2.timeIntervalSince1970, accuracy: accuracy, message(), file: file, line: line)
    }
}
