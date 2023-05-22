/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(tvOS)

import XCTest
import WebKit
import TestUtilities
@testable import Datadog

final class DDUserContentController: WKUserContentController {
    typealias NameHandlerPair = (name: String, handler: WKScriptMessageHandler)
    private(set) var messageHandlers = [NameHandlerPair]()

    override func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        messageHandlers.append((name: name, handler: scriptMessageHandler))
    }

    override func removeScriptMessageHandler(forName name: String) {
        messageHandlers = messageHandlers.filter {
            return $0.name != name
        }
    }
}

final class MockMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { }
}

final class MockScriptMessage: WKScriptMessage {
    let mockBody: Any

    init(body: Any) {
        self.mockBody = body
    }

    override var body: Any { return mockBody }
}

class WKUserContentController_DatadogTests: XCTestCase {
    func testItAddsUserScriptAndMessageHandler() throws {
        let mockSanitizer = MockHostsSanitizer()
        let controller = DDUserContentController()

        let initialUserScriptCount = controller.userScripts.count

        controller.addDatadogMessageHandler(
            core: PassthroughCoreMock(),
            allowedWebViewHosts: ["datadoghq.com"],
            hostsSanitizer: mockSanitizer
        )

        XCTAssertEqual(controller.userScripts.count, initialUserScriptCount + 1)
        XCTAssertEqual(controller.messageHandlers.map({ $0.name }), ["DatadogEventBridge"])

        XCTAssertEqual(mockSanitizer.sanitizations.count, 1)
        let sanitization = try XCTUnwrap(mockSanitizer.sanitizations.first)
        XCTAssertEqual(sanitization.hosts, ["datadoghq.com"])
        XCTAssertEqual(sanitization.warningMessage, "The allowed WebView host configured for Datadog SDK is not valid")
    }

    func testWhenAddingMessageHandlerMultipleTimes_itIgnoresExtraOnesAndPrintsWarning() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let mockSanitizer = MockHostsSanitizer()
        let controller = DDUserContentController()

        let initialUserScriptCount = controller.userScripts.count

        let multipleTimes = 5
        (0..<multipleTimes).forEach { _ in
            controller.addDatadogMessageHandler(
                core: PassthroughCoreMock(),
                allowedWebViewHosts: ["datadoghq.com"],
                hostsSanitizer: mockSanitizer
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
            Array(repeating: "`trackDatadogEvents(in:)` was called more than once for the same WebView. Second call will be ignored. Make sure you call it only once.", count: multipleTimes - 1)
        )
    }

    func testWhenStoppingTracking_itKeepsNonDatadogComponents() throws {
        let core = PassthroughCoreMock()
        let controller = DDUserContentController()

        controller.trackDatadogEvents(in: [], sdk: core)

        let componentCount = 10
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

        controller.stopTrackingDatadogEvents()

        XCTAssertEqual(controller.userScripts.count, componentCount)
        XCTAssertEqual(controller.messageHandlers.count, componentCount)
    }

