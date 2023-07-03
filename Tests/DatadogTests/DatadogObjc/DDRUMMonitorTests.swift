/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import Datadog
@testable import DatadogObjc

class UIKitRUMViewsPredicateBridgeTests: XCTestCase {
    func testItForwardsCallToObjcPredicate() {
        class MockPredicate: DDUIKitRUMViewsPredicate {
            var didCallRUMView = false
            func rumView(for viewController: UIViewController) -> DDRUMView? {
                didCallRUMView = true
                return nil
            }
        }

        let objcPredicate = MockPredicate()

        let predicateBridge = UIKitRUMViewsPredicateBridge(objcPredicate: objcPredicate)
        _ = predicateBridge.rumView(for: mockView)

        XCTAssertTrue(objcPredicate.didCallRUMView)
    }
}

class DDRUMViewTests: XCTestCase {
    func testItCreatesSwiftRUMView() {
        let objcRUMView = DDRUMView(name: "name", attributes: ["foo": "bar"])
        XCTAssertEqual(objcRUMView.swiftView.name, "name")
        XCTAssertEqual((objcRUMView.swiftView.attributes["foo"] as? AnyEncodable)?.value as? String, "bar")
        XCTAssertEqual(objcRUMView.name, "name")
        XCTAssertEqual(objcRUMView.attributes["foo"] as? String, "bar")
    }
}

class UIKitRUMUserActionsPredicateBridgeTests: XCTestCase {
    func testItForwardsCallToObjcTouchPredicate() {
        class MockPredicate: DDUITouchRUMUserActionsPredicate {
            var didCallRUMAction = false
            func rumAction(targetView: UIView) -> DDRUMAction? {
                didCallRUMAction = true
                return nil
            }
        }

        let objcPredicate = MockPredicate()

        let predicateBridge = UIKitRUMUserActionsPredicateBridge(objcPredicate: objcPredicate)
        _ = predicateBridge.rumAction(targetView: UIView())

        XCTAssertTrue(objcPredicate.didCallRUMAction)
    }

    func testItForwardsCallToObjcPressPredicate() {
        class MockPredicate: DDUIPressRUMUserActionsPredicate {
            var didCallRUMAction = false
            func rumAction(press: UIPress.PressType, targetView: UIView) -> DDRUMAction? {
                didCallRUMAction = true
                return nil
            }
        }

        let objcPredicate = MockPredicate()

        let predicateBridge = UIKitRUMUserActionsPredicateBridge(objcPredicate: objcPredicate)
        _ = predicateBridge.rumAction(press: .select, targetView: UIView())

        XCTAssertTrue(objcPredicate.didCallRUMAction)
    }
}

class DDRUMActionTests: XCTestCase {
    func testItCreatesSwiftRUMAction() {
        let objcRUMAction = DDRUMAction(name: "name", attributes: ["foo": "bar"])
        XCTAssertEqual(objcRUMAction.swiftAction.name, "name")
        XCTAssertEqual((objcRUMAction.swiftAction.attributes["foo"] as? AnyEncodable)?.value as? String, "bar")
        XCTAssertEqual(objcRUMAction.name, "name")
        XCTAssertEqual(objcRUMAction.attributes["foo"] as? String, "bar")
    }
}

class DDRUMUserActionTypeTests: XCTestCase {
    func testMappingToSwiftRUMUserActionType() {
        XCTAssertEqual(DDRUMUserActionType.tap.swiftType, .tap)
        XCTAssertEqual(DDRUMUserActionType.scroll.swiftType, .scroll)
        XCTAssertEqual(DDRUMUserActionType.swipe.swiftType, .swipe)
        XCTAssertEqual(DDRUMUserActionType.custom.swiftType, .custom)
    }
}

class DDRUMErrorSourceTests: XCTestCase {
    func testMappingToSwiftRUMErrorSource() {
        XCTAssertEqual(DDRUMErrorSource.source.swiftType, .source)
        XCTAssertEqual(DDRUMErrorSource.network.swiftType, .network)
        XCTAssertEqual(DDRUMErrorSource.webview.swiftType, .webview)
        XCTAssertEqual(DDRUMErrorSource.console.swiftType, .console)
        XCTAssertEqual(DDRUMErrorSource.custom.swiftType, .custom)
    }
}

class DDRUMResourceKindTests: XCTestCase {
    func testMappingToSwiftRUMResourceKind() {
        XCTAssertEqual(DDRUMResourceType.image.swiftType, .image)
        XCTAssertEqual(DDRUMResourceType.xhr.swiftType, .xhr)
        XCTAssertEqual(DDRUMResourceType.beacon.swiftType, .beacon)
        XCTAssertEqual(DDRUMResourceType.css.swiftType, .css)
        XCTAssertEqual(DDRUMResourceType.document.swiftType, .document)
        XCTAssertEqual(DDRUMResourceType.fetch.swiftType, .fetch)
        XCTAssertEqual(DDRUMResourceType.font.swiftType, .font)
        XCTAssertEqual(DDRUMResourceType.js.swiftType, .js)
        XCTAssertEqual(DDRUMResourceType.media.swiftType, .media)
        XCTAssertEqual(DDRUMResourceType.other.swiftType, .other)
        XCTAssertEqual(DDRUMResourceType.native.swiftType, .native)
    }
}

