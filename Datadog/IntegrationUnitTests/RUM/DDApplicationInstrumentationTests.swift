/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

#if !os(watchOS)
// TODO: RUMM-2034 Remove this flag once we have a host application for tests
class DDApplicationInstrumentationTests: XCTestCase {
    private let handler = RUMActionsHandlerMock()
    private lazy var instumentation = try! DDApplicationInstrumentation(handler: handler)

    override func setUp() {
        super.setUp()
        instumentation.install()
    }

    override func tearDown() {
        instumentation.uninstall()
        super.tearDown()
    }

    func testWhenSendEventIsCalled_itNotifiesTheHandler() {
        let expectation = self.expectation(description: "Notify handler")

        let anyApplication = DDApplication.shared
        let anyEvent = DDEvent()

        handler.onSendEvent = { application, event in
            XCTAssertTrue(application === anyApplication)
            XCTAssertTrue(event === anyEvent)
            expectation.fulfill()
        }

        anyApplication.sendEvent(anyEvent)

        waitForExpectations(timeout: 1.5, handler: nil)
    }
}
#endif

#if os(iOS)
import UIKit

@available(iOS 27.0, *)
@MainActor
final class SceneApplicationInstrumentationTests: XCTestCase {
    private func actualApplication() throws -> UIApplication {
        let application = UIApplication.shared
        _ = try XCTUnwrap(object_getClass(application), "Requires a live UIKit test host")
        return application
    }

    private func verifyPreviousCall(_ spy: UIKitPreviousSpy, application: UIApplication, event: UIEvent) {
        application.sendEvent(event)
        XCTAssertEqual(spy.calls, 1, "The independent UIKit call-through must work before installing the SDK layer")
        spy.calls = 0
    }

