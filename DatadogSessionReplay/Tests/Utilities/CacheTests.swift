/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

class CacheTests: XCTestCase {
    func test_insertAndValueForKey() {
        let cache = Cache<String, Int>()
        cache.insert(1, forKey: "one")
        XCTAssertEqual(cache.value(forKey: "one"), 1)
    }

    func test_removeValueForKey() {
        let cache = Cache<String, Int>()
        cache.insert(1, forKey: "one")
        cache.removeValue(forKey: "one")
        XCTAssertNil(cache.value(forKey: "one"))
    }

    func test_subscript() {
        let cache = Cache<String, Int>()
        cache["one"] = 1
        XCTAssertEqual(cache["one"], 1)

        cache["one"] = nil
        XCTAssertNil(cache["one"])
    }

    func test_expiration() {
        let cache = Cache<String, Int>(dateProvider: {
            return Date(timeIntervalSinceReferenceDate: 0)
        }, entryLifetime: 0)

        cache.insert(1, forKey: "one")
        XCTAssertNil(cache.value(forKey: "one"))
    }

    func test_bytesLimit() {
        let cache = Cache<String, Int>(dateProvider: {
            return Date(timeIntervalSinceReferenceDate: 0)
        }, totalBytesLimit: 1)

        cache.insert(1, forKey: "one", size: 1)
        cache.insert(1, forKey: "two", size: 1)
        XCTAssertNil(cache.value(forKey: "one"))
        XCTAssertNotNil(cache.value(forKey: "two"))
    }

    func test_countLimit() {
        let cache = Cache<String, Int>(maximumEntryCount: 1)

        cache.insert(1, forKey: "one")
        cache.insert(2, forKey: "two")
        cache.insert(3, forKey: "three")
        XCTAssertNil(cache.value(forKey: "one"))
        XCTAssertNil(cache.value(forKey: "two"))
        XCTAssertEqual(cache.value(forKey: "three"), 3)
    }
}
