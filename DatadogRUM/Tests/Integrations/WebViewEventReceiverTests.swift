/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import TestUtilities
@_spi(Internal)
import DatadogInternal
@testable import DatadogRUM
@testable import DatadogCore

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
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
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
                "is_main_process": true
            ] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.dd.toInt64Milliseconds,
            "ddtags": featureScope.contextMock.ddTags,
        ].merging(random, uniquingKeysWith: { old, _ in old })

        XCTAssertTrue(result, "It must accept the message")
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "It must write web event to core")
        let actualWebEventWritten = try XCTUnwrap(featureScope.eventsWritten.first)
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebEventWritten))
    }

    func testGivenBrowserTagsAvailable_whenReceivingWebEvent_itMergesWithNativeDDTags() throws {
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
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        let webEventMock: JSON = [
            "application": ["id": String.mockRandom()],
            "session": ["id": String.mockRandom()],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date),
            // Browser SDK sends its own tag alongside a key that collides with a native one:
            "ddtags": "browser_sdk_version:3.6.13,sdk_version:5.2.0"
        ]

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: NOPDatadogCore())

        // Then
        let expectedWebEventWritten: JSON = [
            "application": ["id": rumContext.applicationID],
            "session": ["id": rumContext.sessionID, "is_main_process": true] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.dd.toInt64Milliseconds,
            "ddtags": "browser_sdk_version:3.6.13,env:abc,sdk_version:5.2.0,service:abc,version:abc"
        ]

        XCTAssertTrue(result, "It must accept the message")
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "It must write web event to core")
        let actualWebEventWritten = try XCTUnwrap(featureScope.eventsWritten.first)
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebEventWritten))
    }

    func testGivenNoBrowserTags_whenReceivingWebEvent_itSetsNativeDDTags() throws {
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
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        let webEventMock: JSON = [
            "application": ["id": String.mockRandom()],
            "session": ["id": String.mockRandom()],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date)
        ]

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: NOPDatadogCore())

        // Then
        let expectedWebEventWritten: JSON = [
            "application": ["id": rumContext.applicationID],
            "session": ["id": rumContext.sessionID, "is_main_process": true] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.dd.toInt64Milliseconds,
            "ddtags": featureScope.contextMock.ddTags
        ]

        XCTAssertTrue(result, "It must accept the message")
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "It must write web event to core")
        let actualWebEventWritten = try XCTUnwrap(featureScope.eventsWritten.first)
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebEventWritten))
    }

    func testGivenAppExtensionContext_whenReceivingWebEvent_itSetsIsMainProcessFalse() throws {
        // Given
        let dateProvider = RelativeDateProvider()
        let rumContext: RUMCoreContext = .mockRandom()
        featureScope.contextMock = .mockWith(
            applicationBundleType: .iOSAppExtension,
            additionalContext: [rumContext]
        )

        let receiver = WebViewEventReceiver(
            featureScope: featureScope,
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache(dateProvider: dateProvider)
        )

        dateProvider.advance(bySeconds: 1)
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        let webEventMock: JSON = [
            "application": ["id": String.mockRandom()],
            "session": ["id": String.mockRandom()],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date)
        ]

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: NOPDatadogCore())

        // Then
        let expectedWebEventWritten: JSON = [
            "application": ["id": rumContext.applicationID],
            "session": ["id": rumContext.sessionID, "is_main_process": false] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.dd.toInt64Milliseconds,
            "ddtags": featureScope.contextMock.ddTags
        ]

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
            additionalContext: [
                rumContext,
                SessionReplayCoreContext.HasReplay(value: true)
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
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            hasReplay: true
        )

        dateProvider.advance(bySeconds: 1)
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
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
                "has_replay": webHasReplay,
                "is_main_process": true
            ] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.dd.toInt64Milliseconds,
            "ddtags": featureScope.contextMock.ddTags,
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
            additionalContext: [
                rumContext,
                SessionReplayCoreContext.HasReplay(value: false)
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
            timestamp: dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds,
            hasReplay: true
        )

        dateProvider.advance(bySeconds: 1)
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
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
                "has_replay": false,
                "is_main_process": true
            ] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.dd.toInt64Milliseconds,
            "ddtags": featureScope.contextMock.ddTags,
        ].merging(random, uniquingKeysWith: { old, _ in old })

        XCTAssertTrue(result, "It must accept the message")
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "It must write web event to core")
        let actualWebEventWritten = try XCTUnwrap(featureScope.eventsWritten.first)
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebEventWritten))
    }

    // MARK: - Anonymous ID Propagation

    func testGivenAnonymousIdAvailable_whenReceivingWebEventWithExistingUsr_itAddsAnonymousIdAndPreservesWebFields() throws {
        // Given
        let dateProvider = RelativeDateProvider()
        let fakeAnonymousId: String = .mockRandom()
        let webUsrId: String = .mockRandom()
        let webUsrName: String = .mockRandom()
        let rumContext: RUMCoreContext = .mockRandom()
        featureScope.contextMock = .mockWith(
            userInfo: UserInfo(anonymousId: fakeAnonymousId),
            additionalContext: [rumContext]
        )

        let receiver = WebViewEventReceiver(
            featureScope: featureScope,
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache(dateProvider: dateProvider)
        )

        dateProvider.advance(bySeconds: 1)
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        let webEventMock: JSON = [
            "application": ["id": String.mockRandom()],
            "session": ["id": String.mockRandom()],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date),
            "usr": [
                "id": webUsrId,
                "name": webUsrName
            ]
        ]

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(featureScope.eventsWritten.count, 1, "It must write web event to core")
        let actualWebEventWritten = try XCTUnwrap(featureScope.eventsWritten.first)
        let expectedWebEventWritten: JSON = [
            "application": ["id": rumContext.applicationID],
            "session": ["id": rumContext.sessionID, "is_main_process": true] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.dd.toInt64Milliseconds,
            "ddtags": featureScope.contextMock.ddTags,
            "usr": [
                "id": webUsrId,
                "name": webUsrName,
                "anonymous_id": fakeAnonymousId
            ]
        ]
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebEventWritten))
    }

    func testGivenAnonymousIdAlreadySetByBrowser_whenReceivingWebEvent_itOverwritesWithNativeValue() throws {
        // Given
        let dateProvider = RelativeDateProvider()
        let nativeAnonymousId: String = .mockRandom()
        let browserAnonymousId: String = .mockRandom()
        let rumContext: RUMCoreContext = .mockRandom()
        featureScope.contextMock = .mockWith(
            userInfo: UserInfo(anonymousId: nativeAnonymousId),
            additionalContext: [rumContext]
        )

        let receiver = WebViewEventReceiver(
            featureScope: featureScope,
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache(dateProvider: dateProvider)
        )

        dateProvider.advance(bySeconds: 1)
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        let webEventMock: JSON = [
            "application": ["id": String.mockRandom()],
            "session": ["id": String.mockRandom()],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date),
            "usr": ["anonymous_id": browserAnonymousId]
        ]

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(featureScope.eventsWritten.count, 1)
        let actualWebEventWritten = try XCTUnwrap(featureScope.eventsWritten.first)
        let expectedWebEventWritten: JSON = [
            "application": ["id": rumContext.applicationID],
            "session": ["id": rumContext.sessionID, "is_main_process": true] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.dd.toInt64Milliseconds,
            "ddtags": featureScope.contextMock.ddTags,
            "usr": ["anonymous_id": nativeAnonymousId]
        ]
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebEventWritten))
    }

    // MARK: - First Party Host Sampling Rate (rule_psr)

    func testGivenFirstPartyHostSamplingRate_whenReceivingTracedResourceEvent_itOverwritesRulePsr() throws {
        // Given
        let dateProvider = RelativeDateProvider()
        // This session ID is not sampled at 50%, but it is sampled at 60%:
        let sessionUUID = RUMUUID(rawValue: UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!)
        let uuidGenerator = RUMUUIDGeneratorMock(uuid: sessionUUID)

        let core = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.0.0",
                serverTimeOffset: 0
            )
        )
        defer { try? core.flushAndTearDown() }

        let nativeSamplingRate: SampleRate = 75.0

        RUM.enable(
            with: .mockWith(applicationID: "test-app-id") {
                $0.uuidGenerator = uuidGenerator
                $0.urlSessionTracking = .init(
                    firstPartyHostsTracing: .trace(hosts: ["localhost"], sampleRate: nativeSamplingRate)
                )
            },
            in: core
        )

        // Necessary for RUM to set the session sampler in the feature, since it's an async process.
        Thread.sleep(forTimeInterval: 0.1)

        let receiver = WebViewEventReceiver(
            featureScope: core.scope(for: RUMFeature.self),
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache(dateProvider: dateProvider)
        )

        dateProvider.advance(bySeconds: 1)
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        let webEventMock: JSON = [
            "type": "resource",
            "_dd": [
                "browser_sdk_version": "6.32.0",
                "trace_id": "123456789",
                "span_id": "987654321",
                "rule_psr": 1.0
            ] as [String: Any],
            "application": ["id": String.mockRandom()],
            "session": ["id": String.mockRandom()],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date),
        ]

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: core)

        // Then
        XCTAssertTrue(result)
        let events = core.waitAndReturnEvents(ofFeature: "rum", ofType: AnyEncodable.self)
        let actualWebEventWritten = try XCTUnwrap((events.first)?.value as? [String: Any])
        let actualDD = try XCTUnwrap(actualWebEventWritten["_dd"] as? [String: Any])
        XCTAssertEqual(actualDD["rule_psr"] as? Float, Float(nativeSamplingRate.percentageProportion), "rule_psr must be overwritten with the native sampling rate")
        XCTAssertEqual(actualDD["trace_id"] as? String, "123456789", "trace_id must be preserved")
        XCTAssertEqual(actualDD["span_id"] as? String, "987654321", "span_id must be preserved")
    }

    func testGivenFirstPartyHostSamplingRate_whenReceivingResourceEventWithoutRulePsr_itDoesNotAddRulePsr() throws {
        // Given
        // Given
        let dateProvider = RelativeDateProvider()
        // This session ID is not sampled at 50%, but it is sampled at 60%:
        let sessionUUID = RUMUUID(rawValue: UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!)
        let uuidGenerator = RUMUUIDGeneratorMock(uuid: sessionUUID)

        let core = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.0.0",
                serverTimeOffset: 0
            )
        )
        defer { try? core.flushAndTearDown() }

        let nativeSamplingRate: SampleRate = 75.0

        RUM.enable(
            with: .mockWith(applicationID: "test-app-id") {
                $0.uuidGenerator = uuidGenerator
                $0.urlSessionTracking = .init(
                    firstPartyHostsTracing: .trace(hosts: ["localhost"], sampleRate: nativeSamplingRate)
                )
            },
            in: core
        )

        // Necessary for RUM to set the session sampler in the feature, since it's an async process.
        Thread.sleep(forTimeInterval: 0.1)

        let receiver = WebViewEventReceiver(
            featureScope: core.scope(for: RUMFeature.self),
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache(dateProvider: dateProvider)
        )

        dateProvider.advance(bySeconds: 1)
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        let webEventMock: JSON = [
            "type": "resource",
            "_dd": [
                "browser_sdk_version": "6.32.0"
            ] as [String: Any],
            "application": ["id": String.mockRandom()],
            "session": ["id": String.mockRandom()],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date),
        ]

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: core)

        // Then
        XCTAssertTrue(result)
        let events = core.waitAndReturnEvents(ofFeature: "rum", ofType: AnyEncodable.self)
        let actualWebEventWritten = try XCTUnwrap((events.first)?.value as? [String: Any])
        let actualDD = try XCTUnwrap(actualWebEventWritten["_dd"] as? [String: Any])
        XCTAssertNil(actualDD["rule_psr"], "rule_psr should not have been created")
        XCTAssertNil(actualDD["trace_id"])
        XCTAssertNil(actualDD["span_id"])
    }

    func testGivenNoFirstPartyHostSamplingRate_whenReceivingTracedResourceEvent_itDoesNotModifyRulePsr() throws {
        // Given
        let dateProvider = RelativeDateProvider()
        // This session ID is not sampled at 50%, but it is sampled at 60%:
        let sessionUUID = RUMUUID(rawValue: UUID(uuidString: "c5b3c4ab-fa4a-4de9-8199-a522131ec48a")!)
        let uuidGenerator = RUMUUIDGeneratorMock(uuid: sessionUUID)

        let core = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.0.0",
                serverTimeOffset: 0
            )
        )
        defer { try? core.flushAndTearDown() }

        RUM.enable(
            with: .mockWith(applicationID: "test-app-id") {
                $0.uuidGenerator = uuidGenerator
            },
            in: core
        )

        // Necessary for RUM to set the session sampler in the feature, since it's an async process.
        Thread.sleep(forTimeInterval: 1.0)

        let receiver = WebViewEventReceiver(
            featureScope: core.scope(for: RUMFeature.self),
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache(dateProvider: dateProvider)
        )

        dateProvider.advance(bySeconds: 1)
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        let originalRulePsr: Float = 1.0
        let webEventMock: JSON = [
            "type": "resource",
            "_dd": [
                "browser_sdk_version": "6.32.0",
                "trace_id": "123456789",
                "span_id": "987654321",
                "rule_psr": originalRulePsr
            ] as [String: Any],
            "application": ["id": String.mockRandom()],
            "session": ["id": String.mockRandom()],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date),
        ]

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result)
        let events = core.waitAndReturnEvents(ofFeature: "rum", ofType: AnyEncodable.self)
        let actualWebEventWritten = try XCTUnwrap((events.first)?.value as? [String: Any])
        let actualDD = try XCTUnwrap(actualWebEventWritten["_dd"] as? [String: Any])
        XCTAssertEqual(actualDD["rule_psr"] as? Float, originalRulePsr, "rule_psr must be overwritten")
        XCTAssertEqual(actualDD["trace_id"] as? String, "123456789", "trace_id must be preserved")
        XCTAssertEqual(actualDD["span_id"] as? String, "987654321", "span_id must be preserved")
    }

    // MARK: - Anonymous ID Propagation

    func testGivenAnonymousIdAvailable_whenReceivingWebEventWithNoUsr_itAddsAnonymousId() throws {
        // Given
        let dateProvider = RelativeDateProvider()
        let fakeAnonymousId: String = .mockRandom()
        let rumContext: RUMCoreContext = .mockRandom()
        featureScope.contextMock = .mockWith(
            userInfo: UserInfo(anonymousId: fakeAnonymousId),
            additionalContext: [rumContext]
        )

        let receiver = WebViewEventReceiver(
            featureScope: featureScope,
            dateProvider: DateProviderMock(),
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: ViewCache(dateProvider: dateProvider)
        )

        dateProvider.advance(bySeconds: 1)
        let date = dateProvider.now.timeIntervalSince1970.dd.toInt64Milliseconds
        let webEventMock: JSON = [
            "application": ["id": String.mockRandom()],
            "session": ["id": String.mockRandom()],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": Int(date)
        ]

        // When
        let result = receiver.receive(message: webViewTrackingMessage(with: webEventMock), from: NOPDatadogCore())

        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(featureScope.eventsWritten.count, 1)
        let actualWebEventWritten = try XCTUnwrap(featureScope.eventsWritten.first)
        let expectedWebEventWritten: JSON = [
            "application": ["id": rumContext.applicationID],
            "session": ["id": rumContext.sessionID, "is_main_process": true] as [String: Any],
            "view": ["id": "00000000-aaaa-0000-aaaa-000000000000"],
            "date": date + featureScope.contextMock.serverTimeOffset.dd.toInt64Milliseconds,
            "ddtags": featureScope.contextMock.ddTags,
            "usr": ["anonymous_id": fakeAnonymousId]
        ]
        DDAssertJSONEqual(AnyCodable(actualWebEventWritten), AnyCodable(expectedWebEventWritten))
    }

    func testGivenLongLivedNativeView_whenDelayedWebEventArrivesAfterNavigation_itRetainsOriginalContainer() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let inactiveTTL: TimeInterval = 10
        let dateProvider = DateProviderMock(now: start)
        let viewCache = ViewCache(dateProvider: dateProvider, ttl: inactiveTTL)
        let sessionContext: DatadogContext = .mockWith(
            serverTimeOffset: 0,
            additionalContext: [SessionReplayCoreContext.HasReplay(value: true)]
        )
        let parent = RUMApplicationScope(
            dependencies: .mockWith(rumApplicationID: "rum-207")
        )
        let scope: RUMSessionScope = .mockWith(
            parent: parent,
            startTime: start,
            context: sessionContext,
            dependencies: .mockWith(
                rumApplicationID: "rum-207",
                samplingRate: 100,
                viewCache: viewCache
            )
        )
        let writer = FileWriterMock()

        dateProvider.now = start
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: start,
                identity: ViewIdentifier("A"),
                name: "A",
                path: "A"
            ),
            context: sessionContext,
            writer: writer
        )
        let viewAID = try XCTUnwrap(scope.viewScopes.last).viewUUID.toRUMDataFormat

        let navigation = start.addingTimeInterval(100)
        dateProvider.now = navigation
        _ = scope.process(
            command: RUMStartViewCommand.mockWith(
                time: navigation,
                identity: ViewIdentifier("B"),
                name: "B",
                path: "B"
            ),
            context: sessionContext,
            writer: writer
        )
        let viewBID = try XCTUnwrap(scope.viewScopes.last).viewUUID.toRUMDataFormat

        dateProvider.now = navigation.addingTimeInterval(inactiveTTL - 0.01)
        let rumContext = RUMCoreContext.mockWith(
            applicationID: "rum-207",
            sessionID: scope.context.sessionID.rawValue,
            sessionSampleRate: 100,
            viewID: viewBID,
            serverTimeOffset: 0
        )
        featureScope.contextMock = .mockWith(
            source: "react-native",
            serverTimeOffset: 0,
            additionalContext: [
                rumContext,
                SessionReplayCoreContext.HasReplay(value: true)
            ]
        )
        let receiver = WebViewEventReceiver(
            featureScope: featureScope,
            dateProvider: dateProvider,
            commandSubscriber: RUMCommandSubscriberMock(),
            viewCache: viewCache
        )
        let delayedDate = navigation.timeIntervalSince1970.dd.toInt64Milliseconds - 1
        let webEvent: JSON = [
            "application": ["id": "browser-app"],
            "session": ["id": "browser-session", "has_replay": true],
            "view": ["id": "browser-view"],
            "date": Int(delayedDate)
        ]

        XCTAssertTrue(receiver.receive(message: webViewTrackingMessage(with: webEvent), from: NOPDatadogCore()))
        XCTAssertEqual(featureScope.eventsWritten.count, 1)
        let actual = try XCTUnwrap(featureScope.eventsWritten.first)
        let actualJSON = try AnyCodable(actual).toJSONObject()

        DDAssertJSONEqual(actualJSON["application"], ["id": "rum-207"] as JSON)
        DDAssertJSONEqual(actualJSON["session"], ["id": rumContext.sessionID, "has_replay": true, "is_main_process": true] as JSON)
        DDAssertJSONEqual(actualJSON["view"], ["id": "browser-view"] as JSON)
        DDAssertJSONEqual(actualJSON["date"], delayedDate)
        DDAssertJSONEqual(actualJSON["ddtags"], featureScope.contextMock.ddTags)

        let actualContainer = try XCTUnwrap(actualJSON["container"] as? JSON)
        let expectedContainer: JSON = [
            "source": "react-native",
            "view": ["id": viewAID]
        ]
        DDAssertJSONEqual(actualContainer, expectedContainer)
        withExtendedLifetime(parent) {}
    }
    func testCapturedMessage_keepsOriginalSceneAcrossDeferredWrite() throws {
        let clock = RelativeDateProvider(using: Date(timeIntervalSince1970: 1_000))
        let cache = ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true)
        cache.insert(id: "native-a", timestamp: 999_000, hasReplay: true, isActive: true, sceneIdentifier: .init(rawValue: "scene-a"))
        cache.insert(id: "native-b", timestamp: 999_500, hasReplay: true, isActive: true, sceneIdentifier: .init(rawValue: "scene-b"))
        cache.insert(id: "legacy", timestamp: 999_900, hasReplay: true, isActive: true)
        let original = capturedWebViewContext(viewID: "native-a")
        let scope = FeatureScopeMock(context: .mockWith(serverTimeOffset: 0, additionalContext: [original]), deferEventWriteContext: true)
        let core = CapturedWebViewCore()
        let owner = RUMContextHandoff.Owner()
        core.owner = owner
        let receiver = WebViewEventReceiver(featureScope: scope, dateProvider: clock, commandSubscriber: RUMCommandSubscriberMock(), viewCache: cache)
        let message = capturedWebViewMessage(owner: owner, context: original)
        XCTAssertTrue(receiver.receive(message: .payload(message), from: core))
        scope.contextMock = .mockWith(serverTimeOffset: 0, additionalContext: [capturedWebViewContext(viewID: "native-b")])
        scope.flushDeferredEventWriteContexts()

        let event: AnyEncodable = try XCTUnwrap(scope.eventsWritten(ofType: AnyEncodable.self).first)
        let json = try JSONObjectMatcher(event)
        XCTAssertEqual(try json.value("container.view.id"), "native-a")
        XCTAssertEqual(try json.value("view.id"), "browser-view")
        XCTAssertEqual(try json.value("session.id"), "native-session")
        XCTAssertEqual(try json.value("application.id"), "native-app")
        XCTAssertEqual(cache.lastView(before: 1_000_000, hasReplay: true), "legacy")
    }

    func testCapturedMessage_doesNotFallbackAfterInvalidationOrReplacement() {
        for invalidate in [true, false] {
            let owner = RUMContextHandoff.Owner()
            let context = capturedWebViewContext(viewID: "native-a")
            let scope = FeatureScopeMock(context: .mockWith(additionalContext: [context]), deferEventWriteContext: true)
            let core = CapturedWebViewCore()
            core.owner = owner
            let receiver = WebViewEventReceiver(featureScope: scope, dateProvider: DateProviderMock(), commandSubscriber: RUMCommandSubscriberMock(), viewCache: ViewCache(dateProvider: DateProviderMock()))
            XCTAssertTrue(receiver.receive(message: .payload(capturedWebViewMessage(owner: owner, context: context)), from: core))
            if invalidate { owner.invalidate() } else { core.owner = RUMContextHandoff.Owner() }
            scope.flushDeferredEventWriteContexts()
            XCTAssertTrue(scope.eventsWritten.isEmpty)
        }
    }

    func testCapturedMessage_dropsChangedSessionAndAuthoritativeAbsence() {
        for absent in [true, false] {
            let owner = RUMContextHandoff.Owner()
            let original = capturedWebViewContext(viewID: "native-a")
            let replacement = RUMCoreContext(applicationID: "native-app", sessionID: "new-session", sessionSampler: .mockKeepAll(), viewID: "native-b")
            let scope = FeatureScopeMock(context: .mockWith(additionalContext: [replacement]))
            let core = CapturedWebViewCore()
            core.owner = owner
            let subscriber = RUMCommandSubscriberMock()
            let receiver = WebViewEventReceiver(featureScope: scope, dateProvider: DateProviderMock(), commandSubscriber: subscriber, viewCache: ViewCache(dateProvider: DateProviderMock()))
            XCTAssertTrue(receiver.receive(message: .payload(capturedWebViewMessage(owner: owner, context: absent ? nil : original)), from: core))
            XCTAssertTrue(scope.eventsWritten.isEmpty)
            XCTAssertTrue(subscriber.receivedCommands.isEmpty)
        }
    }

    func testCapturedMessage_doesNotBorrowPeerContainer() throws {
        let clock = RelativeDateProvider(using: Date(timeIntervalSince1970: 1_000))
        let cache = ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true)
        cache.insert(id: "native-b", timestamp: 999_000, hasReplay: true, isActive: true, sceneIdentifier: .init(rawValue: "scene-b"))
        let context = capturedWebViewContext(viewID: "native-a")
        let scope = FeatureScopeMock(context: .mockWith(serverTimeOffset: 0, additionalContext: [context]))
        let owner = RUMContextHandoff.Owner()
        let core = CapturedWebViewCore()
        core.owner = owner
        let receiver = WebViewEventReceiver(featureScope: scope, dateProvider: clock, commandSubscriber: RUMCommandSubscriberMock(), viewCache: cache)
        XCTAssertTrue(receiver.receive(message: .payload(capturedWebViewMessage(owner: owner, context: context)), from: core))
        let event: AnyEncodable = try XCTUnwrap(scope.eventsWritten(ofType: AnyEncodable.self).first)
        let json = try JSONObjectMatcher(event)
        XCTAssertNil(json.object["container"])
        XCTAssertEqual(try json.value("view.id"), "browser-view")
    }

    func testCapturedMessage_clearsUnprovedContainerWithoutValidMetadata() throws {
        let malformed: [JSON] = [
            ["view": ["id": "browser-view"]],
            ["date": "1000000", "view": ["id": "browser-view"]],
            ["date": 1_000_000],
            ["date": 1_000_000, "view": [:] as JSON],
            ["date": 1_000_000, "view": ["id": 42]]
        ]
        for fields in malformed {
            let context = capturedWebViewContext(viewID: "native-a")
            let scope = FeatureScopeMock(context: .mockWith(additionalContext: [context]))
            let owner = RUMContextHandoff.Owner()
            let core = CapturedWebViewCore()
            core.owner = owner
            let receiver = WebViewEventReceiver(
                featureScope: scope, dateProvider: DateProviderMock(),
                commandSubscriber: RUMCommandSubscriberMock(), viewCache: ViewCache(dateProvider: DateProviderMock())
            )
            var event = fields
            event["container"] = ["view": ["id": "unproved-peer"]]
            event["application"] = ["id": "browser-app"]
            event["session"] = ["id": "browser-session"]
            let capture = RUMContextHandoff.Capture(
                owner: owner, value: .init(rumContext: context, sceneIdentifier: "scene-a", hasPendingUserAction: false, excludedUserActionID: nil)
            )
            XCTAssertTrue(receiver.receive(message: .payload(WebViewMessageWithRUMContext(message: .rum(event), capture: capture)), from: core))
            let written = try JSONObjectMatcher(XCTUnwrap(scope.eventsWritten(ofType: AnyEncodable.self).first))
            XCTAssertNil(written.object["container"])
            XCTAssertEqual(try written.value("application.id"), "native-app")
            XCTAssertEqual(try written.value("session.id"), "native-session")
            for key in ["date", "view"] {
                XCTAssertTrue(NSDictionary(dictionary: ["value": fields[key] ?? NSNull()]).isEqual(to: ["value": written.object[key] ?? NSNull()]))
            }
        }
    }

    func testCapturedTelemetry_doesNotBorrowReplacementOwner() {
        let context = capturedWebViewContext(viewID: "native-a")
        let scope = FeatureScopeMock(context: .mockWith(additionalContext: [context]))
        let owner = RUMContextHandoff.Owner()
        let core = CapturedWebViewCore()
        core.owner = RUMContextHandoff.Owner()
        let receiver = WebViewEventReceiver(featureScope: scope, dateProvider: DateProviderMock(), commandSubscriber: RUMCommandSubscriberMock(), viewCache: ViewCache(dateProvider: DateProviderMock()))
        let capture = RUMContextHandoff.Capture(owner: owner, value: .init(rumContext: context, sceneIdentifier: "scene-a", hasPendingUserAction: false, excludedUserActionID: nil))
        XCTAssertTrue(receiver.receive(message: .payload(WebViewMessageWithRUMContext(message: .telemetry(["date": 1_000_000]), capture: capture)), from: core))
        XCTAssertTrue(scope.eventsWritten.isEmpty)
    }

    func testCapturedMessage_checksLiveSessionAtDeferredDelivery() {
        for telemetry in [false, true] {
            let original = capturedWebViewContext(viewID: "native-a")
            let scope = FeatureScopeMock(context: .mockWith(additionalContext: [original]), deferEventWriteContext: true)
            let core = CapturedWebViewCore()
            let owner = RUMContextHandoff.Owner()
            core.owner = owner
            let subscriber = RUMCommandSubscriberMock()
            let receiver = WebViewEventReceiver(featureScope: scope, dateProvider: DateProviderMock(), commandSubscriber: subscriber, viewCache: ViewCache(dateProvider: DateProviderMock()))
            let captured = capturedWebViewMessage(owner: owner, context: original)
            let message = telemetry
                ? WebViewMessageWithRUMContext(message: .telemetry(["date": 1_000_000]), capture: captured.capture)
                : captured
            XCTAssertTrue(receiver.receive(message: .payload(message), from: core))
            core.sessionValidator?.isActive = false
            scope.flushDeferredEventWriteContexts()
            XCTAssertTrue(scope.eventsWritten.isEmpty)
            XCTAssertTrue(subscriber.receivedCommands.isEmpty)
            XCTAssertEqual(core.sessionValidator?.calls, 1)
        }
    }

    func testCapturedMessage_requiresLiveSessionCapability() {
        let original = capturedWebViewContext(viewID: "native-a")
        let scope = FeatureScopeMock(context: .mockWith(additionalContext: [original]))
        let core = CapturedWebViewCore()
        let owner = RUMContextHandoff.Owner()
        core.owner = owner
        core.sessionValidator = nil
        let subscriber = RUMCommandSubscriberMock()
        let receiver = WebViewEventReceiver(featureScope: scope, dateProvider: DateProviderMock(), commandSubscriber: subscriber, viewCache: ViewCache(dateProvider: DateProviderMock()))
        XCTAssertTrue(receiver.receive(message: .payload(capturedWebViewMessage(owner: owner, context: original)), from: core))
        XCTAssertTrue(scope.eventsWritten.isEmpty)
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)
    }

    func testSourceLessWebViewMessage_doesNotReadLiveSessionCapability() {
        let original = capturedWebViewContext(viewID: "native-a")
        let scope = FeatureScopeMock(context: .mockWith(additionalContext: [original]))
        let core = CapturedWebViewCore()
        core.sessionValidator?.isActive = false
        let subscriber = RUMCommandSubscriberMock()
        let receiver = WebViewEventReceiver(featureScope: scope, dateProvider: DateProviderMock(), commandSubscriber: subscriber, viewCache: ViewCache(dateProvider: DateProviderMock()))
        XCTAssertTrue(receiver.receive(message: .webview(.rum(["view": ["id": "browser-view"]])), from: core))
        XCTAssertEqual(scope.eventsWritten.count, 1)
        XCTAssertEqual(subscriber.receivedCommands.count, 1)
        XCTAssertEqual(core.sessionValidator?.calls, 0)
    }

    private func capturedWebViewContext(viewID: String) -> RUMCoreContext {
        RUMCoreContext(applicationID: "native-app", sessionID: "native-session", sessionSampler: .mockKeepAll(), viewID: viewID)
    }

    private func capturedWebViewMessage(owner: RUMContextHandoff.Owner, context: RUMCoreContext?) -> WebViewMessageWithRUMContext {
        WebViewMessageWithRUMContext(
            message: .rum(["application": ["id": "browser-app"], "session": ["id": "browser-session"], "view": ["id": "browser-view"], "date": 1_000_000, "container": ["view": ["id": "unproved-container"]]]),
            capture: .init(owner: owner, value: .init(rumContext: context, sceneIdentifier: "scene-a", hasPendingUserAction: false, excludedUserActionID: nil))
        )
    }
}

