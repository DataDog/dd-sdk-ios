/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogLogs

class LoggingBenchmarkTests: BenchmarkTests {
    private let message = "foobar-message"

    func testCreatingOneLog() {
        let logger = Logger.create()

        measure {
            logger.info(message)
        }
    }

    func testCreatingOneLogWithAttributes() {
        let logger = Logger.create()
        (0..<16).forEach { index in
            logger.addAttribute(forKey: "a\(index)", value: "v\(index)")
        }

        measure {
            logger.info(message)
        }
    }

    func testCreatingOneLogWithTags() {
        let logger = Logger.create()
        (0..<8).forEach { index in
            logger.addTag(withKey: "t\(index)", value: "v\(index)")
        }

        measure {
            logger.info(message)
        }
    }
}
