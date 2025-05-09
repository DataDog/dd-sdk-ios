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
    private let featureScope = FeatureScopeMock()
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

    func testParsingTelemetryEvent() throws {
        // Given
        let data = """
        {
          "eventType": "internal_telemetry",
          "event":
            {
              "type": "telemetry",
              "date": 1712069357432,
              "service": "browser-rum-sdk",
              "version": "5.2.0-b93ed472a4f14fbf2bcd1bc2c9faacb4abbeed82",
              "source": "browser",
              "_dd": { "format_version": 2 },
              "telemetry":
                {
                  "type": "configuration",
                  "configuration":
                    {
                      "session_replay_sample_rate": 100,
                      "use_allowed_tracing_urls": false,
                      "selected_tracing_propagators": [],
                      "default_privacy_level": "allow",
                      "use_excluded_activity_urls": false,
                      "use_worker_url": false,
                      "track_user_interactions": true,
                      "track_resources": true,
                      "track_long_task": true,
                      "session_sample_rate": 100,
                      "telemetry_sample_rate": 100,
                      "use_before_send": false,
                      "use_proxy": false,
                      "allow_fallback_to_local_storage": false,
                      "store_contexts_across_pages": false,
                      "allow_untrusted_events": false
                    },
                  "runtime_env": { "is_local_file": false, "is_worker": false }
                },
              "experimental_features": [],
              "application": { "id": "00000000-aaaa-0000-aaaa-000000000000" },
              "session": { "id": "00000000-aaaa-0000-aaaa-000000000000" },
              "view": {},
              "action": { "id": [] }
            }
        }
        """.utf8Data

        // When
        let decoder = JSONDecoder()
        let message = try decoder.decode(WebViewMessage.self, from: data)

        guard case let .telemetry(event) = message else {
            return XCTFail("not a telemetry message")
        }

        // Then
        let json = JSONObjectMatcher(object: event) // only partial matching
        XCTAssertEqual(try json.value("application.id"), "00000000-aaaa-0000-aaaa-000000000000")
        XCTAssertEqual(try json.value("date"), 1_712_069_357_432)
        XCTAssertEqual(try json.value("service"), "browser-rum-sdk")
        XCTAssertEqual(try json.value("session.id"), "00000000-aaaa-0000-aaaa-000000000000")
        XCTAssertEqual(try json.value("telemetry.type"), "configuration")
        XCTAssertEqual(try json.value("_dd.format_version"), 2)
    }

    func testWhenReceivingWebViewTrackingMessageWithValidEvent_itAcknowledgesTheMessageAndKeepsRUMSessionAlive() throws {
        let commandsSubscriberMock = RUMCommandSubscriberMock()

        // Given
        let receiver = WebViewEventReceiver(
            featureScope: featureScope,
            dateProvider: DateProviderMock(now: .mockDecember15th2019At10AMUTC()),
            commandSubscriber: commandsSubscriberMock,
            viewCache: ViewCache(dateProvider: SystemDateProvider())
        )

        // When
        let message = webViewTrackingMessage(with: randomWebEvent())
        let result = receiver.receive(message: message, from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result, "It must acknowledge the message")
        let command = try XCTUnwrap(commandsSubscriberMock.receivedCommands.firstElement(of: RUMKeepSessionAliveCommand.self), "It must keep RUM session alive")
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
    }

    func testWhenReceivingOtherMessage_itRejectsIt() throws {
        // Given
        let receiver = WebViewEventReceiver(
            featureScope: featureScope,
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache(dateProvider: SystemDateProvider())
        )

        // When
        let otherMessage: FeatureMessage = .payload(String.mockRandom())
        let result = receiver.receive(message: otherMessage, from: NOPDatadogCore())

        // Then
        XCTAssertFalse(result, "It must reject messages addressed to other receivers")
    }

    // MARK: - Modifying Web Events

    func testGivenRUMContextAvailable_whenReceivingWebEvent_itInjectRUMInfo() throws {
        // Given
        let dateProvider = RelativeDateProvider()
        let rumContext: RUMCoreContext = .mockRandom()
        featureScope.contextMock = .mockWith(
            additionalContext: [rumContext]
        )

        let receiver = WebViewEventReceiver(
            featureScope: featureScope,
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache(dateProvider: dateProvider)
        )

        dateProvider.advance(bySeconds: 1)
        let date = dateProvider.now.timeIntervalSince1970.toInt64Milliseconds
        let random = mockRandomAttributes() // because below we only mock partial web event, we use this random to make the test fuzzy
        let webEventMock: JSON = [
            // Known properties:
            "_dd": ["browser_sdk_version": "5.2.0"],
            "application": ["id": String.mockRandom()],
            "session": [
                "id": String.mockRandom(),
            ],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date),
        ].merging(random, uniquingKeysWith: { old, _ in old })

        // When

        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: NOPDatadogCore())

        // Then
        let expectedWebEventWritten: JSON = [
            // Known properties:
            "_dd": [
                "browser_sdk_version": "5.2.0"
            ] as [String: Any],
            "application": ["id": rumContext.applicationID],
            "session": [
                "id": rumContext.sessionID,
            ],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.toInt64Milliseconds,
        ].merging(random, uniquingKeysWith: { old, _ in old })

        XCTAssertTrue(result, "It must accept the message")
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "It must write web event to core")
        let actualWebEventWritten = try XCTUnwrap(featureScope.eventsWritten.first)
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebEventWritten))
    }

    func testGivenRUMContextNotAvailable_whenReceivingWebEvent_itIsDropped() throws {
        // Given
        XCTAssertNil(featureScope.contextMock.additionalContext(ofType: RUMCoreContext.self))

        let receiver = WebViewEventReceiver(
            featureScope: featureScope,
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache(dateProvider: SystemDateProvider())
        )

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: randomWebEvent()), from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result, "It must accept the message")
        XCTAssertTrue(featureScope.eventsWritten.isEmpty, "The event must be dropped")
    }

    func testGivenReplayContextAvailable_whenReceivingWebEvent_itInjectReplayInfo() throws {
        // Given
        let dateProvider = RelativeDateProvider()
        let rumContext: RUMCoreContext = .mockRandom()
        featureScope.contextMock = .mockWith(
            source: "react-native",
            additionalContext: [rumContext],
            baggages: [
                SessionReplayDependency.hasReplay: FeatureBaggage(true)
            ]
        )

        let receiver = WebViewEventReceiver(
            featureScope: featureScope,
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
        let webHasReplay: Bool = .mockRandom()
        let webEventMock: JSON = [
            // Known properties:
            "_dd": [
                "browser_sdk_version": "5.2.0",
                "replay_stats": RUMViewEvent.DD.ReplayStats(
                    recordsCount: 10,
                    segmentsCount: 1,
                    segmentsTotalRawSize: 10
                )
            ] as [String: Any],
            "application": ["id": String.mockRandom()],
            "session": [
                "id": String.mockRandom(),
                "has_replay": webHasReplay
            ] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date),
        ].merging(random, uniquingKeysWith: { old, _ in old })

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: NOPDatadogCore())

        // Then
        let expectedWebEventWritten: JSON = [
            // Known properties:
            "_dd": [
                "browser_sdk_version": "5.2.0",
                "replay_stats": [
                    "records_count": 10,
                    "segments_count": 1,
                    "segments_total_raw_size": 10
                ]
            ] as [String: Any],
            "container": [
                "source": "react-native",
                "view": [ "id": containerViewID ]
            ] as [String: Any],
            "application": ["id": rumContext.applicationID],
            "session": [
                "id": rumContext.sessionID,
                "has_replay": webHasReplay
            ] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.toInt64Milliseconds,
        ].merging(random, uniquingKeysWith: { old, _ in old })

        XCTAssertTrue(result, "It must accept the message")
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "It must write web event to core")
        let actualWebEventWritten = try XCTUnwrap(featureScope.eventsWritten.first)
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebEventWritten))
    }

    func testGivenReplayContextNotAvailable_whenReceivingWebEvent_itRemovesReplayInfo() throws {
        // Given
        let dateProvider = RelativeDateProvider()
        let rumContext: RUMCoreContext = .mockRandom()
        featureScope.contextMock = .mockWith(
            source: "react-native",
            additionalContext: [rumContext],
            baggages: [
                SessionReplayDependency.hasReplay: FeatureBaggage(false)
            ]
        )

        let receiver = WebViewEventReceiver(
            featureScope: featureScope,
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
            "_dd": [
                "browser_sdk_version": "5.2.0",
                "replay_stats": RUMViewEvent.DD.ReplayStats(
                    recordsCount: .mockRandom(),
                    segmentsCount: .mockRandom(),
                    segmentsTotalRawSize: .mockRandom()
                )
            ] as [String: Any],
            "application": ["id": String.mockRandom()],
            "session": [
                "id": String.mockRandom(),
                "has_replay": true
            ] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date),
        ].merging(random, uniquingKeysWith: { old, _ in old })

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: NOPDatadogCore())

        // Then
        let expectedWebEventWritten: JSON = [
            // Known properties:
            "_dd": [
                "browser_sdk_version": "5.2.0"
            ] as [String: Any],
            "container": [
                "source": "react-native",
                "view": [ "id": containerViewID ]
            ] as [String: Any],
            "application": ["id": rumContext.applicationID],
            "session": [
                "id": rumContext.sessionID,
                "has_replay": false
            ] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.toInt64Milliseconds,
        ].merging(random, uniquingKeysWith: { old, _ in old })

        XCTAssertTrue(result, "It must accept the message")
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "It must write web event to core")
        let actualWebEventWritten = try XCTUnwrap(featureScope.eventsWritten.first)
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebEventWritten))
    }
}