    func testItLogsInvalidWebMessages() throws {
        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        let controller = DDUserContentController()
        controller.addDatadogMessageHandler(
            core: PassthroughCoreMock(),
            allowedWebViewHosts: ["datadoghq.com"],
            hostsSanitizer: MockHostsSanitizer()
        )

        let messageHandler = try XCTUnwrap(controller.messageHandlers.first?.handler) as? DatadogMessageHandler
        // non-string body is passed
        messageHandler?.userContentController(controller, didReceive: MockScriptMessage(body: 123))
        messageHandler?.queue.sync { }

        XCTAssertEqual(dd.logger.errorLog?.message, "Encountered an error when receiving web view event")
        XCTAssertEqual(dd.logger.errorLog?.error?.message, #"invalidMessage(description: "123")"#)
    }

    func testSendingWebEvents() throws {
        let core = DatadogCoreProxy(
            context: .mockWith(
                service: "default-service-name",
                env: "tests",
                version: "1.0.0",
                applicationBundleIdentifier: "com.datadoghq.ios-sdk",
                featuresAttributes: [
                    "rum": [
                        "ids": [
                            RUMContextAttributes.IDs.sessionID: UUID.nullUUID.uuidString.lowercased(),
                            RUMContextAttributes.IDs.applicationID: String.mockAny()
                        ]
                    ]
                ]
            )
        )
        defer { core.flushAndTearDown() }

        let logging: LoggingFeature = .mockWith(
            messageReceiver: WebViewLogReceiver()
        )
        core.register(feature: logging)

        let rum: RUMFeature = .mockWith(
            messageReceiver: WebViewEventReceiver.mockAny()
        )
        core.register(feature: rum)

        Global.rum = RUMMonitor.initialize(in: core)
        defer { Global.rum = DDNoopRUMMonitor() }

        let controller = DDUserContentController()
        controller.addDatadogMessageHandler(
            core: core,
            allowedWebViewHosts: ["datadoghq.com"],
            hostsSanitizer: MockHostsSanitizer()
        )

        let messageHandler = try XCTUnwrap(controller.messageHandlers.first?.handler) as? DatadogMessageHandler
        let webLogMessage = MockScriptMessage(body: #"{"eventType":"log","event":{"date":1635932927012,"error":{"origin":"console"},"message":"console error: error","session_id":"0110cab4-7471-480e-aa4e-7ce039ced355","status":"error","view":{"referrer":"","url":"https://datadoghq.dev/browser-sdk-test-playground"}},"tags":["browser_sdk_version:3.6.13"]}"#)
        messageHandler?.userContentController(controller, didReceive: webLogMessage)

        messageHandler?.queue.sync {}
        let logMatcher = try core.waitAndReturnLogMatchers()[0]

        logMatcher.assertValue(forKey: "date", equals: 1_635_932_927_012)
        logMatcher.assertValue(forKey: "ddtags", equals: "version:1.0.0,env:tests")
        logMatcher.assertValue(forKey: "message", equals: "console error: error")
        logMatcher.assertValue(forKey: "status", equals: "error")
        logMatcher.assertValue(
            forKey: "view",
            equals: ["referrer": "", "url": "https://datadoghq.dev/browser-sdk-test-playground"]
        )
        logMatcher.assertValue(
            forKey: "error",
            equals: ["origin": "console"]
        )

        logMatcher.assertValue(forKeyPath: "session_id", equals: Global.rum.dd.applicationScope.activeSession?.sessionUUID.toRUMDataFormat.lowercased())

        let webRUMMessage = MockScriptMessage(body: #"{"eventType":"view","event":{"application":{"id":"xxx"},"date":1635933113708,"service":"super","session":{"id":"0110cab4-7471-480e-aa4e-7ce039ced355","type":"user"},"type":"view","view":{"action":{"count":0},"cumulative_layout_shift":0,"dom_complete":152800000,"dom_content_loaded":118300000,"dom_interactive":116400000,"error":{"count":0},"first_contentful_paint":121300000,"id":"64308fd4-83f9-48cb-b3e1-1e91f6721230","in_foreground_periods":[],"is_active":true,"largest_contentful_paint":121299000,"load_event":152800000,"loading_time":152800000,"loading_type":"initial_load","long_task":{"count":0},"referrer":"","resource":{"count":3},"time_spent":3120000000,"url":"http://localhost:8080/test.html"},"_dd":{"document_version":2,"drift":0,"format_version":2,"session":{"plan":2}}},"tags":["browser_sdk_version:3.6.13"]}"#)
        messageHandler?.userContentController(controller, didReceive: webRUMMessage)

        messageHandler?.queue.sync {}
        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers().filterApplicationLaunchView()
        try rumEventMatchers[0].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.application.id, "abc")
            XCTAssertEqual(rumModel.view.id, "64308fd4-83f9-48cb-b3e1-1e91f6721230")
        }
    }
}

#endif
