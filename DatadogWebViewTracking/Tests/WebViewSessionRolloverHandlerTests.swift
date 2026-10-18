/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(WebKit)

import XCTest
import WebKit
#if os(iOS)
import UIKit
#endif
import TestUtilities
@_spi(Internal)
import DatadogInternal
@testable import DatadogRUM
@testable import DatadogWebViewTracking

@MainActor
final class WebViewSessionRolloverHandlerTests: XCTestCase {
    func testNativeOwnership_legacyDoesNotLookUpProvider() {
        let core = WebViewContextCoreMock()
        let handler = WebViewSessionRolloverHandler(core: core)
        XCTAssertNil(handler.captureRUMContext(forSceneIdentifier: "a"))
        XCTAssertEqual(core.lookups, 0)
    }

    func testNativeOwnership_providerCanRegisterAfterPublication() throws {
        let core = WebViewContextCoreMock()
        let handler = WebViewSessionRolloverHandler(core: core)
        let owner = RUMContextHandoff.Owner()
        let receiver = WebViewTrackingMessageReceiver(sessionRolloverHandler: handler)
        receiver.receiveRUMContextHandoff(owner: owner, active: true)
        let beforeRegistration = try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: "a"))
        XCTAssertTrue(beforeRegistration.owner === owner)
        XCTAssertNil(beforeRegistration.value.rumContext)
        let provider = WebViewContextProviderMock()
        provider.output = nativeCapture(owner: owner, scene: "a")
        core.provider = provider
        let afterRegistration = try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: "a"))
        XCTAssertTrue(afterRegistration.owner === owner)
        XCTAssertEqual(afterRegistration.value.rumContext?.viewID, "view-a")
        XCTAssertEqual(core.lookups, 2)
        XCTAssertEqual(provider.calls, 1)
    }

    func testNativeOwnership_unknownOriginDoesNotLookUpProvider() throws {
        let core = WebViewContextCoreMock()
        let handler = WebViewSessionRolloverHandler(core: core)
        let owner = RUMContextHandoff.Owner()
        handler.receiveRUMContextHandoff(owner: owner, active: true)
        let capture = try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: nil))
        XCTAssertTrue(capture.owner === owner)
        XCTAssertNil(capture.value.rumContext)
        XCTAssertEqual(core.lookups, 0)
    }

    func testNativeOwnership_retirementNeverReturnsLegacyFallback() throws {
        let core = WebViewContextCoreMock()
        let handler = WebViewSessionRolloverHandler(core: core)
        let owner = RUMContextHandoff.Owner()
        owner.invalidate()
        handler.receiveRUMContextHandoff(owner: owner, active: false)
        handler.receiveRUMContextHandoff(owner: owner, active: true)
        let capture = try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: "a"))
        XCTAssertTrue(capture.owner === owner)
        XCTAssertNil(capture.value.rumContext)
        XCTAssertEqual(core.lookups, 0)

        #if os(iOS)
        if #available(iOS 27.0, *) {
            let bridge = DDScriptMessageHandler(emitter: MessageEmitter(logsSampler: .mockKeepAll(), core: core))
            bridge.sessionRolloverHandler = handler
            let webView = ReceiptCountingWebView(frame: .zero, configuration: WKWebViewConfiguration())
            let controller = WKUserContentController()
            let message = MockScriptMessage(body: receiptBody, webView: webView)
            XCTAssertTrue(core.messages.isEmpty)
            let windowReadsBeforeReceipt = webView.windowReads
            bridge.userContentController(controller, didReceive: message)
            let windowReadsAtReturn = webView.windowReads
            bridge.flush()

            let payload = try XCTUnwrap(core.messages.firstPayload as? WebViewMessageWithRUMContext)
            XCTAssertTrue(payload.capture.owner === owner)
            XCTAssertFalse(payload.capture.owner.isValid)
            XCTAssertNil(payload.capture.value.rumContext)
            XCTAssertNil(payload.capture.value.sceneIdentifier)
            XCTAssertFalse(payload.capture.value.hasPendingUserAction)
            XCTAssertNil(payload.capture.value.excludedUserActionID)
            XCTAssertEqual(core.messages.count, 1)
            XCTAssertNil(core.messages.firstWebViewMessage)
            XCTAssertEqual(windowReadsAtReturn - windowReadsBeforeReceipt, 0)
            XCTAssertEqual(core.lookups, 0)
        }
        #endif
    }

    func testNativeOwnership_oldPublicationCannotReplaceNewOwner() throws {
        let core = WebViewContextCoreMock()
        let handler = WebViewSessionRolloverHandler(core: core)
        let old = RUMContextHandoff.Owner()
        let current = RUMContextHandoff.Owner()
        handler.receiveRUMContextHandoff(owner: old, active: true)
        old.invalidate()
        handler.receiveRUMContextHandoff(owner: current, active: true)
        handler.receiveRUMContextHandoff(owner: old, active: false)
        handler.receiveRUMContextHandoff(owner: old, active: true)
        XCTAssertTrue(try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: "a")).owner === current)
    }

    func testNativeOwnership_rejectsForeignProviderCapture() throws {
        let core = WebViewContextCoreMock()
        let provider = WebViewContextProviderMock()
        core.provider = provider
        let handler = WebViewSessionRolloverHandler(core: core)
        let owner = RUMContextHandoff.Owner()
        handler.receiveRUMContextHandoff(owner: owner, active: true)
        for capture in [nativeCapture(owner: RUMContextHandoff.Owner(), scene: "a"), nativeCapture(owner: owner, scene: "b")] {
            provider.output = capture
            let result = try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: "a"))
            XCTAssertTrue(result.owner === owner)
            XCTAssertNil(result.value.rumContext)
        }
    }

    func testNativeOwnership_backgroundRetirementReturnsBeforeMainAndPreservesReplacement() async throws {
        let core = WebViewContextCoreMock()
        let handler = WebViewSessionRolloverHandler(core: core)
        let receiver = WebViewTrackingMessageReceiver(sessionRolloverHandler: handler)
        let old = RUMContextHandoff.Owner()
        let current = RUMContextHandoff.Owner()
        receiver.receiveRUMContextHandoff(owner: old, active: true)
        old.invalidate()
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            receiver.receiveRUMContextHandoff(owner: old, active: false)
            returned.signal()
        }
        XCTAssertEqual(returned.wait(timeout: .now() + 1), .success)
        receiver.receiveRUMContextHandoff(owner: current, active: true)
        let mainDelivery = expectation(description: "queued retirement observed")
        DispatchQueue.main.async { mainDelivery.fulfill() }
        await fulfillment(of: [mainDelivery], timeout: 1)
        XCTAssertTrue(try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: "a")).owner === current)
    }

    func testNativeOwnership_doesNotRetainCore() throws {
        var core: WebViewContextCoreMock? = WebViewContextCoreMock()
        weak var weakCore = core
        let handler = WebViewSessionRolloverHandler(core: try XCTUnwrap(core))
        let owner = RUMContextHandoff.Owner()
        handler.receiveRUMContextHandoff(owner: owner, active: true)
        core = nil
        XCTAssertNil(weakCore)
        let capture = try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: "a"))
        XCTAssertTrue(capture.owner === owner)
        XCTAssertNil(capture.value.rumContext)
    }

    #if os(iOS)
    func testNativeReceiptLegacyDoesNotResolveScene() {
        let core = WebViewContextCoreMock()
        let handler = WebViewSessionRolloverHandler(core: core)
        var resolutions = 0
        XCTAssertNil(handler.captureRUMContext(forSceneIdentifier: {
            resolutions += 1
            return "scene-a"
        }))
        XCTAssertEqual(resolutions, 0)
        XCTAssertEqual(core.lookups, 0)
    }

    @available(iOS 27.0, *)
    func testNativeReceiptInvalidAndRetiredOwnersDoNotResolveScene() throws {
        for retired in [false, true] {
            let core = WebViewContextCoreMock()
            let handler = WebViewSessionRolloverHandler(core: core)
            let owner = RUMContextHandoff.Owner()
            handler.receiveRUMContextHandoff(owner: owner, active: true)
            owner.invalidate()
            if retired {
                handler.receiveRUMContextHandoff(owner: owner, active: false)
            }
            var resolutions = 0
            let capture = try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: {
                resolutions += 1
                return "scene-a"
            }))
            XCTAssertTrue(capture.owner === owner)
            XCTAssertNil(capture.value.rumContext)
            XCTAssertEqual(resolutions, 0)
            XCTAssertEqual(core.lookups, 0)
        }
    }

    @available(iOS 27.0, *)
    func testNativeReceiptMissingSceneKeepsAuthoritativeAbsence() throws {
        let core = WebViewContextCoreMock()
        let handler = WebViewSessionRolloverHandler(core: core)
        let owner = RUMContextHandoff.Owner()
        handler.receiveRUMContextHandoff(owner: owner, active: true)
        var resolutions = 0
        let capture = try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: {
            resolutions += 1
            return nil
        }))
        XCTAssertTrue(capture.owner === owner)
        XCTAssertNil(capture.value.rumContext)
        XCTAssertEqual(resolutions, 1)
        XCTAssertEqual(core.lookups, 0)
    }

    @available(iOS 27.0, *)
    func testNativeReceiptUsesResolvedSceneAndFreezesProviderValue() throws {
        let core = WebViewContextCoreMock()
        let provider = WebViewContextProviderMock()
        core.provider = provider
        let handler = WebViewSessionRolloverHandler(core: core)
        let owner = RUMContextHandoff.Owner()
        handler.receiveRUMContextHandoff(owner: owner, active: true)
        provider.output = nativeCapture(owner: owner, scene: "receipt-b")
        let capture = try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: { "receipt-b" }))
        provider.output = nativeCapture(owner: owner, scene: "later-c")
        XCTAssertTrue(capture.owner === owner)
        XCTAssertEqual(capture.value.sceneIdentifier, "receipt-b")
        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(core.lookups, 1)
    }

    @available(iOS 27.0, *)
    func testNativeReceiptResolutionCannotAdoptReentrantReplacement() throws {
        let core = WebViewContextCoreMock()
        let provider = WebViewContextProviderMock()
        core.provider = provider
        let handler = WebViewSessionRolloverHandler(core: core)
        let original = RUMContextHandoff.Owner()
        let replacement = RUMContextHandoff.Owner()
        handler.receiveRUMContextHandoff(owner: original, active: true)
        let capture = try XCTUnwrap(handler.captureRUMContext(forSceneIdentifier: {
            original.invalidate()
            handler.receiveRUMContextHandoff(owner: replacement, active: true)
            provider.output = self.nativeCapture(owner: replacement, scene: "receipt-b")
            return "receipt-b"
        }))
        XCTAssertTrue(capture.owner === original)
        XCTAssertNil(capture.value.rumContext)
        XCTAssertEqual(core.lookups, 0)
        XCTAssertEqual(provider.calls, 0)
    }

    func testScriptReceiptOffDoesNotReadNativeWindowOrProvider() throws {
        let core = WebViewContextCoreMock()
        let rollover = WebViewSessionRolloverHandler(core: core)
        let bridge = DDScriptMessageHandler(emitter: MessageEmitter(logsSampler: .mockKeepAll(), core: core))
        bridge.sessionRolloverHandler = rollover
        let webView = ReceiptCountingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let controller = WKUserContentController()
        let message = MockScriptMessage(body: receiptBody, webView: webView)
        let windowReadsBeforeReceipt = webView.windowReads
        bridge.userContentController(controller, didReceive: message)
        let windowReadsAtReturn = webView.windowReads
        bridge.flush()
        XCTAssertEqual(windowReadsAtReturn - windowReadsBeforeReceipt, 0)
        XCTAssertEqual(core.lookups, 0)
        XCTAssertEqual(core.messages.count, 1)
        XCTAssertNotNil(core.messages.firstWebViewMessage)
        XCTAssertNil(core.messages.firstPayload as? WebViewMessageWithRUMContext)
    }

    @available(iOS 27.0, *)
    func testScriptReceiptDetachedViewCarriesEmptyCapturedOwnership() throws {
        let core = WebViewContextCoreMock()
        let rollover = WebViewSessionRolloverHandler(core: core)
        let owner = RUMContextHandoff.Owner()
        rollover.receiveRUMContextHandoff(owner: owner, active: true)
        let bridge = DDScriptMessageHandler(emitter: MessageEmitter(logsSampler: .mockKeepAll(), core: core))
        bridge.sessionRolloverHandler = rollover
        let webView = ReceiptCountingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let controller = WKUserContentController()
        let message = MockScriptMessage(body: receiptBody, webView: webView)
        let windowReadsBeforeReceipt = webView.windowReads
        bridge.userContentController(controller, didReceive: message)
        let windowReadsAtReturn = webView.windowReads
        bridge.flush()
        let payload = try XCTUnwrap(core.messages.firstPayload as? WebViewMessageWithRUMContext)
        XCTAssertTrue(payload.capture.owner === owner)
        XCTAssertNil(payload.capture.value.rumContext)
        XCTAssertEqual(windowReadsAtReturn - windowReadsBeforeReceipt, 1)
        XCTAssertEqual(core.lookups, 0)
        XCTAssertEqual(core.messages.count, 1)
        XCTAssertNil(core.messages.firstWebViewMessage)
    }

    @available(iOS 27.0, *)
    func testScriptReceiptFreezesOriginalAbsenceBeforeBridgeQueueDelivery() throws {
        let webView = ReceiptCountingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let core = WebViewContextCoreMock()
        let provider = WebViewContextProviderMock()
        core.provider = provider
        let rollover = WebViewSessionRolloverHandler(core: core)
        let original = RUMContextHandoff.Owner()
        rollover.receiveRUMContextHandoff(owner: original, active: true)
        provider.output = nativeCapture(owner: original, scene: "original-scene")
        let bridge = DDScriptMessageHandler(emitter: MessageEmitter(logsSampler: .mockKeepAll(), core: core))
        bridge.sessionRolloverHandler = rollover
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        bridge.queue.async(qos: .default, flags: .enforceQoS) {
            entered.signal()
            release.wait()
        }
        guard entered.wait(timeout: .now() + 10) == .success else {
            return XCTFail("Bridge queue blocker did not start")
        }
        let controller = WKUserContentController()
        let message = MockScriptMessage(body: receiptBody, webView: webView)
        let windowReadsBeforeReceipt = webView.windowReads
        bridge.userContentController(controller, didReceive: message)
        let windowReadsAtReturn = webView.windowReads
        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(core.lookups, 0)
        original.invalidate()
        let replacement = RUMContextHandoff.Owner()
        rollover.receiveRUMContextHandoff(owner: replacement, active: true)
        provider.output = nativeCapture(owner: replacement, scene: "later-scene")
        release.signal()
        bridge.flush()
        let payload = try XCTUnwrap(core.messages.firstPayload as? WebViewMessageWithRUMContext)
        XCTAssertTrue(payload.capture.owner === original)
        XCTAssertFalse(payload.capture.owner.isValid)
        XCTAssertNil(payload.capture.value.sceneIdentifier)
        XCTAssertNil(payload.capture.value.rumContext)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(core.lookups, 0)
        XCTAssertEqual(windowReadsAtReturn - windowReadsBeforeReceipt, 1)
        XCTAssertEqual(core.messages.count, 1)
        XCTAssertNil(core.messages.firstWebViewMessage)
    }

    @available(iOS 27.0, *)
    func testRetainedScriptReceiptProviderDoesNotRetainCore() throws {
        var core: WebViewContextCoreMock? = WebViewContextCoreMock()
        weak var weakCore = core
        let original = RUMContextHandoff.Owner()
        let rollover = WebViewSessionRolloverHandler(core: try XCTUnwrap(core))
        rollover.receiveRUMContextHandoff(owner: original, active: true)
        let bridge = DDScriptMessageHandler(emitter: MessageEmitter(logsSampler: .mockKeepAll(), core: try XCTUnwrap(core)))
        bridge.sessionRolloverHandler = rollover
        core = nil
        XCTAssertNil(weakCore)
        let capture = try XCTUnwrap(try XCTUnwrap(bridge.sessionRolloverHandler).captureRUMContext(forSceneIdentifier: { "scene-a" }))
        XCTAssertTrue(capture.owner === original)
        XCTAssertNil(capture.value.rumContext)
    }

    private var receiptBody: String {
        "{\"eventType\":\"rum\",\"event\":{\"view\":{\"id\":\"browser-view\"},\"session\":{\"id\":\"browser-session\"}}}"
    }
    #endif

    private func nativeCapture(owner: RUMContextHandoff.Owner, scene: String) -> RUMContextHandoff.Capture {
        let context = RUMCoreContext(applicationID: "app", sessionID: "session", sessionSampler: .mockKeepAll(), viewID: "view-a")
        return .init(owner: owner, value: .init(rumContext: context, sceneIdentifier: scene, hasPendingUserAction: false, excludedUserActionID: nil))
    }

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

