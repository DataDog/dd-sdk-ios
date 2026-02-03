/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

import XCTest
import WebKit
import TestUtilities
import DatadogInternal
@testable import DatadogWebViewTracking

class WebViewTrackingTests: XCTestCase {
    func testItAddsUserScript() throws {
        let mockSanitizer = HostsSanitizerMock()
        let controller = DDUserContentController()

        let host: String = .mockRandom()

        try WebViewTracking.enableOrThrow(
            tracking: controller,
            hosts: [host],
            hostsSanitizer: mockSanitizer,
            logsSampleRate: 30,
            in: PassthroughCoreMock()
        )

        let script = try XCTUnwrap(controller.userScripts.last)
        XCTAssertEqual(script.source, """
        /* DatadogEventBridge */
        window.DatadogEventBridge = {
            send(msg) {
                window.webkit.messageHandlers.DatadogEventBridge.postMessage(msg)
            },
            getAllowedWebViewHosts() {
                return '["\(host)"]'
            },
            getCapabilities() {
                return '[]'
            },
            getPrivacyLevel() {
                return 'mask'
            }
        }
        """)
    }

    func testItAddsUserScriptWithSessionReplay() throws {
        struct SessionReplayFeature: DatadogFeature, SessionReplayConfiguration {
            static let name = "session-replay"
            let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()
            let textAndInputPrivacyLevel: DatadogInternal.TextAndInputPrivacyLevel
            let imagePrivacyLevel: DatadogInternal.ImagePrivacyLevel
            let touchPrivacyLevel: DatadogInternal.TouchPrivacyLevel
        }

        let mockSanitizer = HostsSanitizerMock()
        let controller = DDUserContentController()

        let host: String = .mockRandom()
        let sr = SessionReplayFeature(
            textAndInputPrivacyLevel: .mockRandom(),
            imagePrivacyLevel: .mockRandom(),
            touchPrivacyLevel: .mockRandom()
        )
        let privacyLevel = WebViewTracking.determineWebViewPrivacyLevel(
            textPrivacy: sr.textAndInputPrivacyLevel,
            imagePrivacy: sr.imagePrivacyLevel,
            touchPrivacy: sr.touchPrivacyLevel
        )

        try WebViewTracking.enableOrThrow(
            tracking: controller,
            hosts: [host],
            hostsSanitizer: mockSanitizer,
            logsSampleRate: 30,
            in: SingleFeatureCoreMock(feature: sr)
        )

        let script = try XCTUnwrap(controller.userScripts.last)
        XCTAssertEqual(script.source, """
        /* DatadogEventBridge */
        window.DatadogEventBridge = {
            send(msg) {
                window.webkit.messageHandlers.DatadogEventBridge.postMessage(msg)
            },
            getAllowedWebViewHosts() {
                return '["\(host)"]'
            },
            getCapabilities() {
                return '["records"]'
            },
            getPrivacyLevel() {
                return '\(privacyLevel.rawValue)'
            }
        }
        """)
    }

    func testItAddsUserScriptAndMessageHandler() throws {
        let mockSanitizer = HostsSanitizerMock()
        let controller = DDUserContentController()

        let initialUserScriptCount = controller.userScripts.count

        try WebViewTracking.enableOrThrow(
            tracking: controller,
            hosts: ["datadoghq.com"],
            hostsSanitizer: mockSanitizer,
            logsSampleRate: 30,
            in: PassthroughCoreMock()
        )

        XCTAssertEqual(controller.userScripts.count, initialUserScriptCount + 1)
        XCTAssertEqual(controller.messageHandlers.map({ $0.name }), ["DatadogEventBridge"])

        let messageHandler = try XCTUnwrap(controller.messageHandlers.first?.handler) as? DDScriptMessageHandler
        XCTAssertEqual(messageHandler?.emitter.logsSampler.samplingRate, 30)

        XCTAssertEqual(mockSanitizer.sanitizations.count, 1)
        let sanitization = try XCTUnwrap(mockSanitizer.sanitizations.first)
        XCTAssertEqual(sanitization.hosts, ["datadoghq.com"])
        XCTAssertEqual(sanitization.warningMessage, "The allowed WebView host configured for Datadog SDK is not valid")
    }

    func testWhenAddingMessageHandlerMultipleTimes_itIgnoresExtraOnesAndPrintsWarning() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let mockSanitizer = HostsSanitizerMock()
        let controller = DDUserContentController()

