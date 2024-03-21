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
        return .webview(.rum(webEvent))
    }

    // MARK: - Handling `FeatureMessage`

    func testParsingViewEvent() throws {
        // Given
        let data = """
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
        """.utf8Data

        // When
        let decoder = JSONDecoder()
        let message = try decoder.decode(WebViewMessage.self, from: data)

        guard case let .rum(event) = message else {
            return XCTFail("not a rum message")
        }

        // Then
        let json = JSONObjectMatcher(object: event) // only partial matching
        XCTAssertEqual(try json.value("application.id"), "xxx")
        XCTAssertEqual(try json.value("date"), 1_635_933_113_708)
        XCTAssertEqual(try json.value("service"), "super")
        XCTAssertEqual(try json.value("session.id"), "0110cab4-7471-480e-aa4e-7ce039ced355")
        XCTAssertEqual(try json.value("session.type"), "user")
        XCTAssertEqual(try json.value("type"), "view")
        XCTAssertEqual(try json.value("view.action.count"), 0)
        XCTAssertEqual(try json.value("view.cumulative_layout_shift"), 0)
        XCTAssertEqual(try json.value("view.dom_complete"), 152_800_000)
        XCTAssertEqual(try json.value("view.dom_content_loaded"), 118_300_000)
        XCTAssertEqual(try json.value("view.dom_interactive"), 116_400_000)
        XCTAssertEqual(try json.value("view.error.count"), 0)
        XCTAssertEqual(try json.value("view.first_contentful_paint"), 121_300_000)
        XCTAssertEqual(try json.value("view.id"), "64308fd4-83f9-48cb-b3e1-1e91f6721230")
        XCTAssertEqual(try json.array("view.in_foreground_periods").count, 0)
        XCTAssertEqual(try json.value("view.is_active"), true)
        XCTAssertEqual(try json.value("view.largest_contentful_paint"), 121_299_000)
        XCTAssertEqual(try json.value("view.load_event"), 152_800_000)
        XCTAssertEqual(try json.value("view.loading_time"), 152_800_000)
        XCTAssertEqual(try json.value("view.loading_type"), "initial_load")
        XCTAssertEqual(try json.value("view.long_task.count"), 0)
        XCTAssertEqual(try json.value("view.referrer"), "")
        XCTAssertEqual(try json.value("view.resource.count"), 3)
        XCTAssertEqual(try json.value("view.time_spent"), 3_120_000_000)
        XCTAssertEqual(try json.value("view.url"), "http://localhost:8080/test.html")
        XCTAssertEqual(try json.value("_dd.document_version"), 2)
        XCTAssertEqual(try json.value("_dd.drift"), 0)
        XCTAssertEqual(try json.value("_dd.format_version"), 2)
        XCTAssertEqual(try json.value("_dd.session.plan"), 2)
    }

    func testWhenReceivingWebViewTrackingMessageWithValidEvent_itAcknowledgesTheMessageAndKeepsRUMSessionAlive() throws {
        let core = PassthroughCoreMock()
        let commandsSubscriberMock = RUMCommandSubscriberMock()

        // Given
        let receiver = WebViewEventReceiver(
            dateProvider: DateProviderMock(now: .mockDecember15th2019At10AMUTC()),
            commandSubscriber: commandsSubscriberMock,
            viewCache: ViewCache()
        )

        // When
        let message = webViewTrackingMessage(with: randomWebEvent())
        let result = receiver.receive(message: message, from: core)

        // Then
        XCTAssertTrue(result, "It must acknowledge the message")
        let command = try XCTUnwrap(commandsSubscriberMock.receivedCommands.firstElement(of: RUMKeepSessionAliveCommand.self), "It must keep RUM session alive")
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
    }

    func testWhenReceivingOtherMessage_itRejectsIt() throws {
        let core = PassthroughCoreMock()

        // Given
        let receiver = WebViewEventReceiver(
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache()
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
            context: .mockWith(source: "react-native")
        )

        // Given
        let rumContext: RUMCoreContext = .mockRandom()
        core.set(baggage: rumContext, forKey: RUMFeature.name)
        let dateProvider = RelativeDateProvider()

        let receiver = WebViewEventReceiver(
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache(dateProvider: dateProvider)
        )

        let containerViewID: String = .mockRandom()
        receiver.viewCache.insert(
            id: containerViewID,
            timestamp: dateProvider.now.timeIntervalSince1970.toInt64Milliseconds,
            hasReplay: true
        )

        dateProvider.advance(bySeconds: 1)
        let date = dateProvider.now.timeIntervalSince1970.toInt64Milliseconds
        let random = mockRandomAttributes() // because below we only mock partial web event, we use this random to make the test fuzzy
        let webEventMock: JSON = [
            // Known properties:
            "_dd": ["browser_sdk_version": "5.2.0"],
            "application": ["id": String.mockRandom()],
            "session": ["id": String.mockRandom()],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date),
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
            "container": [
                "source": "react-native",
                "view": [ "id": containerViewID ]
            ] as [String: Any],
            "application": ["id": rumContext.applicationID],
            "session": ["id": rumContext.sessionID],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + core.context.serverTimeOffset.toInt64Milliseconds,
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
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache()
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
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache()
        )

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: randomWebEvent()), from: core)

        // Then
        XCTAssertTrue(result, "It should accept the message")
        let errorTelemetry = try XCTUnwrap(telemetryReceiver.messages.firstError(), "It must send error telemetry")
        XCTAssertTrue(errorTelemetry.message.hasPrefix("Failed to decode `RUMCoreContext`"))
    }
}
