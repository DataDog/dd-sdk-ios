/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogLogs

final class SynchronizedAttributesTests: XCTestCase {
    func testAddAttribute() {
        let synchronizedAttributes = SynchronizedAttributes(attributes: [:])
        synchronizedAttributes.addAttribute(key: "key1", value: "value1")

        let attributes = synchronizedAttributes.getAttributes()
        XCTAssertEqual(attributes["key1"] as? String, "value1")
        XCTAssertEqual(attributes.count, 1)
    }

    func testRemoveAttribute() {
        let synchronizedAttributes = SynchronizedAttributes(attributes: ["key1": "value1", "key2": "value2"])
        synchronizedAttributes.removeAttribute(forKey: "key1")

        let attributes = synchronizedAttributes.getAttributes()
        XCTAssertNil(attributes["key1"])
        XCTAssertEqual(attributes["key2"] as? String, "value2")
        XCTAssertEqual(attributes.count, 1)
    }

    func testGetAttributes() {
        let initialAttributes: [String: Encodable] = ["key1": "value1", "key2": "value2"]
        let synchronizedAttributes = SynchronizedAttributes(attributes: initialAttributes)

        let attributes = synchronizedAttributes.getAttributes()
        XCTAssertEqual(attributes.count, 2)
        XCTAssertEqual(attributes["key1"] as? String, "value1")
        XCTAssertEqual(attributes["key2"] as? String, "value2")
    }

    func testThreadSafety() {
        let synchronizedAttributes = SynchronizedAttributes(attributes: [:])

        callConcurrently(
            closures: [
                { idx in synchronizedAttributes.addAttribute(key: "key\(idx)", value: "value\(idx)") },
                { idx in synchronizedAttributes.removeAttribute(forKey: "unknown-key\(idx)") },
                { _ in _ = synchronizedAttributes.getAttributes() },
            ],
            iterations: 1_000
        )

        XCTAssertEqual(synchronizedAttributes.getAttributes().count, 1_000)
    }
}
