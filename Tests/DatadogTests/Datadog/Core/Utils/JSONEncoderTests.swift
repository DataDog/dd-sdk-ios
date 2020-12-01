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
        let encodedDate = try jsonEncoder.encode(
            EncodingContainer(Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 0.123))
        )

        XCTAssertEqual(encodedDate.utf8String, #"{"value":"2019-12-15T10:00:00.123Z"}"#)
    }

    func testURLEncoding() throws {
        let encodedURL = try jsonEncoder.encode(
            EncodingContainer(URL(string: "https://example.com/foo")!)
        )

        if #available(iOS 13.0, OSX 10.15, *) {
            XCTAssertEqual(encodedURL.utf8String, #"{"value":"https://example.com/foo"}"#)
        } else {
            XCTAssertEqual(encodedURL.utf8String, #"{"value":"https:\/\/example.com\/foo"}"#)
        }
    }

    func testWhenEncoding_thenKeysFollowLexicographicOrder() throws {
        struct Foo: Codable {
            var one = 1
            var two = 1
            var three = 1
            var four = 1
            var five = 1

            enum CodingKeys: String, CodingKey {
                case one = "aaaaaa"
                case two = "bb"
                case three = "aaa"
                case four = "bbb"
                case five = "aaa.aaa"
            }
        }

        // When
        let encodedFoo = try jsonEncoder.encode(Foo())

        // Then
        XCTAssertEqual(
            encodedFoo.utf8String,
            #"{"aaa":1,"aaa.aaa":1,"aaaaaa":1,"bb":1,"bbb":1}"#
        )
    }
}