class DDRUMMethodTests: XCTestCase {
    func testMappingToSwiftRUMMethod() {
        XCTAssertEqual(DDRUMMethod.post.swiftType, .post)
        XCTAssertEqual(DDRUMMethod.get.swiftType, .get)
        XCTAssertEqual(DDRUMMethod.head.swiftType, .head)
        XCTAssertEqual(DDRUMMethod.put.swiftType, .put)
        XCTAssertEqual(DDRUMMethod.delete.swiftType, .delete)
        XCTAssertEqual(DDRUMMethod.patch.swiftType, .patch)
    }
}

class DDRUMMonitorTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    /// Creates `DDRUMMonitor` instance for tests.
    /// The only difference vs. `DDRUMMonitor.initialize()` is that we disable RUM view updates sampling to get deterministic behaviour.
    private func createTestableDDRUMMonitor() throws -> DatadogObjc.DDRUMMonitor {
        let rumFeature: RUMFeature = try XCTUnwrap(core.v1.feature(RUMFeature.self), "RUM feature must be initialized before creating `RUMMonitor`")
        let swiftMonitor = RUMMonitor(
            core: core,
            dependencies: RUMScopeDependencies(
                core: core,
                rumFeature: rumFeature
            ),
            dateProvider: rumFeature.configuration.dateProvider
        )
        return DatadogObjc.DDRUMMonitor(swiftRUMMonitor: swiftMonitor)
    }

    func testSendingViewEvents() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let objcRUMMonitor = try createTestableDDRUMMonitor()
        let mockView = createMockView(viewControllerClassName: "FirstViewController")

        objcRUMMonitor.startView(viewController: mockView, name: "FirstView", attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.stopView(viewController: mockView, attributes: ["event-attribute2": "foo2"])
        objcRUMMonitor.startView(key: "view2", name: "SecondView", attributes: ["event-attribute1": "bar1"])
        objcRUMMonitor.stopView(key: "view2", attributes: ["event-attribute2": "bar2"])

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let viewEvents = rumEventMatchers.filterRUMEvents(ofType: RUMViewEvent.self) { event in
            return event.view.name != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
        }
        XCTAssertEqual(viewEvents.count, 4)

        let event1: RUMViewEvent = try viewEvents[0].model()
        let event2: RUMViewEvent = try viewEvents[1].model()
        let event3: RUMViewEvent = try viewEvents[2].model()
        let event4: RUMViewEvent = try viewEvents[3].model()
        XCTAssertEqual(event1.view.name, "FirstView")
        XCTAssertEqual(event1.view.url, "FirstViewController")
        XCTAssertEqual(event2.view.name, "FirstView")
        XCTAssertEqual(event2.view.url, "FirstViewController")
        XCTAssertEqual(event3.view.name, "SecondView")
        XCTAssertEqual(event3.view.url, "view2")
        XCTAssertEqual(event4.view.name, "SecondView")
        XCTAssertEqual(event4.view.url, "view2")
        XCTAssertEqual(try viewEvents[1].attribute(forKeyPath: "context.event-attribute1"), "foo1")
        XCTAssertEqual(try viewEvents[1].attribute(forKeyPath: "context.event-attribute2"), "foo2")
        XCTAssertEqual(try viewEvents[3].attribute(forKeyPath: "context.event-attribute1"), "bar1")
        XCTAssertEqual(try viewEvents[3].attribute(forKeyPath: "context.event-attribute2"), "bar2")
    }

    func testSendingViewEventsWithTiming() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let objcRUMMonitor = try createTestableDDRUMMonitor()

        objcRUMMonitor.startView(viewController: mockView, name: "SomeView", attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.addTiming(name: "timing")
        objcRUMMonitor.stopView(viewController: mockView, attributes: ["event-attribute2": "foo2"])

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let viewEvents = rumEventMatchers.filterRUMEvents(ofType: RUMViewEvent.self) { event in
            return event.view.name != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
        }
        XCTAssertEqual(viewEvents.count, 3)

        let event1: RUMViewEvent = try viewEvents[0].model()
        let event2: RUMViewEvent = try viewEvents[1].model()
        XCTAssertEqual(event1.view.name, "SomeView")
        XCTAssertEqual(event2.view.name, "SomeView")
        XCTAssertEqual(try viewEvents.first?.attribute(forKeyPath: "context.event-attribute1"), "foo1")
        XCTAssertEqual(try viewEvents.last?.attribute(forKeyPath: "context.event-attribute1"), "foo1")
        XCTAssertEqual(try viewEvents.last?.attribute(forKeyPath: "context.event-attribute2"), "foo2")
        XCTAssertNotNil(try? viewEvents.last?.timing(named: "timing"))
    }

    func testSendingResourceEvents() throws {
        guard #available(iOS 13, *) else {
            return // `URLSessionTaskMetrics` mocking doesn't work prior to iOS 13.0
        }

        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let objcRUMMonitor = try createTestableDDRUMMonitor()

        objcRUMMonitor.startView(viewController: mockView, name: .mockAny(), attributes: [:])

        objcRUMMonitor.startResourceLoading(resourceKey: "/resource1", url: URL(string: "https://foo.com/1")!, attributes: ["event-attribute1": "foo1"])
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
        objcRUMMonitor.stopResourceLoading(resourceKey: "/resource1", response: .mockAny(), size: nil, attributes: ["event-attribute3": "foo3"])

        objcRUMMonitor.startResourceLoading(resourceKey: "/resource2", httpMethod: .get, urlString: "/some/url/2", attributes: [:])
        objcRUMMonitor.stopResourceLoading(resourceKey: "/resource2", statusCode: 333, kind: .beacon, size: 142, attributes: [:])

        objcRUMMonitor.startResourceLoading(resourceKey: "/resource3", httpMethod: .get, urlString: "/some/url/3", attributes: [:])
        objcRUMMonitor.stopResourceLoading(resourceKey: "/resource3", response: .mockAny(), size: 242, attributes: [:])

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
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let objcRUMMonitor = try createTestableDDRUMMonitor()

        objcRUMMonitor.startView(viewController: mockView, name: .mockAny(), attributes: [:])

        let request: URLRequest = .mockAny()
        let error = ErrorMock("error details")
        objcRUMMonitor.startResourceLoading(resourceKey: "/resource1", request: request, attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.stopResourceLoadingWithError(
            resourceKey: "/resource1", error: error, response: .mockAny(), attributes: ["event-attribute2": "foo2"]
        )

        objcRUMMonitor.startResourceLoading(resourceKey: "/resource2", request: request, attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.stopResourceLoadingWithError(
            resourceKey: "/resource2", errorMessage: "error message", response: .mockAny(), attributes: ["event-attribute2": "foo2"]
        )

        objcRUMMonitor.addError(error: error, source: .custom, attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.addError(message: "error message", source: .source, stack: "error stack", attributes: [:])

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let errorEvents = rumEventMatchers.filterRUMEvents(ofType: RUMErrorEvent.self)
        XCTAssertEqual(errorEvents.count, 4)

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
    }

    func testSendingActionEvents() throws {
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
            )
        )
        core.register(feature: rum)

        let objcRUMMonitor = try createTestableDDRUMMonitor()

        objcRUMMonitor.startView(viewController: mockView, name: .mockAny(), attributes: [:])

        objcRUMMonitor.addUserAction(type: .tap, name: "tap action", attributes: ["event-attribute1": "foo1"])

        objcRUMMonitor.startUserAction(type: .swipe, name: "swipe action", attributes: ["event-attribute1": "foo1"])
        objcRUMMonitor.stopUserAction(type: .swipe, name: "swipe action", attributes: ["event-attribute2": "foo2"])

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let actionEvents = rumEventMatchers.filterRUMEvents(ofType: RUMActionEvent.self)
        XCTAssertEqual(actionEvents.count, 3)

        let event1Matcher = actionEvents[0]
        let event1: RUMActionEvent = try event1Matcher.model()
        XCTAssertEqual(event1.action.type, .applicationStart)

        let event2Matcher = actionEvents[1]
        let event2: RUMActionEvent = try event2Matcher.model()
        XCTAssertEqual(event2.action.type, .tap)
        XCTAssertEqual(try event2Matcher.attribute(forKeyPath: "context.event-attribute1"), "foo1")

        let event3Matcher = actionEvents[2]
        let event3: RUMActionEvent = try event3Matcher.model()
        XCTAssertEqual(event3.action.type, .swipe)
        XCTAssertEqual(try event3Matcher.attribute(forKeyPath: "context.event-attribute1"), "foo1")
        XCTAssertEqual(try event3Matcher.attribute(forKeyPath: "context.event-attribute2"), "foo2")
    }

    func testSendingGlobalAttributes() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let objcRUMMonitor = try createTestableDDRUMMonitor()
        objcRUMMonitor.addAttribute(forKey: "global-attribute1", value: "foo1")
        objcRUMMonitor.addAttribute(forKey: "global-attribute2", value: "foo2")
        objcRUMMonitor.removeAttribute(forKey: "global-attribute2")

        objcRUMMonitor.startView(viewController: mockView, name: .mockAny(), attributes: ["event-attribute1": "foo1"])

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let viewEvents = rumEventMatchers.filterRUMEvents(ofType: RUMViewEvent.self) { event in
            return event.view.name != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
        }
        XCTAssertEqual(viewEvents.count, 1)

        XCTAssertEqual(try viewEvents[0].attribute(forKeyPath: "context.global-attribute1"), "foo1")
        XCTAssertNil(try? viewEvents[0].attribute(forKeyPath: "context.global-attribute2") as String)
        XCTAssertEqual(try viewEvents[0].attribute(forKeyPath: "context.event-attribute1"), "foo1")
    }
}
