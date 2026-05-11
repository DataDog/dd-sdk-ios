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

        // Given
        let core = PassthroughCoreMock()
        var received: [WebViewLogMessage] = []
        _ = core.messageBus.subscribe { (msg: WebViewLogMessage, _) in received.append(msg) }
        let emitter = MessageEmitter(logsSampler: sampler, core: core)

        // When
        emitter.send(body: """
        {
          "eventType": "log",
          "event": {
            "attribute1": 123,
            "attribute2": "foo",
            "attribute3": ["foo", "bar", "bizz"]
          }
        }
        """)

        // Then
        let event = try XCTUnwrap(received.first?.event)
        let json = JSONObjectMatcher(object: event)
        XCTAssertEqual(try json.value("attribute1"), 123)
        XCTAssertEqual(try json.value("attribute2"), "foo")
        XCTAssertEqual(try json.array("attribute3").values(), ["foo", "bar", "bizz"])
    }

    func testGivenSampleRate0_whenReceivingLogEvent_itIsDropped() throws {
        let sampler = Sampler(samplingRate: 0)

        // Given
        let core = PassthroughCoreMock()
        var received: [WebViewLogMessage] = []
        _ = core.messageBus.subscribe { (msg: WebViewLogMessage, _) in received.append(msg) }
        let emitter = MessageEmitter(logsSampler: sampler, core: core)

        // When
        emitter.send(body: """
        {
          "eventType": "log",
          "event": {
            "attribute1": 123
          }
        }
        """)

        // Then
        XCTAssertTrue(received.isEmpty)
    }

    func testWhenReceivingRUMEvent_itForwardsToRUM() throws {
        // Given
        let core = PassthroughCoreMock()
        var received: [WebViewRUMMessage] = []
        _ = core.messageBus.subscribe { (msg: WebViewRUMMessage, _) in received.append(msg) }
        let emitter = MessageEmitter(logsSampler: .mockRandom(), core: core)

        // When
        emitter.send(body: """
        {
          "eventType": "rum",
          "event": {
            "attribute1": 123,
            "attribute2": "foo",
            "attribute3": ["foo", "bar", "bizz"]
          }
        }
        """)

        // Then
        let msg = try XCTUnwrap(received.first)
        XCTAssertEqual(msg.kind, .rum)
        let json = JSONObjectMatcher(object: msg.event)
        XCTAssertEqual(try json.value("attribute1"), 123)
        XCTAssertEqual(try json.value("attribute2"), "foo")
        XCTAssertEqual(try json.array("attribute3").values(), ["foo", "bar", "bizz"])
    }

    func testWhenReceivingTelemetryEvent_itForwardsToTelemetry() throws {
        // Given
        let core = PassthroughCoreMock()
        var received: [WebViewRUMMessage] = []
        _ = core.messageBus.subscribe { (msg: WebViewRUMMessage, _) in received.append(msg) }
        let emitter = MessageEmitter(logsSampler: .mockRandom(), core: core)

        // When
        emitter.send(body: """
        {
          "eventType": "internal_telemetry",
          "event": {
            "attribute1": 123,
            "attribute2": "foo",
            "attribute3": ["foo", "bar", "bizz"]
          }
        }
        """)

        // Then
        let msg = try XCTUnwrap(received.first)
        XCTAssertEqual(msg.kind, .telemetry)
        let json = JSONObjectMatcher(object: msg.event)
        XCTAssertEqual(try json.value("attribute1"), 123)
        XCTAssertEqual(try json.value("attribute2"), "foo")
        XCTAssertEqual(try json.array("attribute3").values(), ["foo", "bar", "bizz"])
    }

    // MARK: - Parsing

    func testWhenMessageIsInvalid_itReportTheError() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let telemetry = TelemetryReceiverMock()
        let core = PassthroughCoreMock()
        core.subscribe(receiver: telemetry)
        let bridge = MessageEmitter(logsSampler: .mockAny(), core: core)

        // When
        bridge.send(body: 123)

        // Then
        XCTAssertEqual(dd.logger.errorLog?.message, "Encountered an error when receiving web view event")
        XCTAssertEqual(dd.logger.errorLog?.error?.message, #"invalidMessage(description: "123")"#)
        XCTAssertEqual(telemetry.messages.first?.asError?.message, #"Encountered an error when receiving web view event - invalidMessage(description: "123")"#)
    }
}