private final class CapturedWebViewCore: DatadogCoreProtocol, RUMContextHandoffOwnerProviding, @unchecked Sendable {
    let base: PassthroughCoreMock
    var owner: RUMContextHandoff.Owner?
    var sessionValidator: CapturedWebViewSession? = CapturedWebViewSession()
    var scopeOverride: FeatureScope?
    var rumContextHandoffOwner: RUMContextHandoff.Owner? { owner }
    var remoteConfiguration: RemoteConfiguration? { base.remoteConfiguration }

    init(context: DatadogContext = .mockAny()) { base = PassthroughCoreMock(context: context) }

    func register<T>(feature: T) throws where T: DatadogFeature {}
    func feature<T>(named name: String, type: T.Type) -> T? {
        name == Feature.rum ? sessionValidator as? T : nil
    }
    func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature { scopeOverride ?? base }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext { base.set(context: context) }
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { base.send(message: message, else: fallback) }
    func mostRecentModifiedFileAt(before: Date) throws -> Date? { nil }
    func events<T>(ofType type: T.Type = T.self) -> [T] where T: Encodable { base.events(ofType: type) }
}

private final class CapturedWebViewSession: RUMContextHandoffSessionValidating {
    var isActive = true
    var calls = 0
    func isRUMContextHandoffSessionActive(sessionID: String, owner: RUMContextHandoff.Owner) -> Bool {
        calls += 1
        return isActive
    }
}
