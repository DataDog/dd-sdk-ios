/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities

@testable import DatadogInternal

class WebViewMessageTests: XCTestCase {
    let decoder = JSONDecoder()

    func testParsingCorruptedEvent() throws {
        let invalidJSON = "(^#$@#)".utf8Data

        XCTAssertThrowsError(try decoder.decode(WebViewMessage.self, from: invalidJSON)) { error in
            XCTAssert(error is DecodingError)
        }
    }

    func testParsingInvalidEvent() {
        let messageWithNoEventType = """
        {
          "event": {
            "date": 1635932927012,
            "error": {
              "origin": "console"
            }
          }
        }
        """.utf8Data

        let messageWithNoEvent = """
        {
            "eventType": "log"
        }
        """.utf8Data

        XCTAssertThrowsError(try decoder.decode(WebViewMessage.self, from: messageWithNoEventType)) { error in
            XCTAssert(error is DecodingError)
        }

        XCTAssertThrowsError(try decoder.decode(WebViewMessage.self, from: messageWithNoEvent)) { error in
            XCTAssert(error is DecodingError)
        }
    }
}
