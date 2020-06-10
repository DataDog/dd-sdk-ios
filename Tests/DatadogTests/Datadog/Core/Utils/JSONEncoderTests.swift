/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class JSONEncoderTests: XCTestCase {
    private let jsonEncoder = JSONEncoder.default()

    func testDateEncoding() throws {
        /// Prior to `iOS13.0` `JSONEncoder` supports only object or array as the root type, hence we can't encode `Date` directly.
        struct Container: Encodable {
            let date: Date = .mockDecember15th2019At10AMUTC(addingTimeInterval: 0.123)
        }

        let encodedDate = try jsonEncoder.encode(Container())

        XCTAssertEqual(encodedDate.utf8String, #"{"date":"2019-12-15T10:00:00.123Z"}"#)
    }

    func testURLEncoding() throws {
        /// Prior to `iOS13.0` `JSONEncoder` supports only object or array as the root type, hence we can't encode `URL` directly.
        struct Container: Encodable {
            let url = URL(string: "https://example.com/foo")!
        }

        let encodedURL = try jsonEncoder.encode(Container())

        if #available(iOS 13.0, OSX 10.15, *) {
            XCTAssertEqual(encodedURL.utf8String, #"{"url":"https://example.com/foo"}"#)
        } else {
            XCTAssertEqual(encodedURL.utf8String, #"{"url":"https:\/\/example.com\/foo"}"#)
        }
    }
}
