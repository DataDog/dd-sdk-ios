/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogWebViewTracking

class WebViewMessageTests: XCTestCase {
    func testParsingLogEvent() throws {
        // Given
        let eventString = """
        {
          "eventType": "log",
          "event": {
            "date": 1635932927012,
            "error": {
              "origin": "console"
            },
            "message": "console error: error",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "error",
            "view": {
              "referrer": "",
              "url": "https://datadoghq.dev/browser-sdk-test-playground"
            }
          },
          "tags": [
            "browser_sdk_version:3.6.13"
          ]
        }
        """

        // When
        let message = try WebViewMessage(body: eventString)

        // Then
        XCTAssertTrue(message.isLogEvent)
        let event = JSONObjectMatcher(object: message.json)
        XCTAssertEqual(try event.value("date"), 1635932927012)
        XCTAssertEqual(try event.value("error.origin"), "console")
        XCTAssertEqual(try event.value("message"), "console error: error")
        XCTAssertEqual(try event.value("session_id"), "0110cab4-7471-480e-aa4e-7ce039ced355")
        XCTAssertEqual(try event.value("status"), "error")
        XCTAssertEqual(try event.value("view.referrer"), "")
        XCTAssertEqual(try event.value("view.url"), "https://datadoghq.dev/browser-sdk-test-playground")
    }

    func testParsingRUMEvent() throws {
        // Given
        let eventString = """
        {
          "eventType": "view",
          "event": {
            "application": {
              "id": "xxx"
            },
            "date": 1635933113708,
            "service": "super",
            "session": {
              "id": "0110cab4-7471-480e-aa4e-7ce039ced355",
              "type": "user"
            },
            "type": "view",
            "view": {
              "action": {
                "count": 0
              },
              "cumulative_layout_shift": 0,
              "dom_complete": 152800000,
              "dom_content_loaded": 118300000,
              "dom_interactive": 116400000,
              "error": {
                "count": 0
              },
              "first_contentful_paint": 121300000,
              "id": "64308fd4-83f9-48cb-b3e1-1e91f6721230",
              "in_foreground_periods": [],
              "is_active": true,
              "largest_contentful_paint": 121299000,
              "load_event": 152800000,
              "loading_time": 152800000,
              "loading_type": "initial_load",
              "long_task": {
                "count": 0
              },
              "referrer": "",
              "resource": {
                "count": 3
              },
              "time_spent": 3120000000,
              "url": "http://localhost:8080/test.html"
            },
            "_dd": {
              "document_version": 2,
              "drift": 0,
              "format_version": 2,
              "session": {
                "plan": 2
              }
            }
          },
          "tags": [
            "browser_sdk_version:3.6.13"
          ]
        }
        """

        // When
        let message = try WebViewMessage(body: eventString)

        // Then
        XCTAssertTrue(message.isRUMEvent)
        let event = JSONObjectMatcher(object: message.json) // only partial matching
        XCTAssertEqual(try event.value("application.id"), "xxx")
        XCTAssertEqual(try event.value("date"), 1635933113708)
        XCTAssertEqual(try event.value("service"), "super")
        XCTAssertEqual(try event.value("session.id"), "0110cab4-7471-480e-aa4e-7ce039ced355")
        XCTAssertEqual(try event.value("session.type"), "user")
        XCTAssertEqual(try event.value("type"), "view")
        XCTAssertEqual(try event.value("view.action.count"), 0)
        XCTAssertEqual(try event.value("view.cumulative_layout_shift"), 0)
        XCTAssertEqual(try event.value("view.dom_complete"), 152800000)
        XCTAssertEqual(try event.value("view.dom_content_loaded"), 118300000)
        XCTAssertEqual(try event.value("view.dom_interactive"), 116400000)
        XCTAssertEqual(try event.value("view.error.count"), 0)
        XCTAssertEqual(try event.value("view.first_contentful_paint"), 121300000)
        XCTAssertEqual(try event.value("view.id"), "64308fd4-83f9-48cb-b3e1-1e91f6721230")
        XCTAssertEqual(try event.array("view.in_foreground_periods").count, 0)
        XCTAssertEqual(try event.value("view.is_active"), true)
        XCTAssertEqual(try event.value("view.largest_contentful_paint"), 121299000)
        XCTAssertEqual(try event.value("view.load_event"), 152800000)
        XCTAssertEqual(try event.value("view.loading_time"), 152800000)
        XCTAssertEqual(try event.value("view.loading_type"), "initial_load")
        XCTAssertEqual(try event.value("view.long_task.count"), 0)
        XCTAssertEqual(try event.value("view.referrer"), "")
        XCTAssertEqual(try event.value("view.resource.count"), 3)
        XCTAssertEqual(try event.value("view.time_spent"), 3120000000)
        XCTAssertEqual(try event.value("view.url"), "http://localhost:8080/test.html")
        XCTAssertEqual(try event.value("_dd.document_version"), 2)
        XCTAssertEqual(try event.value("_dd.drift"), 0)
        XCTAssertEqual(try event.value("_dd.format_version"), 2)
        XCTAssertEqual(try event.value("_dd.session.plan"), 2)
    }

    func testParsingCorruptedEvent() {
        let invalidJSON = "(^#$@#)"

        XCTAssertThrowsError(try WebViewMessage(body: invalidJSON)) { error in
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, NSPropertyListReadCorruptError)
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
        """
        let messageWithNoEvent = """
        {
            "eventType": "log"
        }
        """

        XCTAssertThrowsError(try WebViewMessage(body: messageWithNoEventType)) { error in
            XCTAssertEqual(error as? WebViewMessageError, .missingKey(key: "eventType"))
        }
        XCTAssertThrowsError(try WebViewMessage(body: messageWithNoEvent)) { error in
            XCTAssertEqual(error as? WebViewMessageError, .missingKey(key: "event"))
        }
    }
}

// MARK: - Convenience

internal extension WebViewMessage {
    var isLogEvent: Bool {
        switch self {
        case .log: return true
        default: return false
        }
    }

    var isRUMEvent: Bool {
        switch self {
        case .rum: return true
        default: return false
        }
    }

    var json: JSON {
        switch self {
        case let .log(json): return json
        case let .rum(json): return json
        }
    }
}
