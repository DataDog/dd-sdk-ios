/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@_spi(objc)
@testable import DatadogRUM
@_spi(objc)
@testable import DatadogCore

#if !os(watchOS)

class UIKitRUMViewsPredicateBridgeTests: XCTestCase {
    func testItForwardsCallToObjcPredicate() {
        class MockPredicate: objc_ViewsPredicate {
            var didCallRUMView = false
            func rumView(for viewController: DDViewController) -> objc_RUMView? {
                didCallRUMView = true
                return nil
            }
        }

        let objcPredicate = MockPredicate()

        let predicateBridge = ViewsPredicate(objcPredicate: objcPredicate)
        _ = predicateBridge.rumView(for: mockView)

        XCTAssertTrue(objcPredicate.didCallRUMView)
    }
}

class DDRUMViewTests: XCTestCase {
    func testItCreatesSwiftRUMView() {
        let objcRUMView = objc_RUMView(name: "name", attributes: ["foo": "bar"])
        XCTAssertEqual(objcRUMView.swiftView.name, "name")
        XCTAssertEqual(objcRUMView.swiftView.attributes["foo"]?.dd.decode(), "bar")
        XCTAssertEqual(objcRUMView.name, "name")
        XCTAssertEqual(objcRUMView.attributes["foo"] as? String, "bar")
    }
}

#if canImport(UIKit)
class UIKitRUMActionsPredicateBridgeTests: XCTestCase {
    func testItForwardsCallToObjcTouchPredicate() {
        class MockPredicate: objc_UITouchRUMActionsPredicate {
            var didCallRUMAction = false
            func rumAction(targetView: DDView) -> objc_RUMAction? {
                didCallRUMAction = true
                return nil
            }
        }

        let objcPredicate = MockPredicate()

        let predicateBridge = UIKitRUMActionsPredicateBridge(objcPredicate: objcPredicate)
        _ = predicateBridge.rumAction(targetView: DDView())

        XCTAssertTrue(objcPredicate.didCallRUMAction)
    }

    func testItForwardsCallToObjcPressPredicate() {
        class MockPredicate: objc_UIPressRUMActionsPredicate {
            var didCallRUMAction = false
            func rumAction(press: UIPress.PressType, targetView: UIView) -> objc_RUMAction? {
                didCallRUMAction = true
                return nil
            }
        }

        let objcPredicate = MockPredicate()

        let predicateBridge = UIKitRUMActionsPredicateBridge(objcPredicate: objcPredicate)
        _ = predicateBridge.rumAction(press: .select, targetView: UIView())

        XCTAssertTrue(objcPredicate.didCallRUMAction)
    }
}
#endif

class DDRUMActionTests: XCTestCase {
    func testItCreatesSwiftRUMAction() {
        let objcRUMAction = objc_RUMAction(name: "name", attributes: ["foo": "bar"])
        XCTAssertEqual(objcRUMAction.swiftAction.name, "name")
        XCTAssertEqual(objcRUMAction.swiftAction.attributes["foo"]?.dd.decode(), "bar")
        XCTAssertEqual(objcRUMAction.name, "name")
        XCTAssertEqual(objcRUMAction.attributes["foo"] as? String, "bar")
    }
}

class DDRUMUserActionTypeTests: XCTestCase {
    func testMappingToSwiftRUMActionType() {
        XCTAssertEqual(objc_RUMActionType.tap.swiftType, .tap)
        XCTAssertEqual(objc_RUMActionType.scroll.swiftType, .scroll)
        XCTAssertEqual(objc_RUMActionType.swipe.swiftType, .swipe)
        XCTAssertEqual(objc_RUMActionType.custom.swiftType, .custom)
    }
}

class SwiftUIRUMViewsPredicateBridgeTests: XCTestCase {
    func testItForwardsCallToObjcPredicate() {
        class MockPredicate: objc_SwiftUIRUMViewsPredicate {
            var didCallRUMView = false
            func rumView(for extractedViewName: String) -> objc_RUMView? {
                didCallRUMView = true
                return nil
            }
        }

        let objcPredicate = MockPredicate()

        let predicateBridge = SwiftUIRUMViewsPredicateBridge(objcPredicate: objcPredicate)
        _ = predicateBridge.rumView(for: "TestView")

        XCTAssertTrue(objcPredicate.didCallRUMView)
    }
}

