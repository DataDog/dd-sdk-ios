/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
import TestUtilities

@testable import DatadogInternal
@testable import DatadogSessionReplay

class WebViewRecordReceiverTests: XCTestCase {
    func testGivenRUMContextAvailable_whenReceivingWebRecord_itCreatesSegment() throws {
        let serverTimeOffset: TimeInterval = .mockRandom(min: -10, max: 10).rounded()

        let rumContext: RUMContext = .mockWith(
            serverTimeOffset: serverTimeOffset
        )

        let scope = FeatureScopeMock(
            context: .mockWith(
                source: "react-native",
                baggages: ["rum": FeatureBaggage(rumContext)]
            )
        )

        // Given
        let receiver = WebViewRecordReceiver(
            scope: scope
        )

        let random = mockRandomAttributes() // because below we only mock partial web event, we use this random to make the test fuzzy
        let webRecordMock: [String: Any] = [
            "timestamp": 100_000,
            "type": 2
        ].merging(random, uniquingKeysWith: { old, _ in old })

        let browserViewID: String = .mockRandom()

        // When

        let message = WebViewMessage.record(webRecordMock, WebViewMessage.View(id: browserViewID))
        let result = receiver.receive(message: .webview(message), from: NOPDatadogCore())

        // Then
        let expectedWebSegmentWritten: [String: Any] = [
            "applicationID": rumContext.applicationID,
            "sessionID": rumContext.sessionID,
            "viewID": browserViewID,
            "records": [
                [
                    "timestamp": 100_000 + serverTimeOffset.toInt64Milliseconds,
                    "type": 2
                ].merging(random, uniquingKeysWith: { old, _ in old })
            ]
        ]

        XCTAssertTrue(result, "It must accept the message")
        XCTAssertEqual(scope.eventsWritten.count, 1, "It must write web segment to core")
        let actualWebEventWritten = try XCTUnwrap(scope.eventsWritten.first)
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebSegmentWritten))
    }

    func testGivenRUMContextNotAvailable_whenReceivingWebRecord_itIsDropped() throws {
        let scope = FeatureScopeMock()

        // Given
        XCTAssertNil(scope.contextMock.baggages["rum"])

        let receiver = WebViewRecordReceiver(scope: scope)

        // When
        let record = WebViewMessage.record(mockRandomAttributes(), WebViewMessage.View(id: .mockRandom()))
        let result = receiver.receive(message: .webview(record), from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result, "It must accept the message")
        XCTAssertTrue(scope.eventsWritten.isEmpty, "The event must be dropped")
    }

    func testWhenReceivingOtherMessage_itRejectsIt() throws {
        let scope = FeatureScopeMock()

        // Given
        let receiver = WebViewRecordReceiver(scope: scope)

        // When
        let otherMessage: FeatureMessage = .baggage(key: "message to other receiver", value: String.mockRandom())
        let result = receiver.receive(message: otherMessage, from: NOPDatadogCore())

        // Then
        XCTAssertFalse(result, "It must reject messages addressed to other receivers")
    }

    func testWhenReceivingInvalidBaggage_itSendsTelemetryError() throws {
        // Given
        let telemetry = TelemetryReceiverMock()
        let scope = FeatureScopeMock(
            context: .mockWith(baggages: ["rum": FeatureBaggage(123)])
        )
        let core = PassthroughCoreMock(
            messageReceiver: telemetry
        )

        let receiver = WebViewRecordReceiver(scope: scope)

        // When
        let record = WebViewMessage.record(mockRandomAttributes(), WebViewMessage.View(id: .mockRandom()))
        XCTAssert(
            receiver.receive(message: .webview(record), from: core)
        )

        // Then
        let message = try XCTUnwrap(telemetry.messages.first?.asError?.message)
        XCTAssert(message.contains("Fails to decode RUM context from Session Replay - typeMismatch"))
    }
}

#endif