#if os(iOS)
@MainActor
private final class ReceiptCountingWebView: WKWebView {
    private(set) var windowReads = 0

    override var window: UIWindow? {
        windowReads += 1
        return super.window
    }
}
#endif

private final class WebViewContextCoreMock: DatadogCoreProtocol {
    var provider: WebViewContextProviderMock?
    var lookups = 0
    var messages: [FeatureMessage] = []
    var remoteConfiguration: RemoteConfiguration? { nil }
    func register<T>(feature: T) throws where T: DatadogFeature {}
    func feature<T>(named name: String, type: T.Type) -> T? {
        lookups += 1
        return name == Feature.rum ? provider as? T : nil
    }
    func scope<T>(for featureType: T.Type) -> FeatureScope where T: DatadogFeature { NOPFeatureScope() }
    func set<Context>(context: @escaping () -> Context?) where Context: AdditionalContext {}
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { messages.append(message) }
    func mostRecentModifiedFileAt(before: Date) throws -> Date? { nil }
}

private final class WebViewContextProviderMock: RUMContextHandoffWebViewProviding {
    var output: RUMContextHandoff.Capture?
    var calls = 0
    func captureRUMContext(forSceneIdentifier sceneIdentifier: String, owner: RUMContextHandoff.Owner) -> RUMContextHandoff.Capture? {
        calls += 1
        return output
    }
}

#endif
