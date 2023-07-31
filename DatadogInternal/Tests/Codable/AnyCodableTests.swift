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
import TestUtilities

@testable import DatadogInternal

class AnyCodableTests: XCTestCase {
    struct SomeCodable: Codable {
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

    /// Sample struct used to test complex `Encodable` types encoding
    private struct Foo: Encodable, RandomMockable {
        var bar: String
        var bizz: Bizz

        struct Bizz: Encodable {
            var buzz: String
            var bazz: [Int: Int]
        }

        static func mockRandom() -> Foo {
            return Foo(
                bar: .mockRandom(),
                bizz: .init(
                    buzz: .mockRandom(),
                    bazz: [1: 2, 3: 4]
                )
            )
        }
    }

    func testJSONDecoding() throws {
        let json = """
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
            "null": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let dictionary = try decoder.decode([String: AnyCodable].self, from: json)

        XCTAssertEqual(dictionary["boolean"]?.value as! Bool, true)
        XCTAssertEqual(dictionary["integer"]?.value as! Int, 42)
        XCTAssertEqual(dictionary["double"]?.value as! Double, 3.141592653589793, accuracy: 0.001)
        XCTAssertEqual(dictionary["string"]?.value as! String, "string")
        XCTAssertEqual(dictionary["array"]?.value as! [Int], [1, 2, 3])
        XCTAssertEqual(dictionary["nested"]?.value as! [String: String], ["a": "alpha", "b": "bravo", "c": "charlie"])
        XCTAssertEqual(dictionary["null"]?.value as! NSNull, NSNull())
    }

    func testJSONDecodingEquatable() throws {
        let json = """
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
            "null": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let dictionary1 = try decoder.decode([String: AnyCodable].self, from: json)
        let dictionary2 = try decoder.decode([String: AnyCodable].self, from: json)

        XCTAssertEqual(dictionary1["boolean"], dictionary2["boolean"])
        XCTAssertEqual(dictionary1["integer"], dictionary2["integer"])
        XCTAssertEqual(dictionary1["double"], dictionary2["double"])
        XCTAssertEqual(dictionary1["string"], dictionary2["string"])
        XCTAssertEqual(dictionary1["array"], dictionary2["array"])
        XCTAssertEqual(dictionary1["nested"], dictionary2["nested"])
        XCTAssertEqual(dictionary1["null"], dictionary2["null"])
    }

