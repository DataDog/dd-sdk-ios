/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(WebKit)

import XCTest
import WebKit
import TestUtilities
import DatadogInternal
@testable import DatadogRUM
@testable import DatadogWebViewTracking

@MainActor
final class WebViewSessionRolloverHandlerTests: XCTestCase {
    func testSingleCore() throws {
        let core = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.0.0",
                serverTimeOffset: 0
            )
        )
        defer { try? core.flushAndTearDown() }

        RUM.enable(with: .mockWith(applicationID: "test-app-id"), in: core)
        core.flush()

        let config1 = WKWebViewConfiguration()
        let controller1 = DDUserContentController()
        config1.userContentController = controller1
        let webView1 = WKWebView(frame: .zero, configuration: config1)
        let elements1 = WebViewTrackingElements(allowedWebViewHostsString: "localhost")
        try WebViewSessionRolloverHandler.register(webView: webView1, in: core, using: elements1)

        let handler = try XCTUnwrap(WebViewSessionRolloverHandler.handlerPerViewTesting.object(forKey: webView1))
        XCTAssert(handler.coreTesting === core)
        XCTAssert(handler.activeWebViewsTesting.object(forKey: webView1) === elements1)

        let config2 = WKWebViewConfiguration()
        let controller2 = DDUserContentController()
        config2.userContentController = controller2
        let webView2 = WKWebView(frame: .zero, configuration: config2)
        let elements2 = WebViewTrackingElements(allowedWebViewHostsString: "shopist.io")
        try WebViewSessionRolloverHandler.register(webView: webView2, in: core, using: elements2)

        let handler2 = try XCTUnwrap(WebViewSessionRolloverHandler.handlerPerViewTesting.object(forKey: webView2))
        XCTAssert(handler === handler2)
        XCTAssertEqual(WebViewSessionRolloverHandler.handlerPerViewTesting.count, 2)
        XCTAssertEqual(handler.activeWebViewsTesting.count, 2)
        XCTAssert(handler.activeWebViewsTesting.object(forKey: webView2) === elements2)

        WebViewSessionRolloverHandler.unregister(webView: webView1)
        XCTAssertEqual(WebViewSessionRolloverHandler.handlerPerViewTesting.count, 1)
        XCTAssertEqual(handler.activeWebViewsTesting.count, 1)
        XCTAssert(handler.activeWebViewsTesting.object(forKey: webView2) === elements2)
        XCTAssertNil(handler.activeWebViewsTesting.object(forKey: webView1))

        WebViewSessionRolloverHandler.unregister(webView: webView2)
        XCTAssertEqual(WebViewSessionRolloverHandler.handlerPerViewTesting.count, 0)
        XCTAssertEqual(handler.activeWebViewsTesting.count, 0)
    }

    func testMultipleCores() throws {
        // Setup two cores
        let core1 = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.0.0",
                serverTimeOffset: 0
            )
        )
        defer { try? core1.flushAndTearDown() }
        RUM.enable(with: .mockWith(applicationID: "test-app-id"), in: core1)
        core1.flush()

        let core2 = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.0.0",
                serverTimeOffset: 0
            )
        )
        defer { try? core2.flushAndTearDown() }
        RUM.enable(with: .mockWith(applicationID: "test-app-id"), in: core2)
        core2.flush()

        // Register a view in core 1
        let config1 = WKWebViewConfiguration()
        let controller1 = DDUserContentController()
        config1.userContentController = controller1
        let webView1 = WKWebView(frame: .zero, configuration: config1)
        let elements1 = WebViewTrackingElements(allowedWebViewHostsString: "localhost")
        try WebViewSessionRolloverHandler.register(webView: webView1, in: core1, using: elements1)

        let handler = try XCTUnwrap(WebViewSessionRolloverHandler.handlerPerViewTesting.object(forKey: webView1))
        XCTAssert(handler.coreTesting === core1)
        XCTAssert(handler.activeWebViewsTesting.object(forKey: webView1) === elements1)

        // Register a view in core 2
        let config2 = WKWebViewConfiguration()
        let controller2 = DDUserContentController()
        config2.userContentController = controller2
        let webView2 = WKWebView(frame: .zero, configuration: config2)
        let elements2 = WebViewTrackingElements(allowedWebViewHostsString: "shopist.io")
        try WebViewSessionRolloverHandler.register(webView: webView2, in: core2, using: elements2)

        let handler2 = try XCTUnwrap(WebViewSessionRolloverHandler.handlerPerViewTesting.object(forKey: webView2))
        XCTAssert(handler !== handler2)
        XCTAssert(handler2.coreTesting === core2)
        XCTAssertEqual(WebViewSessionRolloverHandler.handlerPerViewTesting.count, 2)
        XCTAssertEqual(handler2.activeWebViewsTesting.count, 1)
        XCTAssertEqual(handler.activeWebViewsTesting.count, 1)
        XCTAssert(handler2.activeWebViewsTesting.object(forKey: webView2) === elements2)
        XCTAssertNil(handler.activeWebViewsTesting.object(forKey: webView2))
        XCTAssertNil(handler2.activeWebViewsTesting.object(forKey: webView1))

        WebViewSessionRolloverHandler.unregister(webView: webView1)
        XCTAssertEqual(WebViewSessionRolloverHandler.handlerPerViewTesting.count, 1)
        XCTAssertEqual(handler.activeWebViewsTesting.count, 0)
        XCTAssertEqual(handler2.activeWebViewsTesting.count, 1)
        XCTAssertNil(handler.activeWebViewsTesting.object(forKey: webView1))

        WebViewSessionRolloverHandler.unregister(webView: webView2)
        XCTAssertEqual(WebViewSessionRolloverHandler.handlerPerViewTesting.count, 0)
        XCTAssertEqual(handler.activeWebViewsTesting.count, 0)
        XCTAssertEqual(handler2.activeWebViewsTesting.count, 0)
        XCTAssertNil(handler2.activeWebViewsTesting.object(forKey: webView2))
    }

    func testWeakReferencesHandling() throws {
        let core = DatadogCoreProxy(
            context: .mockWith(
                env: "test",
                version: "1.0.0",
                serverTimeOffset: 0
            )
        )
        defer { try? core.flushAndTearDown() }

        RUM.enable(with: .mockWith(applicationID: "test-app-id"), in: core)
        core.flush()

        //swiftlint:disable implicitly_unwrapped_optional
        var handler: WebViewSessionRolloverHandler!

        try autoreleasepool {
            let config1 = WKWebViewConfiguration()
            let controller1 = DDUserContentController()
            config1.userContentController = controller1
            let webView1 = WKWebView(frame: .zero, configuration: config1)
            let elements1 = WebViewTrackingElements(allowedWebViewHostsString: "localhost")
            try WebViewSessionRolloverHandler.register(webView: webView1, in: core, using: elements1)

            handler = try XCTUnwrap(WebViewSessionRolloverHandler.handlerPerViewTesting.object(forKey: webView1))
            XCTAssert(handler.coreTesting === core)
            XCTAssert(handler.activeWebViewsTesting.object(forKey: webView1) === elements1)
        }

        // We need at least an iteration of the run loop for the WebViews to be deallocated due to
        // how this class works internally.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))

        // Note: we cannot test `count == 0` for these collections because given the way weak refs work,
        // the collection has no way to know objects were deallocated and `count` will not be updated.
        let handlerPerViewEnumerator = WebViewSessionRolloverHandler.handlerPerViewTesting.keyEnumerator()
        while let _ = handlerPerViewEnumerator.nextObject() as? WKWebView {
            XCTFail("WebViewSessionRolloverHandler.handlerPerView should be empty.")
        }

        let activeWebViewsEnumerator = handler.activeWebViewsTesting.keyEnumerator()
        while let _ = activeWebViewsEnumerator.nextObject() as? WKWebView {
            XCTFail("handler.activeWebViews.handlerPerView should be empty.")
        }
    }
}

#endif
