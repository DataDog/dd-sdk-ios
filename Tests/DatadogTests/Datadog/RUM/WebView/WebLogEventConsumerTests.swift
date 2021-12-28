/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class WebLogEventConsumerTests: XCTestCase {
    let mockUserLogsWriter = FileWriterMock()
    let mockInternalLogsWriter = FileWriterMock()
    let mockDateCorrector = DateCorrectorMock()
    let mockContextProvider = RUMContextProviderMock(context: .mockWith(rumApplicationID: "123456"))

    func testWhenValidWebLogEventPassed_itDecoratesAndPassesToWriter() throws {
        let mockSessionID = UUID(uuidString: "e9796469-c2a1-43d6-b0f6-65c47d33cf5f")!
        mockContextProvider.context.sessionID = RUMUUID(rawValue: mockSessionID)
        mockDateCorrector.correctionOffset = 123
        let applicationVersion = String.mockRandom()
        let environment = String.mockRandom()
        let eventConsumer = WebLogEventConsumer(
            userLogsWriter: mockUserLogsWriter,
            internalLogsWriter: mockInternalLogsWriter,
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
            "date": 1_635_932_927_012 + 123.toInt64Nanoseconds,
            "error": ["origin": "console"],
            "message": "console error: error",
            "application_id": "123456",
            "session_id": mockSessionID.uuidString.lowercased(),
            "status": "error",
            "ddtags": "version:\(applicationVersion),env:\(environment)",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]

        try eventConsumer.consume(event: webLogEvent, eventType: "log")

        let data = try JSONEncoder().encode(mockUserLogsWriter.dataWritten as? CodableValue)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        AssertDictionariesEqual(writtenJSON, expectedWebLogEvent)

        XCTAssertNil(mockInternalLogsWriter.dataWritten)
    }

    func testWhenValidWebInternalLogEventPassed_itDecoratesAndPassesToWriter() throws {
        let mockSessionID = UUID(uuidString: "e9796469-c2a1-43d6-b0f6-65c47d33cf5f")!
        mockContextProvider.context.sessionID = RUMUUID(rawValue: mockSessionID)
        mockDateCorrector.correctionOffset = 123
        let applicationVersion = String.mockRandom()
        let environment = String.mockRandom()
        let eventConsumer = WebLogEventConsumer(
            userLogsWriter: mockUserLogsWriter,
            internalLogsWriter: mockInternalLogsWriter,
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
            "date": 1_635_932_927_012 + 123.toInt64Nanoseconds,
            "error": ["origin": "console"],
            "message": "console error: error",
            "application_id": "123456",
            "session_id": mockSessionID.uuidString.lowercased(),
            "status": "error",
            "ddtags": "version:\(applicationVersion),env:\(environment)",
            "view": ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        ]

        try eventConsumer.consume(event: webLogEvent, eventType: "internal_log")

        let data = try JSONEncoder().encode(mockInternalLogsWriter.dataWritten as? CodableValue)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        AssertDictionariesEqual(writtenJSON, expectedWebLogEvent)

        XCTAssertNil(mockUserLogsWriter.dataWritten)
    }

    func testWhenInvalidEventTypePassed_itIgnoresEvent() throws {
        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }
        let userLoggerOutput = LogOutputMock()
        userLogger = .mockWith(logOutput: userLoggerOutput)

        let eventConsumer = WebLogEventConsumer(
            userLogsWriter: mockUserLogsWriter,
            internalLogsWriter: mockInternalLogsWriter,
            dateCorrector: mockDateCorrector,
            rumContextProvider: mockContextProvider,
            applicationVersion: .mockRandom(),
            environment: .mockRandom()
        )

        let webLogEvent: JSON = [
            "date": 1_635_932_927_012,
            "message": "console error: error",
            "status": "error"
        ]

        try eventConsumer.consume(event: webLogEvent, eventType: "invalid_log")

        XCTAssertNil(mockUserLogsWriter.dataWritten)
        XCTAssertNil(mockInternalLogsWriter.dataWritten)
        XCTAssertEqual(userLoggerOutput.recordedLog?.message, "🔥 Invalid Web Event Type: invalid_log")
    }

    func testWhenContextIsUnavailable_itPassesEventAsIs() throws {
        let applicationVersion = String.mockRandom()
        let environment = String.mockRandom()
        let eventConsumer = WebLogEventConsumer(
            userLogsWriter: mockUserLogsWriter,
            internalLogsWriter: mockInternalLogsWriter,
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

        try eventConsumer.consume(event: webLogEvent, eventType: "log")

        let data = try JSONEncoder().encode(mockUserLogsWriter.dataWritten as? CodableValue)
        let writtenJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: data, options: []) as? JSON)

        AssertDictionariesEqual(writtenJSON, expectedWebLogEvent)

        XCTAssertNil(mockInternalLogsWriter.dataWritten)
    }
}
