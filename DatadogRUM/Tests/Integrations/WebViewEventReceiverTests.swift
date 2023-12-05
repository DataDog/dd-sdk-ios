/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class WebViewEventReceiverTests: XCTestCase {
    /// Creates random RUM Browser event.
    /// Both mobile and browser events conform to the same schema, so we can consider mobile events browser-compatible.
    private func randomWebEvent() -> JSON { try! randomRUMEvent().toJSONObject() }

    /// Creates message sent from `DatadogWebViewTracking`.
    private func webViewTrackingMessage(with webEvent: JSON) -> FeatureMessage {
        return .baggage(
            key: WebViewEventReceiver.MessageKeys.browserEvent,
            value: AnyEncodable(webEvent)
        )
    }

    // MARK: - Handling `FeatureMessage`

    func testWhenReceivingWebViewTrackingMessageWithValidEvent_itAcknowledgesTheMessageAndKeepsRUMSessionAlive() throws {
        let core = PassthroughCoreMock()
        let commandsSubscriberMock = RUMCommandSubscriberMock()

        // Given
        let receiver = WebViewEventReceiver(
            dateProvider: DateProviderMock(now: .mockDecember15th2019At10AMUTC()),
            commandSubscriber: commandsSubscriberMock
        )

        // When
        let message = webViewTrackingMessage(with: randomWebEvent())
        let result = receiver.receive(message: message, from: core)

        // Then
        XCTAssertTrue(result, "It must acknowledge the message")
        let command = try XCTUnwrap(commandsSubscriberMock.receivedCommands.firstElement(of: RUMKeepSessionAliveCommand.self), "It must keep RUM session alive")
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
    }

    func testWhenReceivingWebViewTrackingMessageWithInvalidEvent_itRejectsTheMessageAndSendsErrorTelemetry() throws {
        let telemetryReceiver = TelemetryReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: telemetryReceiver)

        // Given
        let receiver = WebViewEventReceiver(
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock()
        )

        // When
        let invalidMessage: FeatureMessage = .baggage(key: WebViewEventReceiver.MessageKeys.browserEvent, value: "not a JSON object")
        let result = receiver.receive(message: invalidMessage, from: core)

        // Then
        XCTAssertFalse(result, "It must reject the message")
        let errorTelemetry = try XCTUnwrap(telemetryReceiver.messages.firstError(), "It must send error telemetry")
        XCTAssertEqual(errorTelemetry.message, "Fails to decode browser event from RUM - Event is not a dictionary")
    }

    func testWhenReceivingOtherMessage_itRejectsIt() throws {
        let core = PassthroughCoreMock()

        // Given
        let receiver = WebViewEventReceiver(
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock()
        )

        // When
        let otherMessage: FeatureMessage = .baggage(key: "message to other receiver", value: String.mockRandom())
        let result = receiver.receive(message: otherMessage, from: core)

        // Then
        XCTAssertFalse(result, "It must reject messages addressed to other receivers")
    }

    // MARK: - Modifying Web Events

    func testGivenRUMContextAvailable_whenReceivingWebEvent_itGetsEnrichedWithOtherMobileContextAndWritten() throws {
        let core = PassthroughCoreMock(
            context: .mockWith(serverTimeOffset: .mockRandom(min: -10, max: 10).rounded())
        )

        // Given
        let rumContext: RUMCoreContext = .mockRandom()
        core.set(baggage: rumContext, forKey: RUMFeature.name)

        let receiver = WebViewEventReceiver(
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock()
        )

        let random = mockRandomAttributes() // because below we only mock partial web event, we use this random to make the test fuzzy
        let webEventMock: JSON = [
            // Known properties:
            "_dd": ["browser_sdk_version": "5.2.0"],
            "application": ["id": String.mockRandom()],
            "session": ["id": String.mockRandom()],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": 1_000_000,
        ].merging(random, uniquingKeysWith: { old, _ in old })

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: core)

        // Then
        let expectedWebEventWritten: JSON = [
            // Known properties:
            "_dd": [
                "session": ["plan": 1],
                "browser_sdk_version": "5.2.0"
            ] as [String: Any],
            "application": ["id": rumContext.applicationID],
            "session": ["id": rumContext.sessionID],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": 1_000_000 + core.context.serverTimeOffset.toInt64Milliseconds,
        ].merging(random, uniquingKeysWith: { old, _ in old })

        XCTAssertTrue(result, "It must accept the message")
        XCTAssertEqual(core.events.count, 1, "It must write web event to core")
        let actualWebEventWritten = try XCTUnwrap(core.events.first)
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebEventWritten))
    }

    func testGivenRUMContextNotAvailable_whenReceivingWebEvent_itIsDropped() throws {
        let core = PassthroughCoreMock()

        // Given
        XCTAssertNil(core.context.baggages[RUMFeature.name])

        let receiver = WebViewEventReceiver(
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock()
        )

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: randomWebEvent()), from: core)

        // Then
        XCTAssertTrue(result, "It must accept the message")
        XCTAssertTrue(core.events.isEmpty, "The event must be dropped")
    }

    func testGivenInvalidRUMContext_whenReceivingEvent_itSendsErrorTelemetry() throws {
        struct InvalidRUMContext: Codable {
            var foo = "bar"
        }
        let telemetryReceiver = TelemetryReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: telemetryReceiver)

        // Given
        core.set(baggage: InvalidRUMContext(), forKey: RUMFeature.name)
        XCTAssertNotNil(core.context.baggages[RUMFeature.name])

        let receiver = WebViewEventReceiver(
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock()
        )

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: randomWebEvent()), from: core)

        // Then
        XCTAssertTrue(result, "It should accept the message")
        let errorTelemetry = try XCTUnwrap(telemetryReceiver.messages.firstError(), "It must send error telemetry")
        XCTAssertTrue(errorTelemetry.message.hasPrefix("Failed to decode `RUMCoreContext`"))
    }
}
