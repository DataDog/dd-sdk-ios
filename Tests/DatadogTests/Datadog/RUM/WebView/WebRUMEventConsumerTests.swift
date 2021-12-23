/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

// TODO: RUMM-1786 test mutations (session_id, application_id, date)
class WebRUMEventConsumerTests: XCTestCase {
    let mockWriter = FileWriterMock()
    let mockDateCorrector = DateCorrectorMock()
    let mockContextProvider = RUMContextProviderMock(context: .mockWith(rumApplicationID: "123456"))

    private func buildWebRUMViewEvent() -> JSON {
        return [
            "application": ["id": "xxx"],
            "date": 1_635_933_113_708,
            "service": "super",
            "session": ["id": "0110cab4-7471-480e-aa4e-7ce039ced355", "type": "user"],
            "type": "view",
            "view": [
                "action": ["count": 0],
                "cumulative_layout_shift": 0,
                "dom_complete": 152_800_000,
                "dom_content_loaded": 118_300_000,
                "dom_interactive": 116_400_000,
                "error": ["count": 0],
                "first_contentful_paint": 121_300_000,
                "id": "64308fd4-83f9-48cb-b3e1-1e91f6721230",
                "in_foreground_periods": [],
                "is_active": true,
                "largest_contentful_paint": 121_299_000,
                "load_event": 152_800_000,
                "loading_time": 152_800_000,
                "loading_type": "initial_load",
                "long_task": ["count": 0],
                "referrer": "",
                "resource": ["count": 3],
                "time_spent": 3_120_000_000,
                "url": "http://localhost:8080/test.html"
            ],
            "_dd": [
                "document_version": 2,
                "drift": 0,
                "format_version": 2,
                "session": ["plan": 2]
            ]
        ]
    }

    func testWhenValidWebRUMViewEventPassedWithWrongEventType_itThrowsError() throws {
        let mockSessionID = UUID(uuidString: "e9796469-c2a1-43d6-b0f6-65c47d33cf5f")!
        mockContextProvider.context.sessionID = RUMUUID(rawValue: mockSessionID)
        mockDateCorrector.correctionOffset = 123
        let eventConsumer = WebRUMEventConsumer(dataWriter: mockWriter, dateCorrector: mockDateCorrector, contextProvider: mockContextProvider)

        let webRUMViewEvent = buildWebRUMViewEvent()

        XCTAssertThrowsError(try eventConsumer.consume(event: webRUMViewEvent, eventType: "action"))
    }

    func testWhenValidWebRUMViewEventPassed_itDecoratesAndPassesToWriter() throws {
        let mockSessionID = UUID(uuidString: "e9796469-c2a1-43d6-b0f6-65c47d33cf5f")!
        mockContextProvider.context.sessionID = RUMUUID(rawValue: mockSessionID)
        mockDateCorrector.correctionOffset = 123
        let eventConsumer = WebRUMEventConsumer(dataWriter: mockWriter, dateCorrector: mockDateCorrector, contextProvider: mockContextProvider)

        let webRUMViewEvent = buildWebRUMViewEvent()
        try eventConsumer.consume(event: webRUMViewEvent, eventType: "view")

        let writtenRUMViewEvent = try XCTUnwrap(mockWriter.dataWritten as? RUMViewEvent)
        XCTAssertEqual(writtenRUMViewEvent.view.id, "64308fd4-83f9-48cb-b3e1-1e91f6721230")
        XCTAssertEqual(writtenRUMViewEvent.view.loadingTime, 152_800_000)
    }

    func testWhenValidWebRUMActionEventPassed_itDecoratesAndPassesToWriter() throws {
        let mockSessionID = UUID(uuidString: "e9796469-c2a1-43d6-b0f6-65c47d33cf5f")!
        mockContextProvider.context.sessionID = RUMUUID(rawValue: mockSessionID)
        mockDateCorrector.correctionOffset = 123
        let eventConsumer = WebRUMEventConsumer(dataWriter: mockWriter, dateCorrector: mockDateCorrector, contextProvider: mockContextProvider)

        let webRUMActionEvent: JSON = [
            "_dd": [
                "format_version": 2,
                "drift": 1,
                "session": ["plan": 2],
                "browser_sdk_version": "3.10.1"
            ],
            "application": ["id": "75d50c62-8b66-403c-a453-aaa1c44d64bd"],
            "date": 1_640_252_823_292,
            "service": "shopist-web-ui",
            "session": ["id": "00000000-aaaa-0000-aaaa-000000000000", "type": "user", "has_replay": true],
            "view": [
                "url": "https://foo.bar/department/chairs/product/2",
                "referrer": "https://foo.bar/department/chairs",
                "id": "00413060-599f-4a77-80de-5d3beab3da2e",
                "in_foreground": true
            ],
            "action": [
                "id": "e73c32c2-e748-4873-b621-debd7f674c0d",
                "target": ["name": "ADD TO CART"],
                "type": "click",
                "error": ["count": 0],
                "loading_time": 5_000_000,
                "long_task": ["count": 0],
                "resource": ["count": 0]
            ],
            "type": "action"
        ]

        try eventConsumer.consume(event: webRUMActionEvent, eventType: "action")

        let writtenRUMActionEvent = try XCTUnwrap(mockWriter.dataWritten as? RUMActionEvent)
        XCTAssertEqual(writtenRUMActionEvent.view.id, "00413060-599f-4a77-80de-5d3beab3da2e")
    }

