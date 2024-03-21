/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@_spi(Internal)
@testable import DatadogSessionReplay

class WebViewSlotCacheTests: XCTestCase {
    func testAddingWebViewSlotToCache() {
        let cache = WebViewSlotCache()
        cache.update(WebViewSlotMock(id: 1))
        XCTAssertEqual(cache.slots.count, 1)
        cache.update(WebViewSlotMock(id: 2))
        XCTAssertEqual(cache.slots.count, 2)
        cache.update(WebViewSlotMock(id: 3))
        XCTAssertEqual(cache.slots.count, 3)
        cache.update(WebViewSlotMock(id: 3))
        XCTAssertEqual(cache.slots.count, 3, "cache slot should override existing slot")
    }

    func testPurgeViewSlotCache() {
        let cache = WebViewSlotCache()

        cache.update(WebViewSlotMock(id: 1))
        cache.update(WebViewSlotMock(id: 2))
        cache.update(WebViewSlotMock(id: 3))
        XCTAssertEqual(cache.slots.count, 3)
        cache.purge()
        XCTAssertEqual(cache.slots.count, 3)

        cache.update(WebViewSlotMock(id: 1))
        cache.update(WebViewSlotMock(id: 2, shouldPurge: true))
        cache.update(WebViewSlotMock(id: 3, shouldPurge: true))
        XCTAssertEqual(cache.slots.count, 3)
        cache.purge()
        XCTAssertEqual(cache.slots.count, 1)
        XCTAssertNotNil(cache.slots[1])

        cache.update(WebViewSlotMock(id: 1, shouldPurge: true))
        cache.purge()
        XCTAssertEqual(cache.slots.count, 0)
    }
}
