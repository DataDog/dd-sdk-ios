/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

private struct CodableObject: Codable, Equatable {
    let id: UUID
    let date: Date
    let url: URL
    let string: String
    let null: String?
    let integer: Int
    let float: Float
    let nested: Nested
    let empty: Empty
    let array: [Nested]

    struct Empty: Codable, Equatable { }

    struct Nested: Codable, Equatable {
        let id: UUID
        let string: String
    }
}

class AnyCoderTests: XCTestCase {
    func testEncodingDecoding() throws {
        let encoder = AnyEncoder()
        let decoder = AnyDecoder()

        // Given
        let expected: CodableObject = .mockRandom()

        // When
        let any = try encoder.encode(expected)
        let actual: CodableObject = try decoder.decode(from: any)

        // Then
        XCTAssertEqual(actual, expected)
    }

    func testSingleValueEncoding() throws {
        let encoder = AnyEncoder()
        XCTAssertTrue(try encoder.encode(true) is Bool)
        XCTAssertTrue(try encoder.encode("str") is String)
        XCTAssertTrue(try encoder.encode(Int(1)) is Int)
        XCTAssertTrue(try encoder.encode(Int8(1)) is Int8)
        XCTAssertTrue(try encoder.encode(Int16(1)) is Int16)
        XCTAssertTrue(try encoder.encode(Int32(1)) is Int32)
        XCTAssertTrue(try encoder.encode(Int64(1)) is Int64)
        XCTAssertTrue(try encoder.encode(UInt(1)) is UInt)
        XCTAssertTrue(try encoder.encode(UInt8(1)) is UInt8)
        XCTAssertTrue(try encoder.encode(UInt16(1)) is UInt16)
        XCTAssertTrue(try encoder.encode(UInt32(1)) is UInt32)
        XCTAssertTrue(try encoder.encode(UInt64(1)) is UInt64)
        XCTAssertTrue(try encoder.encode(Float(1.1)) is Float)
        XCTAssertTrue(try encoder.encode(Double(1.1)) is Double)
    }

    func testSingleValueDecoding() throws {
        let decoder = AnyDecoder()
        XCTAssertTrue(try decoder.decode(Bool.self, from: true))
        XCTAssertEqual(try decoder.decode(String.self, from: "str"), "str")
        XCTAssertEqual(try decoder.decode(Int.self, from: 1), 1)
        XCTAssertEqual(try decoder.decode(Int8.self, from: 1), 1)
        XCTAssertEqual(try decoder.decode(Int16.self, from: 1), 1)
        XCTAssertEqual(try decoder.decode(Int32.self, from: 1), 1)
        XCTAssertEqual(try decoder.decode(Int64.self, from: 1), 1)
        XCTAssertEqual(try decoder.decode(UInt.self, from: 1), 1)
        XCTAssertEqual(try decoder.decode(UInt8.self, from: 1), 1)
        XCTAssertEqual(try decoder.decode(UInt16.self, from: 1), 1)
        XCTAssertEqual(try decoder.decode(UInt32.self, from: 1), 1)
        XCTAssertEqual(try decoder.decode(UInt64.self, from: 1), 1)
        XCTAssertEqual(try decoder.decode(Float.self, from: Float(1)), 1)
        XCTAssertEqual(try decoder.decode(Float.self, from: Double(1)), 1)
        XCTAssertEqual(try decoder.decode(Float.self, from: Int(1)), 1)
        XCTAssertEqual(try decoder.decode(Double.self, from: Double(1)), 1)
        XCTAssertEqual(try decoder.decode(Double.self, from: Float(1)), 1)
        XCTAssertEqual(try decoder.decode(Double.self, from: Int(1)), 1)
    }

