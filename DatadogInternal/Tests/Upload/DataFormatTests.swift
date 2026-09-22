/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

final class DataFormatTests: XCTestCase {
    func testFormatWithNoData() throws {
        let format = DataFormat(prefix: "prefix", suffix: "suffix", separator: "\n")

        let formatted = format.format([])

        XCTAssertEqual(String(data: formatted, encoding: .utf8), "prefixsuffix")
    }

    func testFormatWithSingleData() throws {
        let format = DataFormat(prefix: "prefix", suffix: "suffix", separator: "\n")
        let event = "abc".data(using: .utf8)!

        let formatted = format.format([event])

        XCTAssertEqual(String(data: formatted, encoding: .utf8), "prefixabcsuffix")
    }

    func testFormatWithMaximumBatchSize() throws {
        let format = DataFormat(prefix: "", suffix: "", separator: "\n")
        let numberOfEvents = 1_000
        let eventSize = 5 * 1_024
        let events = Array(repeating: Data(repeating: 0x61, count: eventSize), count: numberOfEvents)

        let formatted = format.format(events)

        let separatorsSize = numberOfEvents - 1
        XCTAssertEqual(formatted.count, numberOfEvents * eventSize + separatorsSize)
    }

    func testFormat() throws {
        let format = DataFormat(prefix: "prefix", suffix: "suffix", separator: "\n")
        let events = [
            "abc".data(using: .utf8)!,
            "def".data(using: .utf8)!,
            "ghi".data(using: .utf8)!
        ]
        let formatted = format.format(events)
        let actual = String(data: formatted, encoding: .utf8)!
        let expected =
        """
        prefixabc
        def
        ghisuffix
        """
        XCTAssertEqual(actual, expected)
    }
}
