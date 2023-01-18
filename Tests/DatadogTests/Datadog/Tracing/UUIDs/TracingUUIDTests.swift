/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class UUIDTests: XCTestCase {
    func testToHexadecimalStringConversion() {
        XCTAssertEqual(TracingUUID(rawValue: 0).toString(.hexadecimal), "0")
        XCTAssertEqual(TracingUUID(rawValue: 1).toString(.hexadecimal), "1")
        XCTAssertEqual(TracingUUID(rawValue: 15).toString(.hexadecimal), "f")
        XCTAssertEqual(TracingUUID(rawValue: 16).toString(.hexadecimal), "10")
        XCTAssertEqual(TracingUUID(rawValue: 123).toString(.hexadecimal), "7b")
        XCTAssertEqual(TracingUUID(rawValue: 123_456).toString(.hexadecimal), "1e240")
        XCTAssertEqual(TracingUUID(rawValue: .max).toString(.hexadecimal), "ffffffffffffffff")
    }

    func testToDecimalStringConversion() {
        XCTAssertEqual(TracingUUID(rawValue: 0).toString(.decimal), "0")
        XCTAssertEqual(TracingUUID(rawValue: 1).toString(.decimal), "1")
        XCTAssertEqual(TracingUUID(rawValue: 15).toString(.decimal), "15")
        XCTAssertEqual(TracingUUID(rawValue: 16).toString(.decimal), "16")
        XCTAssertEqual(TracingUUID(rawValue: 123).toString(.decimal), "123")
        XCTAssertEqual(TracingUUID(rawValue: 123_456).toString(.decimal), "123456")
        XCTAssertEqual(TracingUUID(rawValue: .max).toString(.decimal), "\(UInt64.max)")
    }

    func testInitializationFromHexadecimal() {
        XCTAssertEqual(TracingUUID("0", .hexadecimal)?.toString(.decimal), "0")
        XCTAssertEqual(TracingUUID("1", .hexadecimal)?.toString(.decimal), "1")
        XCTAssertEqual(TracingUUID("f", .hexadecimal)?.toString(.decimal), "15")
        XCTAssertEqual(TracingUUID("10", .hexadecimal)?.toString(.decimal), "16")
        XCTAssertEqual(TracingUUID("7b", .hexadecimal)?.toString(.decimal), "123")
        XCTAssertEqual(TracingUUID("1e240", .hexadecimal)?.toString(.decimal), "123456")
        XCTAssertEqual(TracingUUID("FFFFFFFFFFFFFFFF", .hexadecimal)?.toString(.decimal), "\(UInt64.max)")
    }

    func testInitializationFromDecimal() {
        XCTAssertEqual(TracingUUID("0", .decimal)?.toString(.hexadecimal), "0")
        XCTAssertEqual(TracingUUID("1", .decimal)?.toString(.hexadecimal), "1")
        XCTAssertEqual(TracingUUID("15", .decimal)?.toString(.hexadecimal), "f")
        XCTAssertEqual(TracingUUID("16", .decimal)?.toString(.hexadecimal), "10")
        XCTAssertEqual(TracingUUID("123", .decimal)?.toString(.hexadecimal), "7b")
        XCTAssertEqual(TracingUUID("123456", .decimal)?.toString(.hexadecimal), "1e240")
        XCTAssertEqual(TracingUUID("\(UInt64.max)", .decimal)?.toString(.hexadecimal), "ffffffffffffffff")
    }
}
