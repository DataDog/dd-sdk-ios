/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class WebLogEventConsumerTests: XCTestCase {
    let core = PassthroughCoreMock(
        messageReceiver: LoggingMessageReceiver(logEventMapper: nil)
    )

    let mockDateCorrector = DateCorrectorMock()
    let mockContextProvider = RUMContextProviderMock(context: .mockWith(rumApplicationID: "123456"))

    func testWhenValidWebLogEventPassed_itDecoratesAndPassesToWriter() throws {
        let mockSessionID: UUID = .mockRandom()
        mockContextProvider.context.sessionID = RUMUUID(rawValue: mockSessionID)
        mockDateCorrector.offset = 123
        let applicationVersion = String.mockRandom()
        let environment = String.mockRandom()
        let eventConsumer = DefaultWebLogEventConsumer(
            core: core,
            dateCorrector: mockDateCorrector,
            rumContextProvider: mockContextProvider,
            applicationVersion: applicationVersion,
            environment: environment
        )

        let webLogEvent: JSON = [
            "date": 1_635_932_927_012,
            "error": ["origin": "console"],
            "message": "console error: error",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "error",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]
        let expectedWebLogEvent: JSON = [
            "date": 1_635_932_927_012 + 123.toInt64Milliseconds,
            "error": ["origin": "console"],
            "message": "console error: error",
            "application_id": "123456",
            "session_id": mockSessionID.uuidString.lowercased(),
            "status": "error",
            "ddtags": "version:\(applicationVersion),env:\(environment)",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]

        try eventConsumer.consume(event: webLogEvent)

        let data = try JSONEncoder().encode(core.events.first as? AnyEncodable)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        AssertDictionariesEqual(writtenJSON, expectedWebLogEvent)
    }

    func testWhenContextIsUnavailable_itPassesEventAsIs() throws {
        let applicationVersion = String.mockRandom()
        let environment = String.mockRandom()
        let eventConsumer = DefaultWebLogEventConsumer(
            core: core,
            dateCorrector: mockDateCorrector,
            rumContextProvider: nil,
            applicationVersion: applicationVersion,
            environment: environment
        )

        let webLogEvent: JSON = [
            "date": 1_635_932_927_012,
            "error": ["origin": "console"],
            "message": "console error: error",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "error",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]
        var expectedWebLogEvent: JSON = webLogEvent
        expectedWebLogEvent["ddtags"] = "version:\(applicationVersion),env:\(environment)"

        try eventConsumer.consume(event: webLogEvent)

        let data = try JSONEncoder().encode(core.events.first as? AnyEncodable)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        AssertDictionariesEqual(writtenJSON, expectedWebLogEvent)
    }
}
