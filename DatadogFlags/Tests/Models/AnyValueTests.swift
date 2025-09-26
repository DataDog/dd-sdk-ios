/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogFlags

final class AnyValueTests: XCTestCase {
    struct Model: Codable, Equatable {
        let value: AnyValue
    }

    func testDecodeString() throws {
        // Given
        let data = """
        {
          "value" : "lorem ipsum"
        }
        """.data(using: .utf8)!
        let expected = Model(value: .string("lorem ipsum"))

        // When
        let result = try JSONDecoder().decode(Model.self, from: data)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testEncodeString() throws {
        // Given
        let model = Model(value: .string("lorem ipsum"))
        let expected = """
        {
          "value" : "lorem ipsum"
        }
        """.data(using: .utf8)!
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        // When
        let result = try encoder.encode(model)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testDecodeBool() throws {
        // Given
        let data = """
        {
          "value" : true
        }
        """.data(using: .utf8)!
        let expected = Model(value: .bool(true))

        // When
        let result = try JSONDecoder().decode(Model.self, from: data)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testEncodeBool() throws {
        // Given
        let model = Model(value: .bool(true))
        let expected = """
        {
          "value" : true
        }
        """.data(using: .utf8)!
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        // When
        let result = try encoder.encode(model)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testDecodeInt() throws {
        // Given
        let data = """
        {
          "value" : 42
        }
        """.data(using: .utf8)!
        let expected = Model(value: .int(42))

        // When
        let result = try JSONDecoder().decode(Model.self, from: data)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testEncodeInt() throws {
        // Given
        let model = Model(value: .int(42))
        let expected = """
        {
          "value" : 42
        }
        """.data(using: .utf8)!
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        // When
        let result = try encoder.encode(model)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testDecodeDouble() throws {
        // Given
        let data = """
        {
          "value" : 3.141592
        }
        """.data(using: .utf8)!
        let expected = Model(value: .double(3.141592))

        // When
        let result = try JSONDecoder().decode(Model.self, from: data)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testEncodeDouble() throws {
        // Given
        let model = Model(value: .double(3))
        let expected = """
        {
          "value" : 3
        }
        """.data(using: .utf8)!
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        // When
        let result = try encoder.encode(model)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testDecodeDictionary() throws {
        // Given
        let data = """
        {
          "foo" : ["bar", "baz"],
          "object" : {
            "foo": 42
          }
        }
        """.data(using: .utf8)!
        let expected: AnyValue = .dictionary([
            "foo": .array([.string("bar"), .string("baz")]),
            "object": .dictionary(["foo": .int(42)]),
        ])

        // When
        let result = try JSONDecoder().decode(AnyValue.self, from: data)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testEncodeDictionary() throws {
        // Given
        let value: AnyValue = .dictionary([
            "foo": .array([.string("bar"), .string("baz")]),
            "object": .dictionary(["foo": .int(42)]),
        ])
        let expected = """
        {
          "foo" : [
            "bar",
            "baz"
          ],
          "object" : {
            "foo" : 42
          }
        }
        """.data(using: .utf8)!
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // When
        let result = try encoder.encode(value)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testDecodeArray() throws {
        // Given
        let data = """
        [
          true,
          {
            "foo" : "bar"
          }
        ]
        """.data(using: .utf8)!
        let expected: AnyValue = .array([
            .bool(true),
            .dictionary(["foo": .string("bar")]),
        ])

        // When
        let result = try JSONDecoder().decode(AnyValue.self, from: data)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testEncodeArray() throws {
        // Given
        let value: AnyValue = .array([
            .bool(true),
            .dictionary(["foo": .string("bar")]),
        ])
        let expected = """
        [
          true,
          {
            "foo" : "bar"
          }
        ]
        """.data(using: .utf8)!
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        // When
        let result = try encoder.encode(value)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testDecodeNull() throws {
        // Given
        let data = """
        {
          "value" : null
        }
        """.data(using: .utf8)!
        let expected = Model(value: .null)

        // When
        let result = try JSONDecoder().decode(Model.self, from: data)

        // Then
        XCTAssertEqual(expected, result)
    }

    func testEncodeNull() throws {
        // Given
        let model = Model(value: .null)
        let expected = """
        {
          "value" : null
        }
        """.data(using: .utf8)!
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        // When
        let result = try encoder.encode(model)

        // Then
        XCTAssertEqual(expected, result)
    }
}