    func testUnkeyedEncoding() throws {
        let encoder = AnyEncoder()

        struct Foo: Encodable {
            func encode(to encoder: Encoder) throws {
                var container1 = encoder.unkeyedContainer()
                try container1.encodeNil()
                try container1.encode(true)
                try container1.encode("str")
                try container1.encode(Int(1))
                try container1.encode(Int8(1))
                try container1.encode(Int16(1))
                try container1.encode(Int32(1))
                var container2 = encoder.unkeyedContainer()
                try container2.encode(Int64(1))
                try container2.encode(UInt(1))
                try container2.encode(UInt8(1))
                try container2.encode(UInt16(1))
                try container2.encode(UInt32(1))
                try container2.encode(UInt64(1))
                try container2.encode(Float(1.1))
                try container2.encode(Double(1.1))
                var container3 = container2.nestedUnkeyedContainer()
                try container3.encode("str")
                var container4 = container2.nestedContainer(keyedBy: DynamicCodingKey.self)
                try container4.encode("str", forKey: "str")
                XCTAssertEqual(container2.count, 17)
            }
        }

        let array = try XCTUnwrap(try encoder.encode(Foo()) as? [Any?])
        XCTAssertNil(array[0])
        XCTAssertTrue(array[1] is Bool)
        XCTAssertTrue(array[2] is String)
        XCTAssertTrue(array[3] is Int)
        XCTAssertTrue(array[4] is Int8)
        XCTAssertTrue(array[5] is Int16)
        XCTAssertTrue(array[6] is Int32)
        XCTAssertTrue(array[7] is Int64)
        XCTAssertTrue(array[8] is UInt)
        XCTAssertTrue(array[9] is UInt8)
        XCTAssertTrue(array[10] is UInt16)
        XCTAssertTrue(array[11] is UInt32)
        XCTAssertTrue(array[12] is UInt64)
        XCTAssertTrue(array[13] is Float)
        XCTAssertTrue(array[14] is Double)
        XCTAssertTrue(array[15] is [String])
        XCTAssertTrue(array[16] is [String: String])
    }

    func testUnkeyedDecoding() throws {
        let decoder = AnyDecoder()

        let array: [Any?] = [
            nil,
            true,
            "str",
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
            1.1, 1.1,
            ["str"],
            ["str": "str"],
        ]

        struct Foo: Decodable {
            init(from decoder: Decoder) throws {
                XCTAssertThrowsError(try decoder.container(keyedBy: DynamicCodingKey.self))
                var container1 = try decoder.unkeyedContainer()
                XCTAssertEqual(container1.count, 17)
                XCTAssertTrue(try container1.decodeNil())
                XCTAssertTrue(try container1.decode(Bool.self))
                XCTAssertEqual(try container1.decode(String.self), "str")
                XCTAssertEqual(try container1.decode(Int.self), 1)
                XCTAssertEqual(try container1.decode(Int8.self), 1)
                XCTAssertEqual(try container1.decode(Int16.self), 1)
                XCTAssertEqual(try container1.decode(Int32.self), 1)
                XCTAssertEqual(try container1.decode(Int64.self), 1)
                XCTAssertEqual(try container1.decode(UInt.self), 1)
                XCTAssertEqual(try container1.decode(UInt8.self), 1)
                XCTAssertEqual(try container1.decode(UInt16.self), 1)
                XCTAssertEqual(try container1.decode(UInt32.self), 1)
                XCTAssertEqual(try container1.decode(UInt64.self), 1)
                XCTAssertEqual(try container1.decode(Float.self), 1.1)
                XCTAssertEqual(try container1.decode(Double.self), 1.1)
                var container2 = try container1.nestedUnkeyedContainer()
                XCTAssertEqual(try container2.decode(String.self), "str")
                let container3 = try container1.nestedContainer(keyedBy: DynamicCodingKey.self)
                XCTAssertEqual(try container3.decode(String.self, forKey: "str"), "str")
                XCTAssertThrowsError(try container1.decodeNil())
            }
        }

        XCTAssertNoThrow(try decoder.decode(Foo.self, from: array))
    }

    func testKeyedEncoding() throws {
        let encoder = AnyEncoder()

        struct Foo: Encodable {
            func encode(to encoder: Encoder) throws {
                var container1 = encoder.container(keyedBy: DynamicCodingKey.self)
                try container1.encodeNil(forKey: "null")
                try container1.encode(true, forKey: "bool")
                try container1.encode("str", forKey: "string")
                try container1.encode(Int(1), forKey: "int")
                try container1.encode(Int8(1), forKey: "int8")
                try container1.encode(Int16(1), forKey: "int16")
                try container1.encode(Int32(1), forKey: "int32")
                try container1.encode(Int64(1), forKey: "int64")
                var container2 = encoder.container(keyedBy: DynamicCodingKey.self)
                try container2.encode(UInt(1), forKey: "uint")
                try container2.encode(UInt8(1), forKey: "uint8")
                try container2.encode(UInt16(1), forKey: "uint16")
                try container2.encode(UInt32(1), forKey: "uint32")
                try container2.encode(UInt64(1), forKey: "uint64")
                try container2.encode(Float(1.1), forKey: "float")
                try container2.encode(Double(1.1), forKey: "double")
                var container3 = container2.nestedUnkeyedContainer(forKey: "array")
                try container3.encode("str")
                var container4 = container2.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: "nested")
                try container4.encode("str", forKey: "str")
            }
        }

