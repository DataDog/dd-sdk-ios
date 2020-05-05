/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DateFormatterTests: XCTestCase {
    func testISO8601FormatWithSubSecondPrecision() throws {
        let dateFormatter = ISO8601DateFormatter.default()

        let knownDate: Date = .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.123)
        let formattedDate = dateFormatter.string(from: knownDate)

        XCTAssertEqual(formattedDate, "2019-12-15T10:00:00.123Z")
    }
}

class EncodingTests: XCTestCase {
    func testEncodingDateWithSubSecondPrecision() throws {
        let jsonEncoder = JSONEncoder.default()

        let knownDate: Date = .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.123)
        let encodedKnownDate = try jsonEncoder.encode(knownDate)

        let jsonDecoder = JSONDecoder()
        let knownDateDecodedString = try jsonDecoder.decode(String.self, from: encodedKnownDate)

        XCTAssertEqual(knownDateDecodedString, "2019-12-15T10:00:00.123Z")
    }
}