    func testJSONEncoding() throws {
        let someCodable = AnyCodable(
            SomeCodable(
                string: "String",
                int: 100,
                bool: true,
                hasUnderscore: "another string"
            )
        )

        let injectedValue = 1_234
        let dictionary: [String: Any?] = [
            "boolean": true,
            "integer": 42,
            "double": 3.141592653589793,
            "string": "string",
            "stringInterpolation": "string \(injectedValue)",
            "array": [1, 2, 3],
            "nested": [
                "a": "alpha",
                "b": "bravo",
                "c": "charlie",
            ],
            "someCodable": someCodable,
            "null": nil
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
            "stringInterpolation": "string 1234",
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
            "null": null
        }
        """.data(using: .utf8)!
        let expectedJSONObject = try JSONSerialization.jsonObject(with: expected, options: []) as! NSDictionary

        XCTAssertEqual(encodedJSONObject, expectedJSONObject)
    }

    func testGivenEncodableValueWrappedIntoCodableValue_whenEncoding_itProducesExpectedJSONRepresentation() throws {
        let encoder = JSONEncoder()

        func json<T: Encodable>(for value: T) throws -> String {
            // Given
            let codableValue = AnyEncodable(value)

            // When
            let encodedCodableValue = try encoder.encode(codableValue)

            // Then
            return encodedCodableValue.utf8String
        }

        if #available(iOS 13.0, *) {
            XCTAssertEqual(try json(for: true), "true")
            XCTAssertEqual(try json(for: false), "false")
            XCTAssertEqual(try json(for: 123), "123")
            XCTAssertEqual(try json(for: -123), "-123")
            XCTAssertEqual(try json(for: 123.45), "123.45")
            XCTAssertEqual(try json(for: "string"), "\"string\"")

            let url = URL(string: "https://example.com/image.png")!
            XCTAssertEqual(try json(for: url), #""https:\/\/example.com\/image.png""#)

            // swiftlint:disable syntactic_sugar
            XCTAssertEqual(try json(for: Optional<Bool>.none), "null")
            XCTAssertEqual(try json(for: Optional<UInt64>.none), "null")
            XCTAssertEqual(try json(for: Optional<Int>.none), "null")
            XCTAssertEqual(try json(for: Optional<Double>.none), "null")
            XCTAssertEqual(try json(for: Optional<String>.none), "null")
            XCTAssertEqual(try json(for: Optional<URL>.none), "null")
            XCTAssertEqual(try json(for: Optional<Foo>.none), "null")
            // swiftlint:enable syntactic_sugar
        } else {
            XCTAssertEqual(try json(for: EncodingContainer(true)), #"{"value":true}"#)
            XCTAssertEqual(try json(for: EncodingContainer(false)), #"{"value":false}"#)
            XCTAssertEqual(try json(for: EncodingContainer(123)), #"{"value":123}"#)
            XCTAssertEqual(try json(for: EncodingContainer(-123)), #"{"value":-123}"#)
            XCTAssertEqual(try json(for: EncodingContainer(123.45)), #"{"value":123.45}"#)
            XCTAssertEqual(try json(for: EncodingContainer("string")), #"{"value":"string"}"#)

            let url = URL(string: "https://example.com/image.png")!
            XCTAssertEqual(try json(for: EncodingContainer(url)), #"{"value":"https:\/\/example.com\/image.png"}"#)

            // swiftlint:disable syntactic_sugar
            XCTAssertEqual(try json(for: EncodingContainer(Optional<Bool>.none)), #"{"value":null}"#)
            XCTAssertEqual(try json(for: EncodingContainer(Optional<UInt64>.none)), #"{"value":null}"#)
            XCTAssertEqual(try json(for: EncodingContainer(Optional<Int>.none)), #"{"value":null}"#)
            XCTAssertEqual(try json(for: EncodingContainer(Optional<Double>.none)), #"{"value":null}"#)
            XCTAssertEqual(try json(for: EncodingContainer(Optional<String>.none)), #"{"value":null}"#)
            XCTAssertEqual(try json(for: EncodingContainer(Optional<URL>.none)), #"{"value":null}"#)
            XCTAssertEqual(try json(for: EncodingContainer(Optional<Foo>.none)), #"{"value":null}"#)
            // swiftlint:enable syntactic_sugar
        }

        XCTAssertEqual(try json(for: [true, false, true, false]), "[true,false,true,false]")
        XCTAssertEqual(try json(for: [1, 2, 3, 4, 5]), "[1,2,3,4,5]")
        XCTAssertEqual(try json(for: [1.5, 2.5, 3.5]), "[1.5,2.5,3.5]")
        XCTAssertEqual(try json(for: ["foo", "bar", "fizz", "buzz"]), #"["foo","bar","fizz","buzz"]"#)

        let foo = Foo(bar: "bar", bizz: .init(buzz: "buzz", bazz: [1: 2]))
        XCTAssertEqual(try json(for: foo), #"{"bar":"bar","bizz":{"bazz":{"1":2},"buzz":"buzz"}}"#)
        XCTAssertEqual(try json(for: [foo]), #"[{"bar":"bar","bizz":{"bazz":{"1":2},"buzz":"buzz"}}]"#)
        XCTAssertEqual(try json(for: ["foo": foo]), #"{"foo":{"bar":"bar","bizz":{"bazz":{"1":2},"buzz":"buzz"}}}"#)
    }

    func testGivenEncodedCodableValue_whenDecoding_itPreservesValueRepresentation() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        func test<T: Encodable>(value: T) throws {
            // Given
            let codableValue = AnyEncodable(value)
            let encodedCodableValue = try encoder.encode(codableValue)

            // When
            let decodedCodableValue = try decoder.decode(AnyCodable.self, from: encodedCodableValue)

            // Then
            DDAssertJSONEqual(codableValue, decodedCodableValue)
        }

        try test(value: EncodingContainer(Bool.mockRandom()))
        try test(value: EncodingContainer(UInt64.mockRandom()))
        try test(value: EncodingContainer(Int.mockRandom()))
        try test(value: EncodingContainer(Double.mockRandom()))
        try test(value: EncodingContainer(String.mockRandom()))
        try test(value: EncodingContainer(URL.mockRandom()))
        try test(value: Foo.mockRandom())

        // swiftlint:disable syntactic_sugar
        try test(value: EncodingContainer(Optional<Bool>.none))
        try test(value: EncodingContainer(Optional<UInt64>.none))
        try test(value: EncodingContainer(Optional<Int>.none))
        try test(value: EncodingContainer(Optional<Double>.none))
        try test(value: EncodingContainer(Optional<String>.none))
        try test(value: EncodingContainer(Optional<URL>.none))
        try test(value: EncodingContainer(Optional<Foo>.none))
        // swiftlint:enable syntactic_sugar

        try test(value: [Bool].mockRandom())
        try test(value: [UInt64].mockRandom())
        try test(value: [Int].mockRandom())
        try test(value: [Double].mockRandom())
        try test(value: [String].mockRandom())
        try test(value: [URL].mockRandom())
        try test(value: [Foo].mockRandom())

        try test(value: [AttributeKey: Bool].mockRandom())
        try test(value: [AttributeKey: UInt64].mockRandom())
        try test(value: [AttributeKey: Int].mockRandom())
        try test(value: [AttributeKey: Double].mockRandom())
        try test(value: [AttributeKey: String].mockRandom())
        try test(value: [AttributeKey: URL].mockRandom())
        try test(value: [AttributeKey: Foo].mockRandom())
    }
}
