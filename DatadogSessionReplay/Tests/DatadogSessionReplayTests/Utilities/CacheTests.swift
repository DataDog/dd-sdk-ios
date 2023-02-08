/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

class CacheTests: XCTestCase {

    func test() {
        let cache = Cache<String, Int>()

        let key = "key1"
        let value = 1
        cache.insert(value, forKey: key)

        XCTAssertEqual(cache.value(forKey: key), value)
    }

    func test2() {
        let cache = Cache<String, Int>( 
            entryLifetime: 0
        )

        let key = "key1"
        cache.insert(1, forKey: key)

        XCTAssertNil(cache.value(forKey: key))
    }
}
