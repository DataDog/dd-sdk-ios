/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class UUIDTests: XCTestCase {
    func testToHexadecimalStringConversion() {
        XCTAssertEqual(TracingUUID(rawValue: 0).toHexadecimalString, "0")
        XCTAssertEqual(TracingUUID(rawValue: 1).toHexadecimalString, "1")
        XCTAssertEqual(TracingUUID(rawValue: 15).toHexadecimalString, "F")
        XCTAssertEqual(TracingUUID(rawValue: 16).toHexadecimalString, "10")
        XCTAssertEqual(TracingUUID(rawValue: 123).toHexadecimalString, "7B")
        XCTAssertEqual(TracingUUID(rawValue: 123_456).toHexadecimalString, "1E240")
        XCTAssertEqual(TracingUUID(rawValue: .max).toHexadecimalString, "FFFFFFFFFFFFFFFF")
    }
}
