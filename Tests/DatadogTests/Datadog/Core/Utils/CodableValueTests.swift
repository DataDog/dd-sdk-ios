/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class CodableValueTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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

    func testGivenEncodableValueWrappedIntoCodableValue_whenEncoding_itProducesExpectedJSONRepresentation() throws {
        func json<T: Encodable>(for value: T) throws -> String {
            // Given
            let codableValue = CodableValue(value)

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
        func test<T: Encodable>(value: T) throws {
            // Given
            let codableValue = CodableValue(value)
            let encodedCodableValue = try encoder.encode(codableValue)

            // When
            let decodedCodableValue = try decoder.decode(CodableValue.self, from: encodedCodableValue)

            // Then
            try AssertEncodedRepresentationsEqual(value1: codableValue, value2: decodedCodableValue)
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
