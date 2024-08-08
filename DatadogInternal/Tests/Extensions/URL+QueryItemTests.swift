/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

final class URLQueryItemTests: XCTestCase {
    func testAppendQueryItem() {
        var url = URL(string: "https://example.com")!
        url.append(URLQueryItem(name: "key", value: "value"))
        XCTAssertEqual(url.absoluteString, "https://example.com?key=value")
    }

    func testAppendQueryItem_givenArrayQueryItems() {
        var url = URL(string: "https://example.com")!
        url.append([URLQueryItem(name: "key", value: "value1")])
        url.append([URLQueryItem(name: "key", value: "value2")])
        XCTAssertEqual(url.absoluteString, "https://example.com?key=value1&key=value2")
    }

    func testAppendQueryItems() {
        var url = URL(string: "https://example.com")!
        url.append([
            URLQueryItem(name: "key1", value: "value1"),
            URLQueryItem(name: "key2", value: "value2")
        ])
        XCTAssertEqual(url.absoluteString, "https://example.com?key1=value1&key2=value2")
    }

    func testQueryItem() {
        let url = URL(string: "https://example.com?key=value")!
        XCTAssertEqual(url.queryItem("key"), URLQueryItem(name: "key", value: "value"))
        XCTAssertNil(url.queryItem("non-existing-key"))
    }

    func testRemoveQueryItem() {
        var url = URL(string: "https://example.com?key=value")!
        url.removeQueryItem(name: "key")
        XCTAssertEqual(url.absoluteString, "https://example.com")
    }
}
