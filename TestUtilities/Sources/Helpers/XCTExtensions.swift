/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

/// Asserts that an optional floating-point value is equal to a non-optional one within a given accuracy.
/// Allows the first parameter to be optional and skips unwrapping boilerplate in tests.
public func XCTAssertEqual<T: FloatingPoint>(_ expression1: T?, _ expression2: T, accuracy: T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    guard let unwrapped = expression1 else {
        XCTFail("Expected non-nil value. " + message(), file: file, line: line)
        return
    }
    XCTAssertEqual(unwrapped, expression2, accuracy: accuracy, message(), file: file, line: line)
}

/// Asserts that two dates are equal within a given accuracy.
/// Allows the first parameter to be optional and skips unwrapping boilerplate in tests.
public func XCTAssertEqual(_ date1: Date?, _ date2: Date, accuracy: TimeInterval, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(date1?.timeIntervalSince1970, date2.timeIntervalSince1970, accuracy: accuracy, message(), file: file, line: line)
}