    func testSceneSendEvent_callsActualVoidUIKitImplementationOnceWithoutLegacyNotification() throws {
        let application = try actualApplication()
        let target = UIEvent()
        let previous = UIKitPreviousSpy(target: target)
        try previous.install()
        defer { previous.unswizzle() }
        verifyPreviousCall(previous, application: application, event: target)
        let handler = SceneDispatchHandler()
        let instrumentation = try DDSceneApplicationInstrumentation(handler: handler)
        instrumentation.install()
        defer { instrumentation.uninstall() }
        application.sendEvent(target)
        XCTAssertEqual(handler.intercepts, 1)
        XCTAssertEqual(handler.legacyNotifications, 0, "The unused base layer must not be installed")
        XCTAssertEqual(previous.calls, 1)
        let method = try dd_class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:)))
        XCTAssertTrue(String(cString: method_getTypeEncoding(method)!).hasPrefix("v"))
    }

    func testSceneSendEvent_uninstallAndDeinitPreserveIndependentVoidLayer() throws {
        let application = try actualApplication()
        let target = UIEvent()
        let previous = UIKitPreviousSpy(target: target)
        try previous.install()
        defer { previous.unswizzle() }
        verifyPreviousCall(previous, application: application, event: target)
        let handler = SceneDispatchHandler()
        var instrumentation: DDSceneApplicationInstrumentation? = try DDSceneApplicationInstrumentation(handler: handler)
        instrumentation?.install()
        let later = UIKitPreviousSpy(target: target)
        try later.install()
        defer { later.unswizzle() }
        application.sendEvent(target)
        XCTAssertEqual(handler.intercepts, 1)
        XCTAssertEqual(previous.calls, 1)
        XCTAssertEqual(later.calls, 1)
        instrumentation?.uninstall()
        application.sendEvent(target)
        XCTAssertEqual(handler.intercepts, 1)
        XCTAssertEqual(previous.calls, 2)
        XCTAssertEqual(later.calls, 2)
        instrumentation?.install()
        application.sendEvent(target)
        XCTAssertEqual(handler.intercepts, 2)
        XCTAssertEqual(previous.calls, 3)
        XCTAssertEqual(later.calls, 3)
        instrumentation = nil
        application.sendEvent(target)
        XCTAssertEqual(handler.intercepts, 2)
        XCTAssertEqual(handler.legacyNotifications, 0)
        XCTAssertEqual(previous.calls, 4)
        XCTAssertEqual(later.calls, 4)
    }

    func testMixedSceneTrackingModes_preserveSurvivingSendEventLayer() throws {
        let application = try actualApplication()
        let target = UIEvent()
        let previous = UIKitPreviousSpy(target: target)
        try previous.install()
        defer { previous.unswizzle() }
        verifyPreviousCall(previous, application: application, event: target)

        for legacyInstallsFirst in [true, false] {
            let legacyHandler = SceneDispatchHandler()
            let sceneHandler = SceneDispatchHandler()
            let legacy = try DDApplicationInstrumentation(handler: legacyHandler)
            let scene = try DDSceneApplicationInstrumentation(handler: sceneHandler)
            let first = legacyInstallsFirst ? legacy : scene
            let second = legacyInstallsFirst ? scene : legacy
            first.install()
            second.install()
            defer {
                second.uninstall()
                first.uninstall()
            }

            previous.calls = 0
            application.sendEvent(target)
            XCTAssertEqual(legacyHandler.legacyNotifications, 1)
            XCTAssertEqual(sceneHandler.intercepts, 1)
            XCTAssertEqual(previous.calls, 1)

            first.uninstall()
            application.sendEvent(target)
            XCTAssertEqual(legacyHandler.legacyNotifications, legacyInstallsFirst ? 1 : 2)
            XCTAssertEqual(sceneHandler.intercepts, legacyInstallsFirst ? 2 : 1)
            XCTAssertEqual(previous.calls, 2)

            second.uninstall()
            application.sendEvent(target)
            XCTAssertEqual(legacyHandler.legacyNotifications, legacyInstallsFirst ? 1 : 2)
            XCTAssertEqual(sceneHandler.intercepts, legacyInstallsFirst ? 2 : 1)
            XCTAssertEqual(previous.calls, 3)
        }
    }

    func testSceneSendEvent_releasedHandlerStillCallsActualUIKitImplementationOnce() throws {
        let application = try actualApplication()
        let target = UIEvent()
        let previous = UIKitPreviousSpy(target: target)
        try previous.install()
        defer { previous.unswizzle() }
        verifyPreviousCall(previous, application: application, event: target)
        var handler: SceneDispatchHandler? = SceneDispatchHandler()
        weak var weakHandler = handler
        let swizzler = try DDSceneApplicationInstrumentation.SceneSendEvent(handler: handler!)
        swizzler.swizzle()
        defer { swizzler.unswizzle() }
        handler = nil
        XCTAssertNil(weakHandler)
        application.sendEvent(target)
        XCTAssertEqual(previous.calls, 1)
    }

    func testSceneSendEvent_nestedDispatchCallsEachPreviousImplementationOnce() throws {
        let application = try actualApplication()
        let outer = UIEvent()
        let inner = UIEvent()
        let outerSpy = UIKitPreviousSpy(target: outer)
        let innerSpy = UIKitPreviousSpy(target: inner)
        try outerSpy.install()
        try innerSpy.install()
        defer { innerSpy.unswizzle(); outerSpy.unswizzle() }
        verifyPreviousCall(outerSpy, application: application, event: outer)
        verifyPreviousCall(innerSpy, application: application, event: inner)
        let handler = SceneDispatchHandler()
        var isNested = false
        handler.onIntercept = {
            if !isNested {
                isNested = true
                application.sendEvent(inner)
            }
        }
        let instrumentation = try DDSceneApplicationInstrumentation(handler: handler)
        instrumentation.install()
        defer { instrumentation.uninstall() }
        application.sendEvent(outer)
        XCTAssertEqual(handler.intercepts, 2)
        XCTAssertEqual(handler.legacyNotifications, 0)
        XCTAssertEqual(outerSpy.calls, 1)
        XCTAssertEqual(innerSpy.calls, 1)
    }
}

@available(iOS 27.0, *)
private final class SceneDispatchHandler: RUMSceneActionsHandling {
    var intercepts = 0
    var legacyNotifications = 0
    var onIntercept: (() -> Void)?
    func publish(to subscriber: RUMCommandSubscriber) {}
    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: Encodable]) {}
    func notify_sendEvent(application: UIApplication, event: UIEvent) { legacyNotifications += 1 }
    func intercept(application: UIApplication, event: UIEvent, operation: () -> Void) {
        intercepts += 1
        onIntercept?()
        operation()
    }
}

private final class UIKitPreviousSpy: MethodSwizzler<
    @convention(c) (UIApplication, Selector, UIEvent) -> Void,
    @convention(block) (UIApplication, UIEvent) -> Void
> {
    private static let selector = #selector(UIApplication.sendEvent(_:))
    private let target: UIEvent
    var calls = 0
    init(target: UIEvent) { self.target = target }
    func install() throws {
        let method = try dd_class_getInstanceMethod(UIApplication.self, Self.selector)
        typealias Signature = @convention(block) (UIApplication, UIEvent) -> Void
        swizzle(method) { previous -> Signature in
            return { [weak self] application, event in
                if event === self?.target { self?.calls += 1 }
                previous(application, Self.selector, event)
            }
        }
    }
}
#endif
