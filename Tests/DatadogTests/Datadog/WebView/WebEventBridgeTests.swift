/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog

class WebEventBridgeTests: XCTestCase {
    // MARK: - Parsing

    func testWhenMessageIsInvalid_itFailsParsing() {
        let bridge = WebEventBridge(core: PassthroughCoreMock())

        let messageInvalidJSON = """
        { 123: foobar }
        """

        XCTAssertThrowsError(
            try bridge.consume(messageInvalidJSON),
            "Non-string keys (123) should throw"
        )
    }

    // MARK: - Routing

    func testWhenEventTypeIsMissing_itThrows() {
        let bridge = WebEventBridge(core: PassthroughCoreMock())

        let messageMissingEventType = """
        {"event":{"date":1635932927012,"error":{"origin":"console"}}}
        """
        XCTAssertThrowsError(
            try bridge.consume(messageMissingEventType),
            "Missing eventType should throw"
        ) { error in
            XCTAssertEqual(
                error as? WebEventError,
                WebEventError.missingKey(key: WebEventBridge.Constants.eventTypeKey)
            )
        }
    }

    func testWhenEventTypeIsLog_itGoesToLogEventConsumer() throws {
        let core = PassthroughCoreMock(
            messageReceiver: WebViewLogReceiver()
        )

        let bridge = WebEventBridge(core: core)

        let messageLog = """
        {"eventType":"log","event":{"date":1635932927012,"error":{"origin":"console"},"message":"console error: error","session_id":"0110cab4-7471-480e-aa4e-7ce039ced355","status":"error","view":{"referrer":"","url":"https://datadoghq.dev/browser-sdk-test-playground"}},"tags":["browser_sdk_version:3.6.13"]}
        """
        try bridge.consume(messageLog)

        let event = try XCTUnwrap(core.events(ofType: AnyEncodable.self).first?.value as? JSON)
        XCTAssertEqual(event["session_id"] as? String, "0110cab4-7471-480e-aa4e-7ce039ced355")
        XCTAssertEqual((event["view"] as? JSON)?["url"] as? String, "https://datadoghq.dev/browser-sdk-test-playground")
    }

    func testWhenEventTypeIsNonLog_itGoesToRUMEventConsumer() throws {
        let core = PassthroughCoreMock(
            messageReceiver: WebViewEventReceiver.mockAny()
        )

        let bridge = WebEventBridge(core: core)

        let messageRUM = """
        {"eventType":"view","event":{"application":{"id":"xxx"},"date":1635933113708,"service":"super","session":{"id":"0110cab4-7471-480e-aa4e-7ce039ced355","type":"user"},"type":"view","view":{"action":{"count":0},"cumulative_layout_shift":0,"dom_complete":152800000,"dom_content_loaded":118300000,"dom_interactive":116400000,"error":{"count":0},"first_contentful_paint":121300000,"id":"64308fd4-83f9-48cb-b3e1-1e91f6721230","in_foreground_periods":[],"is_active":true,"largest_contentful_paint":121299000,"load_event":152800000,"loading_time":152800000,"loading_type":"initial_load","long_task":{"count":0},"referrer":"","resource":{"count":3},"time_spent":3120000000,"url":"http://localhost:8080/test.html"},"_dd":{"document_version":2,"drift":0,"format_version":2,"session":{"plan":2}}},"tags":["browser_sdk_version:3.6.13"]}
        """
        try bridge.consume(messageRUM)

        let event = try XCTUnwrap(core.events(ofType: AnyEncodable.self).first?.value as? JSON)
        XCTAssertEqual((event["session"] as? JSON)?["id"] as? String, "0110cab4-7471-480e-aa4e-7ce039ced355")
        XCTAssertEqual((event["view"] as? JSON)?["url"] as? String, "http://localhost:8080/test.html")
    }
}
