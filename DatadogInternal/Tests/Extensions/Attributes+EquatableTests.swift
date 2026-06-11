/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class AttributesEquatableTests: XCTestCase {
    func testScalarsEqual() {
        let a: [String: Encodable] = ["key": "value", "count": 42]
        let b: [String: Encodable] = ["key": "value", "count": 42]
        XCTAssertEqual(a.dd, b.dd)
    }

    func testScalarsNotEqual() {
        let a: [String: Encodable] = ["key": "value", "count": 42]
        let b: [String: Encodable] = ["key": "other", "count": 42]
        XCTAssertNotEqual(a.dd, b.dd)
    }

    func testDifferentCountNotEqual() {
        let a: [String: Encodable] = ["key": "value"]
        let b: [String: Encodable] = ["key": "value", "extra": 1]
        XCTAssertNotEqual(a.dd, b.dd)
    }

    func testNestedTypedArrayEqual() {
        let a: [String: Encodable] = ["tags": ["x", "y", "z"]]
        let b: [String: Encodable] = ["tags": ["x", "y", "z"]]
        XCTAssertEqual(a.dd, b.dd)
    }

    func testNestedTypedArrayNotEqual() {
        let a: [String: Encodable] = ["tags": ["x", "y", "z"]]
        let b: [String: Encodable] = ["tags": ["x", "y", "w"]]
        XCTAssertNotEqual(a.dd, b.dd)
    }

    func testNestedJSONDecodedObjectEqual() throws {
        let decoder = JSONDecoder()
        let json1 = try decoder.decode([String: AnyCodable].self, from: #"{"meta": {"env": "prod"}}"#.data(using: .utf8)!)
        let json2 = try decoder.decode([String: AnyCodable].self, from: #"{"meta": {"env": "prod"}}"#.data(using: .utf8)!)
        let a: [String: Encodable] = json1.mapValues { $0 as Encodable }
        let b: [String: Encodable] = json2.mapValues { $0 as Encodable }
        XCTAssertEqual(a.dd, b.dd)
    }

    func testOneSidedAnyCodableEqual() throws {
        let decoder = JSONDecoder()
        let json = try decoder.decode([String: AnyCodable].self, from: #"{"env": "prod"}"#.data(using: .utf8)!)
        let a: [String: Encodable] = json.mapValues { $0 as Encodable }
        let b: [String: Encodable] = ["env": "prod"]
        XCTAssertEqual(a.dd, b.dd)
    }

    func testAnyEncodableAttributesEqual() {
        let a: [String: Encodable] = ["key": "value", "count": 42].dd.swiftAttributes
        let b: [String: Encodable] = ["key": "value", "count": 42].dd.swiftAttributes
        XCTAssertEqual(a.dd, b.dd)
    }

    func testAnyEncodableAttributesNotEqual() {
        let a: [String: Encodable] = ["key": "value"].dd.swiftAttributes
        let b: [String: Encodable] = ["key": "other"].dd.swiftAttributes
        XCTAssertNotEqual(a.dd, b.dd)
    }

    func testNestedJSONDecodedObjectNotEqual() throws {
        let decoder = JSONDecoder()
        let json1 = try decoder.decode([String: AnyCodable].self, from: #"{"meta": {"env": "prod"}}"#.data(using: .utf8)!)
        let json2 = try decoder.decode([String: AnyCodable].self, from: #"{"meta": {"env": "staging"}}"#.data(using: .utf8)!)
        let a: [String: Encodable] = json1.mapValues { $0 as Encodable }
        let b: [String: Encodable] = json2.mapValues { $0 as Encodable }
        XCTAssertNotEqual(a.dd, b.dd)
    }
}
