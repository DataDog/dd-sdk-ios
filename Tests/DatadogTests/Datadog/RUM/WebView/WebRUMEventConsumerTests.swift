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
    let mockCommandSubscriber = RUMCommandSubscriberMock()
    let mockDateProvider = RelativeDateProvider(startingFrom: .mockDecember15th2019At10AMUTC(), advancingBySeconds: 0.0)

    func testWhenValidWebRUMEventPassed_itDecoratesAndPassesToWriter() throws {
        let mockSessionID = UUID(uuidString: "e9796469-c2a1-43d6-b0f6-65c47d33cf5f")!
        mockContextProvider.context.sessionID = RUMUUID(rawValue: mockSessionID)
        mockDateCorrector.correctionOffset = 123
        let eventConsumer = DefaultWebRUMEventConsumer(
            dataWriter: mockWriter,
            dateCorrector: mockDateCorrector,
            contextProvider: mockContextProvider,
            rumCommandSubscriber: mockCommandSubscriber,
            dateProvider: mockDateProvider
        )

        let webRUMEvent: JSON = [
            "_dd": [
                "session": ["plan": 2]
            ],
            "application": ["id": "75d50c62-8b66-403c-a453-aaa1c44d64bd"],
            "date": 1_640_252_823_292,
            "service": "shopist-web-ui",
            "session": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "view": [
                "id": "00413060-599f-4a77-80de-5d3beab3da2e"
            ],
            "type": "action"
        ]
        let expectedWebRUMEvent: JSON = [
            "_dd": [
                "session": ["plan": 1]
            ],
            "application": ["id": mockContextProvider.context.rumApplicationID],
            "date": 1_640_252_823_292 + 123.toInt64Milliseconds,
            "service": "shopist-web-ui",
            "session": ["id": mockContextProvider.context.sessionID.toRUMDataFormat],
            "view": [
                "id": "00413060-599f-4a77-80de-5d3beab3da2e"
            ],
            "type": "action"
        ]

        try eventConsumer.consume(event: webRUMEvent)

        let data = try JSONEncoder().encode(mockWriter.dataWritten as? CodableValue)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        AssertDictionariesEqual(writtenJSON, expectedWebRUMEvent)
        let webViewCommand = try XCTUnwrap(mockCommandSubscriber.lastReceivedCommand)
        XCTAssertEqual(webViewCommand.time, .mockDecember15th2019At10AMUTC())
    }

    func testWhenValidWebRUMEventPassedWithoutRUMContext_itPassesToWriter() throws {
        let eventConsumer = DefaultWebRUMEventConsumer(
            dataWriter: mockWriter,
            dateCorrector: mockDateCorrector,
            contextProvider: nil,
            rumCommandSubscriber: mockCommandSubscriber,
            dateProvider: mockDateProvider
        )

        let webRUMEvent: JSON = [
            "_dd": [
                "session": ["plan": 2]
            ],
            "application": ["id": "75d50c62-8b66-403c-a453-aaa1c44d64bd"],
            "date": 1_640_252_823_292,
            "service": "shopist-web-ui",
            "session": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "view": [
                "id": "00413060-599f-4a77-80de-5d3beab3da2e"
            ],
            "type": "action"
        ]

        try eventConsumer.consume(event: webRUMEvent)

        let data = try JSONEncoder().encode(mockWriter.dataWritten as? CodableValue)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        AssertDictionariesEqual(writtenJSON, webRUMEvent)
        let webViewCommand = try XCTUnwrap(mockCommandSubscriber.lastReceivedCommand)
        XCTAssertEqual(webViewCommand.time, .mockDecember15th2019At10AMUTC())
    }

    func testWhenNativeSessionIsSampledOut_itPassesWebEventToWriter() throws {
        mockContextProvider.context.sessionID = RUMUUID.nullUUID
        let eventConsumer = DefaultWebRUMEventConsumer(
            dataWriter: mockWriter,
            dateCorrector: mockDateCorrector,
            contextProvider: mockContextProvider,
            rumCommandSubscriber: mockCommandSubscriber,
            dateProvider: mockDateProvider
        )

        let webRUMEvent: JSON = [
            "new_key": "new_value",
            "type": "unknown"
        ]

        try eventConsumer.consume(event: webRUMEvent)

        let data = try JSONEncoder().encode(mockWriter.dataWritten as? CodableValue)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        AssertDictionariesEqual(writtenJSON, webRUMEvent)
        let webViewCommand = try XCTUnwrap(mockCommandSubscriber.lastReceivedCommand)
        XCTAssertEqual(webViewCommand.time, .mockDecember15th2019At10AMUTC())
    }

    func testWhenUnknownWebRUMEventPassed_itPassesToWriter() throws {
        let eventConsumer = DefaultWebRUMEventConsumer(
            dataWriter: mockWriter,
            dateCorrector: mockDateCorrector,
            contextProvider: mockContextProvider,
            rumCommandSubscriber: mockCommandSubscriber,
            dateProvider: mockDateProvider
        )

        let unknownWebRUMEvent: JSON = [
            "new_key": "new_value",
            "type": "unknown"
        ]

        try eventConsumer.consume(event: unknownWebRUMEvent)

        let data = try JSONEncoder().encode(mockWriter.dataWritten as? CodableValue)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        AssertDictionariesEqual(writtenJSON, unknownWebRUMEvent)
        let webViewCommand = try XCTUnwrap(mockCommandSubscriber.lastReceivedCommand)
        XCTAssertEqual(webViewCommand.time, .mockDecember15th2019At10AMUTC())
    }
}
