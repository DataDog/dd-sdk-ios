/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

#if !os(tvOS) && !os(watchOS)

import DatadogInternal
import TestUtilities
import WebKit

@testable import DatadogRUM
@testable import DatadogWebViewTracking

@MainActor
class WebEventIntegrationTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var controller: WKUserContentControllerMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        core = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.1.1",
                serverTimeOffset: 123
            )
        )

        let config = WKWebViewConfiguration()
        controller = WKUserContentControllerMock()
        config.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: config)

        try WebViewTracking.enableOrThrow(
            tracking: webView,
            hosts: [],
            hostsSanitizer: HostsSanitizer(),
            logsSampleRate: 100,
            in: core
        )
    }

    override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        controller = nil
    }

    func testWebEventIntegration() throws {
        // Given
        let randomApplicationID: String = .mockRandom()
        let randomUUID: RUMUUID = .mockRandom()

        RUM.enable(with: .mockWith(applicationID: randomApplicationID) {
            $0.uuidGenerator = RUMUUIDGeneratorMock(uuid: randomUUID)
        }, in: core)

        // Flush to ensure the AnonymousIdentifierManager has generated
        // and propagated the anonymous ID to the context
        core.flush()

        let body = """
        {
          "eventType": "view",
          "event": {
            "application": {
              "id": "xxx"
            },
            "date": \(1_635_932_927_012),
            "service": "super",
            "session": {
              "id": "0110cab4-7471-480e-aa4e-7ce039ced355",
              "type": "user",
              "has_replay": true
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
              "url": "http://localhost:8080/test.html",
            },
            "_dd": {
              "document_version": 2,
              "drift": 0,
              "format_version": 2,
              "replay_stats": {
                  "records_count": 10,
                  "segments_count": 1,
                  "segments_total_raw_size": 10
              }
            }
          },
          "tags": [
            "browser_sdk_version:3.6.13"
          ]
        }
        """

        // When
        RUMMonitor.shared(in: core).startView(key: "web-view")
        controller.send(body: body)
        controller.flush()

        // Then
        let expectedUUID = randomUUID.toRUMDataFormat
        let rumMatcher = try XCTUnwrap(core.waitAndReturnRUMEventMatchers().last)
        try rumMatcher.assertItFullyMatches(
            jsonString: """
        {
            "application": {
              "id": "\(randomApplicationID)"
            },
            "date": \(1_635_932_927_012 + 123.dd.toInt64Milliseconds),
            "service": "super",
            "session": {
              "id": "\(expectedUUID)",
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
              "format_version": 2
            },
            "usr": {
              "anonymous_id": "\(expectedUUID)"
            },
            "ddtags": "service:abc,version:1.1.1,sdk_version:abc,env:test"
        }
        """
        )
    }

    func testWebTelemetryIntegration() throws {
        // Given
        let randomApplicationID: String = .mockRandom()
        let randomUUID: RUMUUID = .mockRandom()

        RUM.enable(with: .mockWith(applicationID: randomApplicationID) {
            $0.uuidGenerator = RUMUUIDGeneratorMock(uuid: randomUUID)
        }, in: core)

        let body = """
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
        """

        // When
        RUMMonitor.shared(in: core).startView(key: "web-view")
        controller.send(body: body)
        controller.flush()

        // Then
        let expectedUUID = randomUUID.toRUMDataFormat
        let rumMatcher = try XCTUnwrap(core.waitAndReturnRUMEventMatchers().last)
        try rumMatcher.assertItFullyMatches(
            jsonString: """
        {
          "type": "telemetry",
          "date": \(1_712_069_357_432 + 123.dd.toInt64Milliseconds),
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
          "application": { "id": "\(randomApplicationID)" },
          "session": { "id": "\(expectedUUID)" },
          "view": {},
          "action": { "id": [] }
        }
        """
        )
    }

    #if os(iOS)
    func testGivenLongLivedNativeView_whenDelayedWebEventsArrive_itPreservesContainerWindow() throws {
        // Given
        let applicationID = "exp207-native-application"
        let dateProvider = DateProviderMock(now: Date(timeIntervalSince1970: 1_700_000_000))

        RUM.enable(with: .mockWith(applicationID: applicationID) {
            $0.dateProvider = dateProvider
        }, in: core)
        core.set(context: SessionReplayCoreContext.HasReplay(value: true))
        var hasReplayBeforeViewA: Bool?
        core.scope(for: RUMFeature.self).context { context in
            hasReplayBeforeViewA = context.additionalContext(ofType: SessionReplayCoreContext.HasReplay.self)?.value
        }
        core.flush()
        XCTAssertEqual(hasReplayBeforeViewA, true)

        let monitor = RUMMonitor.shared(in: core)
        let viewAStart = dateProvider.now
        monitor.startView(key: "native-a", name: "Native A")
        core.flush()
        let eventsBeforeViewB = try core.waitAndReturnRUMEventMatchers()
        let allNativeViewEventsBeforeViewB = eventsBeforeViewB.filterRUMEvents(
            ofType: RUMViewEvent.self,
            where: { $0.view.name != nil }
        )
        let incidentalNativeViewCount = allNativeViewEventsBeforeViewB.filter {
            let name: String? = try? $0.attribute(forKeyPath: "view.name")
            return name != "Native A" && name != "Native B"
        }.count
        XCTAssertGreaterThan(incidentalNativeViewCount, 0, "Retain incidental native view inventory separately")
        let nativeViewEventsBeforeViewB = allNativeViewEventsBeforeViewB.filter {
            let name: String? = try? $0.attribute(forKeyPath: "view.name")
            return name == "Native A" || name == "Native B"
        }
        XCTAssertEqual(nativeViewEventsBeforeViewB.count, 1, "A must emit one workload view event before B starts")
        let nativeAStartedEvents = nativeViewEventsBeforeViewB.filter {
            let name: String? = try? $0.attribute(forKeyPath: "view.name")
            return name == "Native A"
        }
        XCTAssertEqual(nativeAStartedEvents.count, 1)
        let nativeAStartedEvent: RUMViewEvent = try XCTUnwrap(nativeAStartedEvents.first?.model())
        XCTAssertEqual(nativeAStartedEvent.view.isActive, true)
        XCTAssertEqual(nativeAStartedEvent.session.hasReplay, true)

        // A is intentionally older than the legacy three-minute insertion TTL when B starts.
        let viewBStart = viewAStart.addingTimeInterval(3.minutes + 1)
        dateProvider.now = viewBStart
        monitor.startView(key: "native-b", name: "Native B")
        core.flush()
        let eventsAfterViewB = try core.waitAndReturnRUMEventMatchers()
        let allNativeViewEventsAfterViewB = eventsAfterViewB.filterRUMEvents(
            ofType: RUMViewEvent.self,
            where: { $0.view.name != nil }
        )
        let incidentalNativeViewCountAfterViewB = allNativeViewEventsAfterViewB.filter {
            let name: String? = try? $0.attribute(forKeyPath: "view.name")
            return name != "Native A" && name != "Native B"
        }.count
        XCTAssertEqual(incidentalNativeViewCountAfterViewB, incidentalNativeViewCount)
        let nativeViewEventsAfterViewB = allNativeViewEventsAfterViewB.filter {
            let name: String? = try? $0.attribute(forKeyPath: "view.name")
            return name == "Native A" || name == "Native B"
        }
        XCTAssertEqual(nativeViewEventsAfterViewB.count, 3, "B must add A's terminal update and B's active event")
        let nativeAEvents = nativeViewEventsAfterViewB.filter {
            let name: String? = try? $0.attribute(forKeyPath: "view.name")
            return name == "Native A"
        }
        XCTAssertEqual(nativeAEvents.count, 2, "The native inventory must contain A's active and terminal records")
        let nativeAStoppedEvents = try nativeAEvents.compactMap { matcher -> RUMEventMatcher? in
            let event: RUMViewEvent = try matcher.model()
            return event.view.isActive == false ? matcher : nil
        }
        XCTAssertEqual(nativeAStoppedEvents.count, 1, "A must have exactly one terminal record")
        let nativeAIDs = try nativeAEvents.map { (matcher: RUMEventMatcher) -> String in
            let event: RUMViewEvent = try matcher.model()
            return event.view.id
        }
        XCTAssertEqual(Set(nativeAIDs).count, 1, "A's active and terminal records must share one owner")
        let nativeAEvent: RUMViewEvent = try XCTUnwrap(nativeAStoppedEvents.first?.model())
        XCTAssertEqual(nativeAEvent.view.name, "Native A")
        let nativeViewA = nativeAEvent.view.id
        let nativeSessionID = nativeAEvent.session.id
        let nativeApplicationID = nativeAEvent.application.id
        XCTAssertEqual(nativeApplicationID, applicationID)
        XCTAssertEqual(nativeAEvent.session.hasReplay, true)
        let nativeBEventsAfterViewB = nativeViewEventsAfterViewB.filter {
            let name: String? = try? $0.attribute(forKeyPath: "view.name")
            return name == "Native B"
        }
        XCTAssertEqual(nativeBEventsAfterViewB.count, 1, "The native inventory must contain exactly one B owner record")
        let nativeBEvent: RUMViewEvent = try XCTUnwrap(nativeBEventsAfterViewB.first?.model())
        XCTAssertEqual(nativeBEvent.view.isActive, true)
        XCTAssertEqual(nativeBEvent.application.id, nativeApplicationID)
        XCTAssertEqual(nativeBEvent.session.id, nativeSessionID)
        XCTAssertNotEqual(nativeBEvent.view.id, nativeViewA)

        let browserApplicationID = "exp207-browser-application"
        let browserSessionID = "00000000-0000-0000-0000-000000000010"
        let browserViewID = "00000000-0000-0000-0000-000000000011"
        let serverOffsetMilliseconds = 123.dd.toInt64Milliseconds
        let delayedAEventDate = viewAStart.timeIntervalSince1970.dd.toInt64Milliseconds + 1_000 - serverOffsetMilliseconds
        let currentBEventDate = viewBStart.timeIntervalSince1970.dd.toInt64Milliseconds + 1_000 - serverOffsetMilliseconds

        // When: A's delayed browser event arrives near the end of the inactive retention window.
        dateProvider.now = viewBStart.addingTimeInterval(3.minutes - 1)
        controller.send(body: webViewViewBody(
            date: delayedAEventDate,
            applicationID: browserApplicationID,
            sessionID: browserSessionID,
            viewID: browserViewID
        ))
        controller.flush()

        let delayedAWithinWindow = try consumeBrowserViewEvent(
            from: core,
            browserViewID: browserViewID,
            service: "exp207-browser",
            expectedCount: 1
        )
        assertWebViewEvent(
            delayedAWithinWindow,
            applicationID: nativeApplicationID,
            sessionID: nativeSessionID,
            browserViewID: browserViewID,
            eventDate: delayedAEventDate + serverOffsetMilliseconds,
            containerViewID: nativeViewA
        )

        // When: the same delayed A event arrives after the inactive retention window.
        dateProvider.now = viewBStart.addingTimeInterval(3.minutes + 1)
        controller.send(body: webViewViewBody(
            date: delayedAEventDate,
            applicationID: browserApplicationID,
            sessionID: browserSessionID,
            viewID: browserViewID
        ))
        controller.flush()

        let delayedAAfterWindow = try consumeBrowserViewEvent(
            from: core,
            browserViewID: browserViewID,
            service: "exp207-browser",
            expectedCount: 2
        )
        assertWebViewEvent(
            delayedAAfterWindow,
            applicationID: nativeApplicationID,
            sessionID: nativeSessionID,
            browserViewID: browserViewID,
            eventDate: delayedAEventDate + serverOffsetMilliseconds,
            containerViewID: nil
        )

        // Then: a current B event still resolves to B while B remains active.
        controller.send(body: webViewViewBody(
            date: currentBEventDate,
            applicationID: browserApplicationID,
            sessionID: browserSessionID,
            viewID: browserViewID
        ))
        controller.flush()

        let currentBEvent = try consumeBrowserViewEvent(
            from: core,
            browserViewID: browserViewID,
            service: "exp207-browser",
            expectedCount: 3
        )

        assertWebViewEvent(
            currentBEvent,
            applicationID: nativeApplicationID,
            sessionID: nativeSessionID,
            browserViewID: browserViewID,
            eventDate: currentBEventDate + serverOffsetMilliseconds,
            containerViewID: nativeBEvent.view.id
        )
    }

    private func webViewViewBody(date: Int64, applicationID: String, sessionID: String, viewID: String) -> String {
        """
        {
          "eventType": "view",
          "event": {
            "application": { "id": "\(applicationID)" },
            "date": \(date),
            "service": "exp207-browser",
            "session": { "id": "\(sessionID)", "type": "user", "has_replay": true },
            "type": "view",
            "view": {
              "action": { "count": 0 },
              "error": { "count": 0 },
              "id": "\(viewID)",
              "is_active": true,
              "resource": { "count": 0 }
            },
            "_dd": {
              "document_version": 2,
              "format_version": 2,
              "replay_stats": {
                "records_count": 1,
                "segments_count": 1,
                "segments_total_raw_size": 1
              }
            }
          }
        }
        """
    }

    private func assertWebViewEvent(
        _ matcher: RUMEventMatcher,
        applicationID: String,
        sessionID: String,
        browserViewID: String,
        eventDate: Int64,
        containerViewID: String?
    ) {
        matcher.jsonMatcher.assertValue(forKeyPath: "type", equals: "view")
        matcher.jsonMatcher.assertValue(forKeyPath: "application.id", equals: applicationID)
        matcher.jsonMatcher.assertValue(forKeyPath: "session.id", equals: sessionID)
        matcher.jsonMatcher.assertValue(forKeyPath: "session.has_replay", equals: true)
        matcher.jsonMatcher.assertValue(forKeyPath: "view.id", equals: browserViewID)
        matcher.jsonMatcher.assertValue(forKeyPath: "date", equals: Int(eventDate))

        if let containerViewID {
            matcher.jsonMatcher.assertValue(forKeyPath: "container.source", equals: "ios")
            matcher.jsonMatcher.assertValue(forKeyPath: "container.view.id", equals: containerViewID)
        } else {
            matcher.jsonMatcher.assertNoValue(forKeyPath: "container")
        }
    }

    private func consumeBrowserViewEvent(
        from core: DatadogCoreProxy,
        browserViewID: String,
        service: String,
        expectedCount: Int
    ) throws -> RUMEventMatcher {
        let inventory = try core.waitAndReturnRUMEventMatchers()
        let candidates = inventory.filter { matcher in
            let viewID: String? = try? matcher.jsonMatcher.valueOrNil(forKeyPath: "view.id")
            let eventService: String? = try? matcher.jsonMatcher.valueOrNil(forKeyPath: "service")
            return viewID == browserViewID && eventService == service
        }
        XCTAssertEqual(candidates.count, expectedCount, "Each browser phase must add exactly one matching view event")
        return try XCTUnwrap(candidates.dropFirst(expectedCount - 1).first)
    }
    #endif
}

#endif
