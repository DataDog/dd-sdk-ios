/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

final class FixedWidthIntegerConvinienceTests: XCTestCase {
    func test_Bytes() {
        let value: Int = 1_000
        XCTAssertEqual(value.bytes, 1_000)
    }

    func test_Kilobytes() {
        let value: Int = 1
        XCTAssertEqual(value.KB, 1_024)
    }

    func test_Megabytes() {
        let value: Int = 1
        XCTAssertEqual(value.MB, 1_048_576)
    }

    func test_Gigabytes() {
        let value: Int = 1
        XCTAssertEqual(value.GB, 1_073_741_824)
    }

    func test_OverflowKilobytes() {
        let value = UInt64.max / 1_024
        XCTAssertEqual(value.KB, UInt64.max &- 1_023)
    }

    func test_OverflowMegabytes() {
        let value = UInt64.max / (1_024 * 1_024)
        XCTAssertEqual(value.MB, UInt64.max &- 1_048_575)
    }

    func test_OverflowGigabytes() {
        let value = UInt64.max / (1_024 * 1_024 * 1_024)
        XCTAssertEqual(value.GB, UInt64.max &- 1_073_741_823)
    }
}