        let initialUserScriptCount = controller.userScripts.count

        let multipleTimes = Int.random(in: 1...5)
        try (0..<multipleTimes).forEach { _ in
            try WebViewTracking.enableOrThrow(
                tracking: controller,
                hosts: ["datadoghq.com"],
                hostsSanitizer: mockSanitizer,
                logsSampleRate: 100,
                in: PassthroughCoreMock()
            )
        }

        XCTAssertEqual(controller.userScripts.count, initialUserScriptCount + 1)
        XCTAssertEqual(controller.messageHandlers.map({ $0.name }), ["DatadogEventBridge"])

        XCTAssertGreaterThanOrEqual(mockSanitizer.sanitizations.count, 1)
        let sanitization = try XCTUnwrap(mockSanitizer.sanitizations.first)
        XCTAssertEqual(sanitization.hosts, ["datadoghq.com"])
        XCTAssertEqual(sanitization.warningMessage, "The allowed WebView host configured for Datadog SDK is not valid")

        XCTAssertEqual(
            dd.logger.warnLogs.map({ $0.message }),
            Array(repeating: "`startTrackingDatadogEvents(core:hosts:)` was called more than once for the same WebView. Second call will be ignored. Make sure you call it only once.", count: multipleTimes - 1)
        )
    }

    func testWhenAddingMessageHandlerMultipleTimes_afterExternalRemovalOfUserScripts_itHandlesCorrectlyTheInstrumentation() {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let core = PassthroughCoreMock()
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        let webView = WKWebView(frame: .zero, configuration: configuration)

        WebViewTracking.enable(webView: webView, in: core)

        XCTAssertEqual(controller.userScripts.count, 1)
        // Simulates external code wiping user scripts.
        controller.removeAllUserScripts()
        XCTAssertTrue(controller.userScripts.isEmpty)

        WebViewTracking.enable(webView: webView, in: core)

        XCTAssertEqual(controller.userScripts.count, 1)
        XCTAssertEqual(dd.logger.warnLogs.count, 0)
    }

    func testWhenStoppingTracking_itCanBeEnabledAgain() throws {
        let core = PassthroughCoreMock()
        let controller = DDUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webview = WKWebView(frame: .zero, configuration: configuration)

        WebViewTracking.enable(webView: webview,in: core)

        XCTAssertEqual(controller.userScripts.count, 1)
        XCTAssertEqual(controller.messageHandlers.count, 1)

        WebViewTracking.disable(webView: webview)

        XCTAssertEqual(controller.userScripts.count, 0)
        XCTAssertEqual(controller.messageHandlers.count, 0)

        WebViewTracking.enable(webView: webview,in: core)

        XCTAssertEqual(controller.userScripts.count, 1)
        XCTAssertEqual(controller.messageHandlers.count, 1)
    }

    func testWhenStoppingTracking_itKeepsNonDatadogComponents() throws {
        let core = PassthroughCoreMock()
        let controller = DDUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webview = WKWebView(frame: .zero, configuration: configuration)

        WebViewTracking.enable(
            webView: webview,
            in: core
        )

        let componentCount = Int.random(in: 1...10)
        for i in 0..<componentCount {
            let userScript = WKUserScript(
                source: String.mockRandom(),
                injectionTime: (i % 2 == 0 ? .atDocumentStart : .atDocumentEnd),
                forMainFrameOnly: i % 2 == 0
            )
            controller.addUserScript(userScript)
            controller.add(MockMessageHandler(), name: String.mockRandom())
        }

        XCTAssertEqual(controller.userScripts.count, componentCount + 1)
        XCTAssertEqual(controller.messageHandlers.count, componentCount + 1)

        WebViewTracking.disable(webView: webview)

        XCTAssertEqual(controller.userScripts.count, componentCount)
        XCTAssertEqual(controller.messageHandlers.count, componentCount)
    }

    func testSendingWebEvents() throws {
        let logMessageExpectation = expectation(description: "Log message received")
        let core = PassthroughCoreMock(
            messageReceiver: FeatureMessageReceiverMock { message in
                switch message {
                case let .webview(.log(event)):
                    let matcher = JSONObjectMatcher(object: event)
                    XCTAssertEqual(try? matcher.value("date"), 1_635_932_927_012)
                    XCTAssertEqual(try? matcher.value("message"), "console error: error")
                    XCTAssertEqual(try? matcher.value("status"), "error")
                    XCTAssertEqual(try? matcher.value("view"), ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"])
                    XCTAssertEqual(try? matcher.value("error"), ["origin": "console"])
                    XCTAssertEqual(try? matcher.value("session_id"), "0110cab4-7471-480e-aa4e-7ce039ced355")
                    logMessageExpectation.fulfill()
                case .context:
                    break
                default:
                    XCTFail("Unexpected message received: \(message)")
                }
            }
        )

        let controller = DDUserContentController()
        try WebViewTracking.enableOrThrow(
            tracking: controller,
            hosts: ["datadoghq.com"],
            hostsSanitizer: HostsSanitizerMock(),
            logsSampleRate: 100,
            in: core
        )

        let messageHandler = try XCTUnwrap(controller.messageHandlers.first?.handler) as? DDScriptMessageHandler
        let webLogMessage = MockScriptMessage(body: """
        {
          "eventType": "log",
          "event": {
            "date": 1635932927012,
            "error": {
              "origin": "console"
            },
            "message": "console error: error",
            "session_id": "0110cab4-7471-480e-aa4e-7ce039ced355",
            "status": "error",
            "view": {
              "referrer": "",
              "url": "https://datadoghq.dev/browser-sdk-test-playground"
            }
          },
          "tags": [
            "browser_sdk_version:3.6.13"
          ]
        }
        """)
        messageHandler?.userContentController(controller, didReceive: webLogMessage)
        waitForExpectations(timeout: 1)
    }

    func testSendingWebRUMEvent() throws {
        let rumMessageExpectation = expectation(description: "RUM message received")
        let core = PassthroughCoreMock(
            messageReceiver: FeatureMessageReceiverMock { message in
                switch message {
                case let .webview(.rum(event)):
                    let matcher = JSONObjectMatcher(object: event)
                    XCTAssertEqual(try? matcher.value("view.id"), "64308fd4-83f9-48cb-b3e1-1e91f6721230")
                    rumMessageExpectation.fulfill()
                case .context:
                    break
                default:
                    XCTFail("Unexpected message received: \(message)")
                }
            }
        )

        let controller = DDUserContentController()
        try WebViewTracking.enableOrThrow(
            tracking: controller,
            hosts: ["datadoghq.com"],
            hostsSanitizer: HostsSanitizerMock(),
            logsSampleRate: 100,
            in: core
        )

        let messageHandler = try XCTUnwrap(controller.messageHandlers.first?.handler) as? DDScriptMessageHandler
        let webRUMMessage = MockScriptMessage(body: """
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
        """)
        messageHandler?.userContentController(controller, didReceive: webRUMMessage)
        waitForExpectations(timeout: 1)
    }

    func testSendingWebRecordEvent() throws {
        let recordMessageExpectation = expectation(description: "Record message received")
        let webView = WKWebView()
        let controller = DDUserContentController()

        let core = PassthroughCoreMock(
            messageReceiver: FeatureMessageReceiverMock { message in
                switch message {
                case let .webview(.record(event, view)):
                    XCTAssertEqual(view.id, "64308fd4-83f9-48cb-b3e1-1e91f6721230")
                    let matcher = JSONObjectMatcher(object: event)
                    XCTAssertEqual(try? matcher.value("date"), 1_635_932_927_012)
                    XCTAssertEqual(try? matcher.value("slotId"), String(webView.hash))
                    recordMessageExpectation.fulfill()
                case .context:
                    break
                default:
                    XCTFail("Unexpected message received: \(message)")
                }
            }
        )

        try WebViewTracking.enableOrThrow(
            tracking: controller,
            hosts: ["datadoghq.com"],
            hostsSanitizer: HostsSanitizerMock(),
            logsSampleRate: 100,
            in: core
        )

        let messageHandler = try XCTUnwrap(controller.messageHandlers.first?.handler) as? DDScriptMessageHandler
        let webLogMessage = MockScriptMessage(body: """
        {
          "eventType": "record",
          "event": {
            "date": 1635932927012
          },
          "view": { "id": "64308fd4-83f9-48cb-b3e1-1e91f6721230" }
        }
        """, webView: webView)

        messageHandler?.userContentController(controller, didReceive: webLogMessage)
        waitForExpectations(timeout: 1)
    }
}

#endif
