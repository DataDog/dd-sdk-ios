/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class DateFormattingTests: XCTestCase {
    private let date: Date = .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.001)

    func testISO8601DateFormatter() {
        XCTAssertEqual(
            iso8601DateFormatter.string(from: date),
            "2019-12-15T10:00:00.001Z"
        )
    }

    func testPresentationDateFormatter() {
        XCTAssertEqual(
            presentationDateFormatter(withTimeZone: .UTC).string(from: date),
            "10:00:00.001"
        )
        XCTAssertEqual(
            presentationDateFormatter(withTimeZone: .EET).string(from: date),
            "12:00:00.001"
        )
    }
}
