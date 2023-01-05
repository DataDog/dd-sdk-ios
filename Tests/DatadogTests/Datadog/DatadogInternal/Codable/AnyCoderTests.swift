/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class AnyCoderTests: XCTestCase {
    struct Object: Codable {
        let id: UUID
        let date: Date
        let url: URL
        let title: String
        let null: String?
        let int: Int?
        let bool: Bool?
        let nested: Nested
        let empty: Empty
        let array: [AnyCodable?]?

        struct Nested: Codable {
            let id: UUID
            let title: String
        }
    }

    struct Empty: Codable { }

    let id: UUID = .mockAny()

    lazy var dictionary: [String: Any?] = [
        "id": id,
        "date": Date.mockAny(),
        "url": URL(string: "https://test.com/object/1")!,
        "title": "Response",
        "int": UInt64(12_345),
        "bool": true,
        "nested": [
            "id": id,
            "title": "Nested",
        ],
        "empty": [:],
        "array": [
            1,
            "2",
            3.4,
            ["five": 5],
            nil
        ]
    ]

    func testObjectDecoding() throws {
        let decoder = AnyDecoder()
        let object = try decoder.decode(Object.self, from: dictionary)

        XCTAssertEqual(object.id, id)
        XCTAssertEqual(object.date, .mockAny())
        XCTAssertEqual(object.title, "Response")
        XCTAssertEqual(object.url, URL(string: "https://test.com/object/1"))
        XCTAssertNotNil(object.nested)
        XCTAssertEqual(object.nested.id, id)
        XCTAssertEqual(object.int, 12_345)
        XCTAssertNil(object.null)
        XCTAssertTrue(object.bool ?? false)
        XCTAssertNotNil(object.array)
        XCTAssertEqual(object.array?.underestimatedCount, 5)
        XCTAssertEqual(object.array?[0], AnyCodable(1))
    }

    func testObjectEncoding() throws {
        let encoder = AnyEncoder()
        let object = Object(
            id: id,
            date: .mockAny(),
            url: URL(string: "https://test.com/object/1")!,
            title: "Response",
            null: nil,
            int: 12_345,
            bool: true,
            nested: .init(id: id, title: "Nested"),
            empty: Empty(),
            array: [
                AnyCodable(1),
                AnyCodable("2"),
                AnyCodable(3.4),
                AnyCodable(["five": 5]),
                AnyCodable(nil as Any?)
            ]
        )

        let dict = try XCTUnwrap(encoder.encode(object) as? [String: Any?])

        XCTAssertEqual(dict["id"] as? UUID, id)
        XCTAssertEqual(dict["date"] as? Date, .mockAny())
        XCTAssertEqual(dict["title"] as? String, "Response")
        XCTAssertEqual(dict["url"] as? URL, URL(string: "https://test.com/object/1"))
        XCTAssertEqual(dict["int"] as? Int, 12_345)
        XCTAssertNil(dict["null"] as Any?)
        XCTAssertTrue(dict["bool"] as? Bool ?? false)
        let nested = try XCTUnwrap(dict["nested"] as? [String: Any?])
        XCTAssertEqual(nested["id"] as? UUID, id)
        XCTAssertEqual(nested["title"] as? String, "Nested")
        let array = try XCTUnwrap(dict["array"] as? [Any?])
        XCTAssertEqual(array.count, 5)
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
    }

    func testUnkeyedDecoding() throws {
        let decoder = AnyDecoder()

        let array: [Any?] = [
            nil,
            true,
            "str",
            1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
            1.1, 1.1
        ]

        struct Foo: Decodable {
            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                XCTAssertTrue(try container.decodeNil())
                XCTAssertTrue(try container.decode(Bool.self))
                XCTAssertEqual(try container.decode(String.self), "str")
                XCTAssertEqual(try container.decode(Int.self), 1)
                XCTAssertEqual(try container.decode(Int8.self), 1)
                XCTAssertEqual(try container.decode(Int16.self), 1)
                XCTAssertEqual(try container.decode(Int32.self), 1)
                XCTAssertEqual(try container.decode(Int64.self), 1)
                XCTAssertEqual(try container.decode(UInt.self), 1)
                XCTAssertEqual(try container.decode(UInt8.self), 1)
                XCTAssertEqual(try container.decode(UInt16.self), 1)
                XCTAssertEqual(try container.decode(UInt32.self), 1)
                XCTAssertEqual(try container.decode(UInt64.self), 1)
                XCTAssertEqual(try container.decode(Float.self), 1.1)
                XCTAssertEqual(try container.decode(Double.self), 1.1)
            }
        }

        XCTAssertNoThrow(try decoder.decode(Foo.self, from: array))
    }

    func testKeyedEncoding() throws {
        let encoder = AnyEncoder()

        struct Foo: Encodable {
            func encode(to encoder: Encoder) throws {
                var container1 = encoder.container(keyedBy: DynamicCodingKey.self)
                try container1.encodeNil(forKey: .init("null"))
                try container1.encode(true, forKey: .init("bool"))
                try container1.encode("str", forKey: .init("string"))
                try container1.encode(Int(1), forKey: .init("int"))
                try container1.encode(Int8(1), forKey: .init("int8"))
                try container1.encode(Int16(1), forKey: .init("int16"))
                try container1.encode(Int32(1), forKey: .init("int32"))
                try container1.encode(Int64(1), forKey: .init("int64"))
                var container2 = encoder.container(keyedBy: DynamicCodingKey.self)
                try container2.encode(UInt(1), forKey: .init("uint"))
                try container2.encode(UInt8(1), forKey: .init("uint8"))
                try container2.encode(UInt16(1), forKey: .init("uint16"))
                try container2.encode(UInt32(1), forKey: .init("uint32"))
                try container2.encode(UInt64(1), forKey: .init("uint64"))
                try container2.encode(Float(1.1), forKey: .init("float"))
                try container2.encode(Double(1.1), forKey: .init("double"))
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
    }

    func testKeyedDecoding() throws {
        let decoder = AnyDecoder()

        let dictionary: [String: Any?] = [
            "null": nil,
            "bool": true,
            "string": "str",
            "integer": 1,
            "floating": 1.1
        ]

        struct Foo: Decodable {
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: DynamicCodingKey.self)
                XCTAssertTrue(try container.decodeNil(forKey: .init("null")))
                XCTAssertTrue(try container.decode(Bool.self, forKey: .init("bool")))
                XCTAssertEqual(try container.decode(String.self, forKey: .init("string")), "str")
                XCTAssertEqual(try container.decode(Int.self, forKey: .init("integer")), 1)
                XCTAssertEqual(try container.decode(Int8.self, forKey: .init("integer")), 1)
                XCTAssertEqual(try container.decode(Int16.self, forKey: .init("integer")), 1)
                XCTAssertEqual(try container.decode(Int32.self, forKey: .init("integer")), 1)
                XCTAssertEqual(try container.decode(Int64.self, forKey: .init("integer")), 1)
                XCTAssertEqual(try container.decode(UInt.self, forKey: .init("integer")), 1)
                XCTAssertEqual(try container.decode(UInt8.self, forKey: .init("integer")), 1)
                XCTAssertEqual(try container.decode(UInt16.self, forKey: .init("integer")), 1)
                XCTAssertEqual(try container.decode(UInt32.self, forKey: .init("integer")), 1)
                XCTAssertEqual(try container.decode(UInt64.self, forKey: .init("integer")), 1)
                XCTAssertEqual(try container.decode(Float.self, forKey: .init("floating")), 1.1)
                XCTAssertEqual(try container.decode(Double.self, forKey: .init("floating")), 1.1)
            }
        }

        XCTAssertNoThrow(try decoder.decode(Foo.self, from: dictionary))
    }
}
