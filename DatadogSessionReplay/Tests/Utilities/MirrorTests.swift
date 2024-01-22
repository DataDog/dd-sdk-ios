/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

class MirrorTests: XCTestCase {
    func testItDoesSomething() {
        // 🐶

        let dictionay: [String: String] = ["test": "test"]
        let mirror = Mirror(reflecting: dictionay)

        print(mirror)
    }
}
