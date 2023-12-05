/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogWebViewTracking

class MessageEmitterTests: XCTestCase {
    // MARK: - Routing

    func testGivenSampleRate100_whenReceivingLogEvent_itForwardsToLogs() throws {
        let sampler = Sampler(samplingRate: 100)
        let eventType = "log"

        // Given
        let receiverMock = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiverMock)
        let emitter = MessageEmitter(logsSampler: sampler, core: core)

        // When
        try emitter.send(body: """
        {
          "eventType": "\(eventType)",
          "event": {
            "attribute1": 123,
            "attribute2": "foo",
            "attribute3": ["foo", "bar", "bizz"]
          }
        }
        """)

        // Then
        let messageKey = MessageEmitter.MessageKeys.browserLog
        let message = try XCTUnwrap(receiverMock.messages.firstBaggage(withKey: messageKey))
        let json = JSONObjectMatcher(object: try message.encode() as! JSON)
        XCTAssertEqual(try json.value("attribute1"), 123)
        XCTAssertEqual(try json.value("attribute2"), "foo")
        XCTAssertEqual(try json.array("attribute3").values(), ["foo", "bar", "bizz"])
    }

    func testGivenSampleRate0_whenReceivingLogEvent_itIsDropped() throws {
        let sampler = Sampler(samplingRate: 0)
        let eventType = "log"

        // Given
        let receiverMock = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiverMock)
        let emitter = MessageEmitter(logsSampler: sampler, core: core)

        // When
        try emitter.send(body: """
        {
          "eventType": "\(eventType)",
          "event": {
            "attribute1": 123,
            "attribute2": "foo",
            "attribute3": ["foo", "bar", "bizz"]
          }
        }
        """)

        // Then
        let messageKey = MessageEmitter.MessageKeys.browserLog
        XCTAssertNil(receiverMock.messages.firstBaggage(withKey: messageKey))
    }

    func testWhenReceivingEventOtherThanLog_itForwardsToRUM() throws {
        let eventType: String = .mockRandom(otherThan: ["log"])

        // Given
        let receiverMock = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiverMock)
        let emitter = MessageEmitter(logsSampler: .mockRandom(), core: core)

        // When
        try emitter.send(body: """
        {
          "eventType": "\(eventType)",
          "event": {
            "attribute1": 123,
            "attribute2": "foo",
            "attribute3": ["foo", "bar", "bizz"]
          }
        }
        """)

        // Then
        let messageKey = MessageEmitter.MessageKeys.browserRUMEvent
        let message = try XCTUnwrap(receiverMock.messages.firstBaggage(withKey: messageKey))
        let json = JSONObjectMatcher(object: try message.encode() as! JSON)
        XCTAssertEqual(try json.value("attribute1"), 123)
        XCTAssertEqual(try json.value("attribute2"), "foo")
        XCTAssertEqual(try json.array("attribute3").values(), ["foo", "bar", "bizz"])
    }

    // MARK: - Parsing

    func testWhenMessageIsInvalid_itThrows() {
        let bridge = MessageEmitter(logsSampler: .mockAny(), core: PassthroughCoreMock())

        let messageInvalidJSON = """
        { 123: foobar }
        """

        XCTAssertThrowsError(
            try bridge.send(body: messageInvalidJSON),
            "Non-string keys (123) should throw"
        )
    }
}