        let dictionary = try XCTUnwrap(try encoder.encode(Foo()) as? [String: Any?])
        XCTAssertNil(try XCTUnwrap(dictionary["null"]))
        XCTAssertTrue(dictionary["bool"] is Bool)
        XCTAssertTrue(dictionary["string"] is String)
        XCTAssertTrue(dictionary["int"] is Int)
        XCTAssertTrue(dictionary["int8"] is Int8)
        XCTAssertTrue(dictionary["int16"] is Int16)
        XCTAssertTrue(dictionary["int32"] is Int32)
        XCTAssertTrue(dictionary["int64"] is Int64)
        XCTAssertTrue(dictionary["uint"] is UInt)
        XCTAssertTrue(dictionary["uint8"] is UInt8)
        XCTAssertTrue(dictionary["uint16"] is UInt16)
        XCTAssertTrue(dictionary["uint32"] is UInt32)
        XCTAssertTrue(dictionary["uint64"] is UInt64)
        XCTAssertTrue(dictionary["float"] is Float)
        XCTAssertTrue(dictionary["double"] is Double)
        XCTAssertTrue(dictionary["array"] is [String])
        XCTAssertTrue(dictionary["nested"] is [String: String])
    }

    func testKeyedDecoding() throws {
        let decoder = AnyDecoder()

        let dictionary: [String: Any?] = [
            "null": nil,
            "bool": true,
            "string": "str",
            "integer": 1,
            "floating": 1.1,
            "array": ["str"],
            "nested": ["str": "str"],
        ]

        struct Foo: Decodable {
            init(from decoder: Decoder) throws {
                XCTAssertThrowsError(try decoder.unkeyedContainer())
                let container1 = try decoder.container(keyedBy: DynamicCodingKey.self)
                XCTAssertEqual(container1.allKeys.count, 7)
                XCTAssertTrue(try container1.decodeNil(forKey: "null"))
                XCTAssertTrue(try container1.decode(Bool.self, forKey: "bool"))
                XCTAssertEqual(try container1.decode(String.self, forKey: "string"), "str")
                XCTAssertEqual(try container1.decode(Int.self, forKey: "integer"), 1)
                XCTAssertEqual(try container1.decode(Int8.self, forKey: "integer"), 1)
                XCTAssertEqual(try container1.decode(Int16.self, forKey: "integer"), 1)
                XCTAssertEqual(try container1.decode(Int32.self, forKey: "integer"), 1)
                XCTAssertEqual(try container1.decode(Int64.self, forKey: "integer"), 1)
                XCTAssertEqual(try container1.decode(UInt.self, forKey: "integer"), 1)
                XCTAssertEqual(try container1.decode(UInt8.self, forKey: "integer"), 1)
                XCTAssertEqual(try container1.decode(UInt16.self, forKey: "integer"), 1)
                XCTAssertEqual(try container1.decode(UInt32.self, forKey: "integer"), 1)
                XCTAssertEqual(try container1.decode(UInt64.self, forKey: "integer"), 1)
                XCTAssertEqual(try container1.decode(Float.self, forKey: "floating"), 1.1)
                XCTAssertEqual(try container1.decode(Double.self, forKey: "floating"), 1.1)
                var container2 = try container1.nestedUnkeyedContainer(forKey: "array")
                XCTAssertEqual(try container2.decode(String.self), "str")
                let container3 = try container1.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: "nested")
                XCTAssertEqual(try container3.decode(String.self, forKey: "str"), "str")
                XCTAssertThrowsError(try container1.decodeNil(forKey: "unkown"))
            }
        }

        XCTAssertNoThrow(try decoder.decode(Foo.self, from: dictionary))
    }
}

extension CodableObject: RandomMockable {
    static func mockRandom() -> Self {
        .init(
            id: .mockRandom(),
            date: .mockRandom(),
            url: .mockRandom(),
            string: .mockRandom(),
            null: nil,
            integer: .mockRandom(),
            float: .mockRandom(),
            nested: .mockRandom(),
            empty: .init(),
            array: .mockRandom()
        )
    }
}

extension CodableObject.Nested: RandomMockable {
    fileprivate static func mockRandom() -> Self {
        .init(id: .mockRandom(), string: .mockRandom())
    }
}
