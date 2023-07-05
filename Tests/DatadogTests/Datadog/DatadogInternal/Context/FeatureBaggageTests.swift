/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import Datadog

class FeatureBaggageTests: XCTestCase {
    private enum EnumAttribute: String, Codable {
        case test
    }

    let attributes: FeatureBaggage = [
        "int": 1,
        "string": "test",
        "double": 2.0,
        "enum": EnumAttribute.test
    ]

    func testSubscript() {
        var attributes = attributes
        XCTAssertEqual(attributes["int", type: Int.self], 1)
        XCTAssertEqual(attributes["double", type: Double.self], 2.0)
        XCTAssertNil(attributes["string", type: Int.self])
        XCTAssertEqual(attributes["string"], "test")

        attributes["int"] = 2
        XCTAssertEqual(attributes["int"], 2)
    }

    func testRawRepresentable() {
        XCTAssertEqual(attributes["enum", type: EnumAttribute.self], .test)
        XCTAssertEqual(attributes["string", type: EnumAttribute.self], .test)
    }

    func testDynamicMemberLookup() {
        var attributes = attributes
        XCTAssertEqual(attributes.int, 1)
        XCTAssertEqual(attributes.double, 2.0)
        XCTAssertEqual(attributes.string, "test")
        XCTAssertEqual(attributes.string, EnumAttribute.test)
        XCTAssertEqual(attributes.enum, EnumAttribute.test)

        attributes.int = 2
        XCTAssertEqual(attributes.int, 2)
    }

    func testMerge() {
        var attributes = attributes
        attributes.merge(with: ["string": "test2"])

        XCTAssertEqual(attributes.int, 1)
        XCTAssertEqual(attributes.double, 2.0)
        XCTAssertEqual(attributes.string, "test2")
        XCTAssertEqual(attributes.enum, EnumAttribute.test)
    }
}