#if !os(macOS)
class SwiftUIRUMActionsPredicateBridgeTests: XCTestCase {
    func testItForwardsCallToObjcPredicate() {
        class MockPredicate: objc_SwiftUIRUMActionsPredicate {
            var didCallRUMAction = false
            func rumAction(with componentName: String) -> objc_RUMAction? {
                didCallRUMAction = true
                return nil
            }
        }

        let objcPredicate = MockPredicate()

        let predicateBridge = SwiftUIRUMActionsPredicateBridge(objcPredicate: objcPredicate)
        _ = predicateBridge.rumAction(with: "Button")

        XCTAssertTrue(objcPredicate.didCallRUMAction)
    }
}
#endif

#endif

class DDRUMFeatureOperationFailureReasonTests: XCTestCase {
    func testMappingToSwiftRUMFeatureOperationFailureReason() {
        XCTAssertEqual(objc_RUMFeatureOperationFailureReason.error.swiftType, .error)
        XCTAssertEqual(objc_RUMFeatureOperationFailureReason.abandoned.swiftType, .abandoned)
        XCTAssertEqual(objc_RUMFeatureOperationFailureReason.other.swiftType, .other)
    }
}

class DDRUMErrorSourceTests: XCTestCase {
    func testMappingToSwiftRUMErrorSource() {
        XCTAssertEqual(objc_RUMErrorSource.source.swiftType, .source)
        XCTAssertEqual(objc_RUMErrorSource.network.swiftType, .network)
        XCTAssertEqual(objc_RUMErrorSource.webview.swiftType, .webview)
        XCTAssertEqual(objc_RUMErrorSource.console.swiftType, .console)
        XCTAssertEqual(objc_RUMErrorSource.custom.swiftType, .custom)
    }
}

class DDRUMResourceKindTests: XCTestCase {
    func testMappingToSwiftRUMResourceKind() {
        XCTAssertEqual(objc_ResourceType.image.swiftType, .image)
        XCTAssertEqual(objc_ResourceType.xhr.swiftType, .xhr)
        XCTAssertEqual(objc_ResourceType.beacon.swiftType, .beacon)
        XCTAssertEqual(objc_ResourceType.css.swiftType, .css)
        XCTAssertEqual(objc_ResourceType.document.swiftType, .document)
        XCTAssertEqual(objc_ResourceType.fetch.swiftType, .fetch)
        XCTAssertEqual(objc_ResourceType.font.swiftType, .font)
        XCTAssertEqual(objc_ResourceType.js.swiftType, .js)
        XCTAssertEqual(objc_ResourceType.media.swiftType, .media)
        XCTAssertEqual(objc_ResourceType.other.swiftType, .other)
        XCTAssertEqual(objc_ResourceType.native.swiftType, .native)
    }
}

class DDRUMMethodTests: XCTestCase {
    func testMappingToSwiftRUMMethod() {
        XCTAssertEqual(objc_RUMMethod.post.swiftType, .post)
        XCTAssertEqual(objc_RUMMethod.get.swiftType, .get)
        XCTAssertEqual(objc_RUMMethod.head.swiftType, .head)
        XCTAssertEqual(objc_RUMMethod.put.swiftType, .put)
        XCTAssertEqual(objc_RUMMethod.delete.swiftType, .delete)
        XCTAssertEqual(objc_RUMMethod.patch.swiftType, .patch)
        XCTAssertEqual(objc_RUMMethod.connect.swiftType, .connect)
        XCTAssertEqual(objc_RUMMethod.trace.swiftType, .trace)
        XCTAssertEqual(objc_RUMMethod.options.swiftType, .options)
    }
}

class DDRUMMonitorTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var config: RUM.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
        CoreRegistry.register(default: core)
        config = RUM.Configuration(applicationID: .mockAny())
    }

        override func tearDownWithError() throws {
        try core.flushAndTearDown()
        config = nil
        CoreRegistry.unregisterDefault()
        core = nil
        super.tearDown()
    }

    func testWhenSwiftRUMIsNotEnabled_thenObjcMonitorIsNotRegistered() {
        XCTAssertTrue(objc_RUMMonitor.shared().swiftRUMMonitor is NOPMonitor)
    }

    func testWhenSwiftRUMIsEnabled_thenObjcMonitorIsRegistered() {
        RUM.enable(with: config)
        XCTAssertTrue(objc_RUMMonitor.shared().swiftRUMMonitor is Monitor)
    }

    func testProvidingCurrentSessionID() throws {
        let callSessionIDCallback = expectation(description: "call session ID callback")
        var currentSessionID: String? = nil

        RUM.enable(with: config)
        let objcRUMMonitor = objc_RUMMonitor.shared()
        objcRUMMonitor.currentSessionID { sessionID in
            currentSessionID = sessionID
            callSessionIDCallback.fulfill()
        }

        waitForExpectations(timeout: 0.5)
        let sessionID = try XCTUnwrap(currentSessionID)
        XCTAssertTrue(sessionID.matches(regex: .uuidRegex))
        XCTAssertEqual(sessionID, sessionID.lowercased())
    }

    func testStoppingSession() throws {
        let callSessionIDCallback = expectation(description: "call session ID callback twice")
        callSessionIDCallback.expectedFulfillmentCount = 2
        var sessionID1: String? = nil
        var sessionID2: String? = nil

        // Given
        RUM.enable(with: config)
        let objcRUMMonitor = objc_RUMMonitor.shared()
        objcRUMMonitor.currentSessionID { sessionID in
            sessionID1 = sessionID
            callSessionIDCallback.fulfill()
        }

        // When
        objcRUMMonitor.stopSession()
        objcRUMMonitor.startView(key: "key", name: "AnyView", attributes: [:])

        // Then
        objcRUMMonitor.currentSessionID { sessionID in
            sessionID2 = sessionID
            callSessionIDCallback.fulfill()
        }

        waitForExpectations(timeout: 0.5)
        XCTAssertNotEqual(try XCTUnwrap(sessionID1), try XCTUnwrap(sessionID2))
    }

    func testSendingViewAttributes() throws {
        RUM.enable(with: config)
        let view: String = .mockRandom()
        let objcRUMMonitor = objc_RUMMonitor.shared()

        objcRUMMonitor.startView(key: view, name: .mockAny(), attributes: ["view-attribute3": "foobar"])

        objcRUMMonitor.addViewAttribute(forKey: "view-attribute1", value: "foo")
        objcRUMMonitor.addViewAttribute(forKey: "view-attribute2", value: "bar")
        objcRUMMonitor.removeViewAttribute(forKey: "view-attribute2")

        objcRUMMonitor.stopView(key: view, attributes: [:])

        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customView = try XCTUnwrap(session.views.first(where: { !$0.isApplicationLaunchView() }))
        XCTAssertEqual(customView.viewEvents.count, 1)
        XCTAssertEqual(customView.viewUpdateEvents.count, 1)

        XCTAssertEqual(customView.viewUpdateEvents[0].attribute(forKey: "view-attribute1"), "foo")
        XCTAssertNil(customView.viewUpdateEvents[0].attribute(forKey: "view-attribute2") as String?)
        XCTAssertEqual(customView.viewUpdateEvents[0].attribute(forKey: "view-attribute3"), "foobar")
    }

    func testSendingMultipleViewAttributes() throws {
        RUM.enable(with: config)
        let view: String = .mockRandom()
        let objcRUMMonitor = objc_RUMMonitor.shared()

        objcRUMMonitor.startView(key: view, name: .mockAny(), attributes: [:])

        objcRUMMonitor.addViewAttributes(
            [
                "view-attribute1": "foo",
                "view-attribute2": "bar",
                "view-attribute3": 3,
                "view-attribute4": true,
                "view-attribute5": "foobar"
            ]
        )
        objcRUMMonitor.removeViewAttributes(forKeys: ["view-attribute2", "view-attribute5"])

        objcRUMMonitor.stopView(key: view, attributes: [:])

        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customView = try XCTUnwrap(session.views.first(where: { !$0.isApplicationLaunchView() }))
        XCTAssertEqual(customView.viewEvents.count, 1)
        XCTAssertEqual(customView.viewUpdateEvents.count, 1)

        XCTAssertEqual(customView.viewUpdateEvents[0].attribute(forKey: "view-attribute1"), "foo")
        XCTAssertNil(customView.viewUpdateEvents[0].attribute(forKey: "view-attribute2") as String?)
        XCTAssertEqual(customView.viewUpdateEvents[0].attribute(forKey: "view-attribute3"), 3)
        XCTAssertEqual(customView.viewUpdateEvents[0].attribute(forKey: "view-attribute4"), true)
        XCTAssertNil(customView.viewUpdateEvents[0].attribute(forKey: "view-attribute5") as String?)
    }

    func testSendingViewEvents() throws {
        RUM.enable(with: config)

        let objcRUMMonitor = objc_RUMMonitor.shared()
        objcRUMMonitor.startView(key: "view1", name: "FirstView", attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.stopView(key: "view1", attributes: ["event-attribute2": "foo2"])
        objcRUMMonitor.startView(key: "view2", name: "SecondView", attributes: ["event-attribute1": "bar1"])
        objcRUMMonitor.addViewLoadingTime(overwrite: true)
        objcRUMMonitor.reportAppFullyDisplayed()
        objcRUMMonitor.stopView(key: "view2", attributes: ["event-attribute2": "bar2"])

        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let firstView = try XCTUnwrap(session.views.first(where: { $0.name == "FirstView" }))
        XCTAssertEqual(firstView.viewEvents.count, 1)
        XCTAssertEqual(firstView.viewUpdateEvents.count, 1)
        XCTAssertEqual(firstView.viewEvents[0].attribute(forKey: "event-attribute1"), "foo1")
        XCTAssertEqual(firstView.viewUpdateEvents[0].attribute(forKey: "event-attribute1"), "foo1")
        XCTAssertEqual(firstView.viewUpdateEvents[0].attribute(forKey: "event-attribute2"), "foo2")

        let secondView = try XCTUnwrap(session.views.first(where: { $0.name == "SecondView" }))
        XCTAssertEqual(secondView.viewEvents.count, 1)
        XCTAssertEqual(secondView.viewUpdateEvents.count, 2)
        XCTAssertEqual(secondView.viewEvents[0].attribute(forKey: "event-attribute1"), "bar1")
        XCTAssertNotNil(secondView.viewUpdateEvents[0].view.loadingTime)
        XCTAssertEqual(secondView.viewUpdateEvents[1].attribute(forKey: "event-attribute1"), "bar1")
        XCTAssertEqual(secondView.viewUpdateEvents[1].attribute(forKey: "event-attribute2"), "bar2")
    }

    func testSendingViewEventsWithTiming() throws {
        RUM.enable(with: config)
        let objcRUMMonitor = objc_RUMMonitor.shared()

        objcRUMMonitor.startView(key: "some-view", name: "SomeView", attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.addTiming(name: "timing")
        objcRUMMonitor.stopView(key: "some-view", attributes: ["event-attribute2": "foo2"])

        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let someView = try XCTUnwrap(session.views.first(where: { $0.name == "SomeView" }))
        XCTAssertEqual(someView.viewEvents.count, 1)
        XCTAssertEqual(someView.viewUpdateEvents.count, 2)

        XCTAssertEqual(someView.viewEvents[0].attribute(forKey: "event-attribute1"), "foo1")
        XCTAssertNotNil(someView.viewUpdateEvents[0].view.customTimings?.customTimingsInfo["timing"])
        XCTAssertEqual(someView.viewUpdateEvents[1].attribute(forKey: "event-attribute1"), "foo1")
        XCTAssertEqual(someView.viewUpdateEvents[1].attribute(forKey: "event-attribute2"), "foo2")
    }

    func testSendingResourceEvents() throws {
        RUM.enable(with: config)
        let objcRUMMonitor = objc_RUMMonitor.shared()

        objcRUMMonitor.startView(key: .mockAny(), name: .mockAny(), attributes: [:])

        objcRUMMonitor.startResource(resourceKey: "/resource1", url: URL(string: "https://foo.com/1")!, attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.addResourceMetrics(
            resourceKey: "/resource1",
            metrics: .mockWith(
                taskInterval: .init(start: .mockDecember15th2019At10AMUTC(), end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 2)),
                transactionMetrics: [
                    .mockBySpreadingDetailsBetween(start: .mockDecember15th2019At10AMUTC(), end: .mockDecember15th2019At10AMUTC(addingTimeInterval: 2))
                ]
            ),
            attributes: ["event-attribute2": "foo2"]
        )
        objcRUMMonitor.stopResource(resourceKey: "/resource1", response: .mockAny(), size: nil, attributes: ["event-attribute3": "foo3"])

        objcRUMMonitor.startResource(resourceKey: "/resource2", httpMethod: .get, urlString: "/some/url/2", attributes: [:])
        objcRUMMonitor.stopResource(resourceKey: "/resource2", statusCode: 333, kind: .beacon, size: 142, attributes: [:])

        objcRUMMonitor.startResource(resourceKey: "/resource3", httpMethod: .get, urlString: "/some/url/3", attributes: [:])
        objcRUMMonitor.stopResource(resourceKey: "/resource3", response: .mockAny(), size: 242, attributes: [:])

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let resourceEvents = rumEventMatchers.filterRUMEvents(ofType: RUMResourceEvent.self)
        XCTAssertEqual(resourceEvents.count, 3)

        let event1Matcher = resourceEvents[0]
        let event1: RUMResourceEvent = try event1Matcher.model()
        XCTAssertEqual(event1.resource.url, "https://foo.com/1")
        XCTAssertEqual(event1.resource.duration, 2_000_000_000)
        XCTAssertNotNil(event1.resource.dns)
        XCTAssertEqual(try event1Matcher.attribute(forKeyPath: "context.event-attribute1"), "foo1")
        XCTAssertEqual(try event1Matcher.attribute(forKeyPath: "context.event-attribute2"), "foo2")
        XCTAssertEqual(try event1Matcher.attribute(forKeyPath: "context.event-attribute3"), "foo3")

        let event2Matcher = resourceEvents[1]
        let event2: RUMResourceEvent = try event2Matcher.model()
        XCTAssertEqual(event2.resource.url, "/some/url/2")
        XCTAssertEqual(event2.resource.size, 142)
        XCTAssertEqual(event2.resource.type, .beacon)
        XCTAssertEqual(event2.resource.statusCode, 333)

        let event3: RUMResourceEvent = try resourceEvents[2].model()
        XCTAssertEqual(event3.resource.url, "/some/url/3")
        XCTAssertEqual(event3.resource.size, 242)
    }

    func testSendingErrorEvents() throws {
        RUM.enable(with: config)
        let objcRUMMonitor = objc_RUMMonitor.shared()

        objcRUMMonitor.startView(key: .mockAny(), name: .mockAny(), attributes: [:])

        let request: URLRequest = .mockAny()
        let error = ErrorMock("error details")
        objcRUMMonitor.startResource(resourceKey: "/resource1", request: request, attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.stopResourceWithError(
            resourceKey: "/resource1", error: error, response: .mockAny(), attributes: ["event-attribute2": "foo2"]
        )

        objcRUMMonitor.startResource(resourceKey: "/resource2", request: request, attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.stopResourceWithError(
            resourceKey: "/resource2", message: "error message", response: .mockAny(), attributes: ["event-attribute2": "foo2"]
        )

        objcRUMMonitor.addError(error: error, source: .custom, attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.addError(message: "error message", stack: "error stack", source: .source, attributes: [:])

        objcRUMMonitor._internal_sync_addError(NSError.mockAny(), source: .custom, attributes: [:])

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let errorEvents = rumEventMatchers.filterRUMEvents(ofType: RUMErrorEvent.self)
        XCTAssertEqual(errorEvents.count, 5)

        let event1Matcher = errorEvents[0]
        let event1: RUMErrorEvent = try event1Matcher.model()
        XCTAssertEqual(event1.error.resource?.url, request.url!.absoluteString)
        XCTAssertEqual(event1.error.type, "ErrorMock")
        XCTAssertEqual(event1.error.message, "error details")
        XCTAssertEqual(event1.error.source, .network)
        XCTAssertEqual(event1.error.stack, "error details")
        XCTAssertEqual(try event1Matcher.attribute(forKeyPath: "context.event-attribute1"), "foo1")
        XCTAssertEqual(try event1Matcher.attribute(forKeyPath: "context.event-attribute2"), "foo2")

        let event2Matcher = errorEvents[1]
        let event2: RUMErrorEvent = try event2Matcher.model()
        XCTAssertEqual(event2.error.resource?.url, request.url!.absoluteString)
        XCTAssertEqual(event2.error.message, "error message")
        XCTAssertEqual(event2.error.source, .network)
        XCTAssertNil(event2.error.stack)
        XCTAssertEqual(try event2Matcher.attribute(forKeyPath: "context.event-attribute1"), "foo1")
        XCTAssertEqual(try event2Matcher.attribute(forKeyPath: "context.event-attribute2"), "foo2")

        let event3Matcher = errorEvents[2]
        let event3: RUMErrorEvent = try event3Matcher.model()
        XCTAssertNil(event3.error.resource)
        XCTAssertEqual(event3.error.type, "ErrorMock")
        XCTAssertEqual(event3.error.message, "error details")
        XCTAssertEqual(event3.error.source, .custom)
        XCTAssertEqual(event3.error.stack, "error details")
        XCTAssertEqual(try event3Matcher.attribute(forKeyPath: "context.event-attribute1"), "foo1")

        let event4Matcher = errorEvents[3]
        let event4: RUMErrorEvent = try event4Matcher.model()
        XCTAssertEqual(event4.error.message, "error message")
        XCTAssertEqual(event4.error.source, .source)
        XCTAssertEqual(event4.error.stack, "error stack")

        let event5Matcher = errorEvents[4]
        let event5: RUMErrorEvent = try event5Matcher.model()
        XCTAssertEqual(event5.error.type, "abc - 0")
        XCTAssertEqual(event5.error.source, .custom)
        XCTAssertEqual(event5.error.message, #"Error Domain=abc Code=0 "(null)""#)
    }

    func testSendingActionEvents() throws {
        config.dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
        RUM.enable(with: config)
        let objcRUMMonitor = objc_RUMMonitor.shared()

        objcRUMMonitor.startView(key: .mockAny(), name: .mockAny(), attributes: [:])

        objcRUMMonitor.addAction(type: .tap, name: "tap action", attributes: ["event-attribute1": "foo1"])

        objcRUMMonitor.startAction(type: .swipe, name: "swipe action", attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.stopAction(type: .swipe, name: "swipe action", attributes: ["event-attribute2": "foo2"])

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let actionEvents = rumEventMatchers.filterRUMEvents(ofType: RUMActionEvent.self)
        XCTAssertEqual(actionEvents.count, 2)

        let event1Matcher = actionEvents[0]
        let event1: RUMActionEvent = try event1Matcher.model()
        XCTAssertEqual(event1.action.type, .tap)
        XCTAssertEqual(try event1Matcher.attribute(forKeyPath: "context.event-attribute1"), "foo1")

        let event2Matcher = actionEvents[1]
        let event2: RUMActionEvent = try event2Matcher.model()
        XCTAssertEqual(event2.action.type, .swipe)
        XCTAssertEqual(try event2Matcher.attribute(forKeyPath: "context.event-attribute1"), "foo1")
        XCTAssertEqual(try event2Matcher.attribute(forKeyPath: "context.event-attribute2"), "foo2")
    }

    func testSendingGlobalAttributes() throws {
        RUM.enable(with: config)
        let objcRUMMonitor = objc_RUMMonitor.shared()

        objcRUMMonitor.addAttribute(forKey: "global-attribute1", value: "foo1")
        objcRUMMonitor.addAttribute(forKey: "global-attribute2", value: "foo2")
        objcRUMMonitor.removeAttribute(forKey: "global-attribute2")

        objcRUMMonitor.startView(key: .mockAny(), name: .mockAny(), attributes: ["event-attribute1": "foo1"])

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let viewEvents = rumEventMatchers.filterRUMEvents(ofType: RUMViewEvent.self) { event in
            return event.view.name != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
        }
        XCTAssertEqual(viewEvents.count, 1)

        XCTAssertEqual(try viewEvents[0].attribute(forKeyPath: "context.global-attribute1"), "foo1")
        XCTAssertNil(try? viewEvents[0].attribute(forKeyPath: "context.global-attribute2") as String)
        XCTAssertEqual(try viewEvents[0].attribute(forKeyPath: "context.event-attribute1"), "foo1")
    }

    func testSendingMultipleGlobalAttributes() throws {
        RUM.enable(with: config)
        let objcRUMMonitor = objc_RUMMonitor.shared()

        objcRUMMonitor.addAttributes(["global-attribute1": "foo1", "global-attribute2": "foo2", "global-attribute3": 2, "global-attribute4": true])
        objcRUMMonitor.removeAttribute(forKey: "global-attribute2")

        objcRUMMonitor.startView(key: .mockAny(), name: .mockAny(), attributes: [:])

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let viewEvents = rumEventMatchers.filterRUMEvents(ofType: RUMViewEvent.self) { event in
            return event.view.name != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
        }
        XCTAssertEqual(viewEvents.count, 1)

        XCTAssertEqual(try viewEvents[0].attribute(forKeyPath: "context.global-attribute1"), "foo1")
        XCTAssertNil(try? viewEvents[0].attribute(forKeyPath: "context.global-attribute2") as String)
        XCTAssertEqual(try viewEvents[0].attribute(forKeyPath: "context.global-attribute3"), 2)
        XCTAssertEqual(try viewEvents[0].attribute(forKeyPath: "context.global-attribute4"), true)
    }

    func testEvaluatingFeatureFlags() throws {
        RUM.enable(with: config)
        let objcRUMMonitor = objc_RUMMonitor.shared()

        objcRUMMonitor.addFeatureFlagEvaluation(name: "flag1", value: "value1")
        objcRUMMonitor.addFeatureFlagEvaluation(name: "flag2", value: true)

        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let launchView = try XCTUnwrap(session.views.first(where: { $0.isApplicationLaunchView() }))
        XCTAssertEqual(launchView.viewEvents.count, 1)
        XCTAssertEqual(launchView.viewUpdateEvents.count, 2)

        let lastUpdate = try XCTUnwrap(launchView.viewUpdateEvents.last)
        XCTAssertEqual((lastUpdate.featureFlags?.featureFlagsInfo["flag1"] as? AnyCodable)?.value as? String, "value1")
        XCTAssertEqual((lastUpdate.featureFlags?.featureFlagsInfo["flag2"] as? AnyCodable)?.value as? Bool, true)
    }

    func testChangingDebugFlag() throws {
        RUM.enable(with: config)
        let objcRUMMonitor = objc_RUMMonitor.shared()

        objcRUMMonitor.debug = true
        XCTAssertTrue(objcRUMMonitor.swiftRUMMonitor.debug)

        objcRUMMonitor.debug = false
        XCTAssertFalse(objcRUMMonitor.swiftRUMMonitor.debug)
    }
}

// MARK: - Helpers

private extension RUMViewEvent {
    func attribute<T: Equatable>(forKey key: String) -> T? { (context?.contextInfo[key] as? AnyCodable)?.value as? T }
}

private extension RUMViewUpdateEvent {
    func attribute<T: Equatable>(forKey key: String) -> T? { (context?.contextInfo[key] as? AnyCodable)?.value as? T }
}