    func testWhenValidWebRUMResourceEventPassed_itDecoratesAndPassesToWriter() throws {
        let mockSessionID = UUID(uuidString: "e9796469-c2a1-43d6-b0f6-65c47d33cf5f")!
        mockContextProvider.context.sessionID = RUMUUID(rawValue: mockSessionID)
        mockDateCorrector.correctionOffset = 123
        let eventConsumer = WebRUMEventConsumer(dataWriter: mockWriter, dateCorrector: mockDateCorrector, contextProvider: mockContextProvider)

        let webRUMResourceEvent: JSON = [
            "_dd": [
                "format_version": 2,
                "drift": 0,
                "session": ["plan": 2],
                "browser_sdk_version": "3.10.1"
            ],
            "application": ["id": "75d50c62-8b66-403c-a453-aaa1c44d64bd"],
            "date": 1_640_252_561_077,
            "service": "shopist-web-ui",
            "session": [
                "id": "00000000-aaaa-0000-aaaa-000000000000",
                "type": "user",
                "has_replay": true
            ],
            "view": [
                "url": "https://foo.bar/",
                "referrer": "",
                "id": "2aac5419-a626-4098-b1b5-39154f8ea8f3"
            ],
            "resource": [
                "id": "6df22efd-78b4-454f-b44f-3ac8846e5311",
                "type": "image",
                "url": "https://foo.bar/_nuxt/img/bedding.8af1600.jpg",
                "duration": 369_000_000,
                "download": ["duration": 351_000_000, "start": 18_000_000],
                "first_byte": ["duration": 17_000_000, "start": 1_000_000]
            ],
            "type": "resource"
        ]

        try eventConsumer.consume(event: webRUMResourceEvent, eventType: "resource")

        let writtenRUMResourceEvent = try XCTUnwrap(mockWriter.dataWritten as? RUMResourceEvent)
        XCTAssertEqual(writtenRUMResourceEvent.view.id, "2aac5419-a626-4098-b1b5-39154f8ea8f3")
    }

    func testWhenValidWebRUMErrorEventPassed_itDecoratesAndPassesToWriter() throws {
        let mockSessionID = UUID(uuidString: "e9796469-c2a1-43d6-b0f6-65c47d33cf5f")!
        mockContextProvider.context.sessionID = RUMUUID(rawValue: mockSessionID)
        mockDateCorrector.correctionOffset = 123
        let eventConsumer = WebRUMEventConsumer(dataWriter: mockWriter, dateCorrector: mockDateCorrector, contextProvider: mockContextProvider)

        let webRUMErrorEvent: JSON = [
            "_dd": [
                "format_version": 2,
                "drift": 0,
                "session": ["plan": 2],
                "browser_sdk_version": "3.10.1"
            ],
            "application": ["id": "75d50c62-8b66-403c-a453-aaa1c44d64bd"],
            "date": 1_640_252_666_129,
            "service": "shopist-web-ui",
            "session": [
                "id": "00000000-aaaa-0000-aaaa-000000000000",
                "type": "user",
                "has_replay": true
            ],
            "view": [
                "url": "https://foo.bar/department/chairs/product/2",
                "referrer": "https://foo.bar/department/chairs",
                "id": "00413060-599f-4a77-80de-5d3beab3da2e",
                "in_foreground": true
            ],
            "error": [
                "id": "3de88670-be12-4a30-91c8-378f8ccb8a75",
                "message": "Provided [\"type\":\"network error\",\"status\":404]",
                "source": "custom",
                "stack": "No stack, consider using an instance of Error",
                "handling_stack": "Error: \n  at <anonymous> @ https://foo.bar/_nuxt/app.30bb4c9.js:2:47460\n  at promiseReactionJob @ [native code]",
                "handling": "handled"
            ],
            "type": "error"
        ]

        try eventConsumer.consume(event: webRUMErrorEvent, eventType: "error")

        let writtenRUMErrorEvent = try XCTUnwrap(mockWriter.dataWritten as? RUMErrorEvent)
        XCTAssertEqual(writtenRUMErrorEvent.view.id, "00413060-599f-4a77-80de-5d3beab3da2e")
    }

    func testWhenInvalidEventTypeIsPassed_itLogsToUserLogger() throws {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }
        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        let eventConsumer = WebRUMEventConsumer(dataWriter: mockWriter, dateCorrector: mockDateCorrector, contextProvider: mockContextProvider)
        try eventConsumer.consume(event: [:], eventType: "unknown_event_type")

        XCTAssertEqual(output.recordedLog?.status, .error)
        let userLogMessage = try XCTUnwrap(output.recordedLog?.message)
        XCTAssertEqual(userLogMessage, "🔥 Web RUM Event Error - Unknown event type: unknown_event_type")
    }
}
