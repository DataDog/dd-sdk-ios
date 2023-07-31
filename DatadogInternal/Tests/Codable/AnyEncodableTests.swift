/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * This file includes software developed by Flight School, https://flight.school/ and altered by Datadog.
 * Use of this source code is governed by MIT license:
 *
 * Copyright 2018 Read Evaluate Press, LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
 * documentation files (the "Software"), to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or substantial portions
 * of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
 * TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
 * CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

import XCTest
import DatadogInternal

class AnyEncodableTests: XCTestCase {
    struct SomeEncodable: Encodable {
        var string: String
        var int: Int
        var bool: Bool
        var hasUnderscore: String

        enum CodingKeys: String,CodingKey {
            case string
            case int
            case bool
            case hasUnderscore = "has_underscore"
        }
    }

    func testJSONEncoding() throws {
        let someEncodable = AnyEncodable(
            SomeEncodable(
                string: "String",
                int: 100,
                bool: true,
                hasUnderscore: "another string"
            )
        )

        let dictionary: [String: Any?] = [
            "boolean": true,
            "integer": 42,
            "double": 3.141592653589793,
            "string": "string",
            "array": [1, 2, 3],
            "nested": [
                "a": "alpha",
                "b": "bravo",
                "c": "charlie",
            ],
            "someCodable": someEncodable,
            "null": nil,
            "url": URL(string: "https://example.com/image.png")!
        ]

        let encoder = JSONEncoder()

        let json = try encoder.encode(AnyEncodable(dictionary))
        let encodedJSONObject = try JSONSerialization.jsonObject(with: json, options: []) as! NSDictionary

        let expected = """
        {
            "boolean": true,
            "integer": 42,
            "double": 3.141592653589793,
            "string": "string",
            "array": [1, 2, 3],
            "nested": {
                "a": "alpha",
                "b": "bravo",
                "c": "charlie"
            },
            "someCodable": {
                "string":"String",
                "int":100,
                "bool": true,
                "has_underscore":"another string"
            },
            "null": null,
            "url": "https://example.com/image.png"
        }
        """.data(using: .utf8)!
        let expectedJSONObject = try JSONSerialization.jsonObject(with: expected, options: []) as! NSDictionary

        XCTAssertEqual(encodedJSONObject, expectedJSONObject)
    }

    func testEncodeNSNumber() throws {
        let dictionary: [String: NSNumber] = [
            "boolean": true,
            "char": -127,
            "int": -32_767,
            "short": -32_767,
            "long": -2_147_483_647,
            "longlong": -9_223_372_036_854_775_807,
            "uchar": 255,
            "uint": 65_535,
            "ushort": 65_535,
            "ulong": 4_294_967_295,
            "ulonglong": 18_446_744_073_709_615,
            "double": 3.141592653589793,
        ]

        let encoder = JSONEncoder()

        let json = try encoder.encode(AnyEncodable(dictionary))
        let encodedJSONObject = try JSONSerialization.jsonObject(with: json, options: []) as! NSDictionary

        let expected = """
        {
            "boolean": true,
            "char": -127,
            "int": -32767,
            "short": -32767,
            "long": -2147483647,
            "longlong": -9223372036854775807,
            "uchar": 255,
            "uint": 65535,
            "ushort": 65535,
            "ulong": 4294967295,
            "ulonglong": 18446744073709615,
            "double": 3.141592653589793,
        }
        """.data(using: .utf8)!
        let expectedJSONObject = try JSONSerialization.jsonObject(with: expected, options: []) as! NSDictionary

        XCTAssertEqual(encodedJSONObject, expectedJSONObject)
        XCTAssert(encodedJSONObject["boolean"] is Bool)

        XCTAssert(encodedJSONObject["char"] is Int8)
        XCTAssert(encodedJSONObject["int"] is Int16)
        XCTAssert(encodedJSONObject["short"] is Int32)
        XCTAssert(encodedJSONObject["long"] is Int32)
        XCTAssert(encodedJSONObject["longlong"] is Int64)

        XCTAssert(encodedJSONObject["uchar"] is UInt8)
        XCTAssert(encodedJSONObject["uint"] is UInt16)
        XCTAssert(encodedJSONObject["ushort"] is UInt32)
        XCTAssert(encodedJSONObject["ulong"] is UInt32)
        XCTAssert(encodedJSONObject["ulonglong"] is UInt64)

        XCTAssert(encodedJSONObject["double"] is Double)
    }

    func testStringInterpolationEncoding() throws {
        let dictionary: [String: Any] = [
            "boolean": "\(true)",
            "integer": "\(42)",
            "double": "\(3.141592653589793)",
            "string": "\("string")",
            "array": "\([1, 2, 3])",
        ]

        let encoder = JSONEncoder()

        let json = try encoder.encode(AnyEncodable(dictionary))
        let encodedJSONObject = try JSONSerialization.jsonObject(with: json, options: []) as! NSDictionary

        let expected = """
        {
            "boolean": "true",
            "integer": "42",
            "double": "3.141592653589793",
            "string": "string",
            "array": "[1, 2, 3]",
        }
        """.data(using: .utf8)!
        let expectedJSONObject = try JSONSerialization.jsonObject(with: expected, options: []) as! NSDictionary

        XCTAssertEqual(encodedJSONObject, expectedJSONObject)
    }
}
