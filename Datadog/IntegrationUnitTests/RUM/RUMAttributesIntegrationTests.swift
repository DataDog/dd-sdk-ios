/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM
@testable import DatadogInternal

final class RUMAttributesIntegrationTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var rumConfig: RUM.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
        rumConfig = RUM.Configuration(applicationID: .mockAny())
    }

        override func tearDownWithError() throws {
        try core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testWhenViewStops_theViewEvents_haveTheCorrectGlobalAttributes() throws {
        // Given
        let initialAttributes: [AttributeKey: AttributeValue] = ["key1": "value1", "key2": "value2", "key3": "value3"]
        let firstViewName = "FirstView"
        let secondViewName = "SecondView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.addAttributes(initialAttributes)
        monitor.startView(key: "key", name: firstViewName)
        monitor.removeAttributes(forKeys: Array(initialAttributes.keys))
        monitor.startView(key: "key", name: secondViewName)

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let firstView = try XCTUnwrap(session.views.first(where: { $0.name == firstViewName }))
        firstView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, 3)
        }

        let secondView = try XCTUnwrap(session.views.first(where: { $0.name == secondViewName }))
        secondView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, 0)
        }
    }

    func testWhenViewStops_theViewAttributesAreNotUpdated_withGlobalAttributes() throws {
        // Given
        let initialAttributes: [AttributeKey: AttributeValue] = ["key1": "value1", "key2": "value2"]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: initialAttributes)
        monitor.stopView(key: "key")
        monitor.addAttribute(forKey: "additionalKey", value: "additionalValue")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(session.views.count, 2)

        let applicationView = try XCTUnwrap(session.views.first(where: { $0.isApplicationLaunchView() }))
        applicationView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, 0)
        }

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))

        customView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, initialAttributes.count)

            initialAttributes.forEach {
                XCTAssertEqual(viewEvent.attribute(forKey: $0.key), $0.value as? String)
            }
        }
    }

    func testWhenViewRelyingOnGlobalAttributes_doesNotUpdateTheViewAttributes_afterStopView() throws {
        // Given
        let initialAttributes: [AttributeKey: AttributeValue] = ["key1": "value1", "key2": "value2"]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName)
        monitor.addAttribute(forKey: "key1", value: initialAttributes["key1"] as? String)
        monitor.addAttribute(forKey: "key2", value: initialAttributes["key2"] as? String)
        monitor.stopView(key: "key")
        monitor.addAttribute(forKey: "additionalKey", value: "additionalValue")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(session.views.count, 2)

        let applicationView = try XCTUnwrap(session.views.first(where: { $0.isApplicationLaunchView() }))
        applicationView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, 0)
        }

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))
        let lastViewEvent = customView.viewEvents.last

        XCTAssertEqual(lastViewEvent?.numberOfAttributes, initialAttributes.count)

        initialAttributes.forEach {
            XCTAssertEqual(lastViewEvent?.attribute(forKey: $0.key), $0.value as? String)
        }
    }

    func testWhenSessionEnds_theViewAttributesAreNotUpdated_withNewCommands() throws {
        // Given
        let initialAttributes: [AttributeKey: AttributeValue] = ["key1": "value1", "key2": "value2"]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: initialAttributes)
        monitor.stopSession()
        monitor.addAttribute(forKey: "additionalKey", value: "additionalValue")
        monitor.startView(key: "key", name: viewName, attributes: initialAttributes)
        monitor.stopView(key: "key", attributes: ["anotherAdditionalKey": "anotherAdditionalValue"])

        // Then
        let sessions = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeTwo()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(sessions.0.views.count, 2)
        // It should have only `MyView`
        XCTAssertEqual(sessions.1.views.count, 1)

        let applicationView = try XCTUnwrap(sessions.0.views.first(where: { $0.isApplicationLaunchView() }))
        applicationView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, 0)
        }

        // Session 0
        var customView = try XCTUnwrap(sessions.0.views.first(where: { $0.name == viewName }))

        customView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, initialAttributes.count)

            initialAttributes.forEach {
                XCTAssertEqual(viewEvent.attribute(forKey: $0.key), $0.value as? String)
            }
        }

        // Session 1
        customView = try XCTUnwrap(sessions.1.views.first(where: { $0.name == viewName }))

        let startViewEvent = try XCTUnwrap(customView.viewEvents.first)
        XCTAssertEqual(startViewEvent.numberOfAttributes, 3)

        initialAttributes.forEach {
            XCTAssertEqual(startViewEvent.attribute(forKey: $0.key), $0.value as? String)
        }
        XCTAssertEqual(startViewEvent.attribute(forKey: "additionalKey"), "additionalValue")

        let stopViewEvent = try XCTUnwrap(customView.viewEvents.last)
        XCTAssertEqual(stopViewEvent.numberOfAttributes, 4)
        initialAttributes.forEach {
            XCTAssertEqual(startViewEvent.attribute(forKey: $0.key), $0.value as? String)
        }
        XCTAssertEqual(stopViewEvent.attribute(forKey: "additionalKey"), "additionalValue")
        XCTAssertEqual(stopViewEvent.attribute(forKey: "anotherAdditionalKey"), "anotherAdditionalValue")
    }

    func testViewAttributes_havePrecedenceOverGlobalAttributes() throws {
        // Given
        let initialAttributes: [AttributeKey: AttributeValue] = ["sameKey": "value1", "key2": "value2"]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.addAttribute(forKey: "sameKey", value: "globalValue")
        monitor.startView(key: "key", name: viewName, attributes: initialAttributes)
        monitor.stopView(key: "key", attributes: initialAttributes)

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let applicationView = try XCTUnwrap(session.views.first(where: { $0.isApplicationLaunchView() }))
        let firstViewEvent = applicationView.viewEvents.first
        let lastViewEvent = applicationView.viewEvents.last
        XCTAssertEqual(firstViewEvent?.numberOfAttributes, 0)
        XCTAssertEqual(lastViewEvent?.numberOfAttributes, 1)

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))

        customView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, initialAttributes.count)

            initialAttributes.forEach {
                XCTAssertEqual(viewEvent.attribute(forKey: $0.key), $0.value as? String)
            }
        }
    }

    func testViewAttributes_haveGlobalAttributesOverWritingViewAttributes_whenNoViewAttributesArePassed() throws {
        // Given
        let initialAttributes: [AttributeKey: AttributeValue] = ["sameKey": "value1", "key2": "value2"]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.addAttribute(forKey: "sameKey", value: "globalValue")
        monitor.startView(key: "key", name: viewName, attributes: initialAttributes)
        monitor.stopView(key: "key")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let applicationView = try XCTUnwrap(session.views.first(where: { $0.isApplicationLaunchView() }))
        let firstViewEvent = applicationView.viewEvents.first
        let lastViewEvent = applicationView.viewEvents.last
        XCTAssertEqual(firstViewEvent?.numberOfAttributes, 0)
        XCTAssertEqual(lastViewEvent?.numberOfAttributes, 1)

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))

        let firstCustomViewEvent = customView.viewEvents.first
        let lastCustomViewEvent = customView.viewEvents.last

        XCTAssertEqual(firstCustomViewEvent?.numberOfAttributes, initialAttributes.count)
        initialAttributes.forEach {
            XCTAssertEqual(firstCustomViewEvent?.attribute(forKey: $0.key), $0.value as? String)
        }

        XCTAssertEqual(lastCustomViewEvent?.attribute(forKey: "key2"), "value2")
        XCTAssertEqual(lastCustomViewEvent?.attribute(forKey: "sameKey"), "globalValue")
    }

    func testWhenViewReceivesActions_theViewAttributesAreNotUpdated_withActionAttributes() throws {
        // Given
        let initialAttributes: [AttributeKey: AttributeValue] = ["key1": "value1", "key2": "value2"]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: initialAttributes)
        monitor.addAction(type: .custom, name: "drag", attributes: ["additionalKey": "additionalValue"])
        monitor.stopView(key: "key")
        monitor.addAction(type: .tap, name: "tap", attributes: ["anotherAdditionalKey": "anotherAdditionalValue"])

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(session.views.count, 2)

        let applicationView = try XCTUnwrap(session.views.first(where: { $0.isApplicationLaunchView() }))
        applicationView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, 0)
        }

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))

        customView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, initialAttributes.count)

            initialAttributes.forEach {
                XCTAssertEqual(viewEvent.attribute(forKey: $0.key), $0.value as? String)
            }
        }
    }

    func testWhenViewReceivesResources_theViewAttributesAreNotUpdated_withResourceAttributes() throws {
        // Given
        let initialAttributes: [AttributeKey: AttributeValue] = ["key1": "value1", "key2": "value2"]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: initialAttributes)
        monitor.startResource(
            resourceKey: "resourceKey",
            httpMethod: .get,
            urlString: .mockAny(),
            attributes: ["additionalKey": "additionalValue"]
        )

        monitor.stopResource(
            resourceKey: "resourceKey",
            statusCode: 200,
            kind: .fetch,
            size: nil,
            attributes: ["resourceAdditionalKey": "resourceAdditionalValue"]
        )

        monitor.stopView(key: "key")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(session.views.count, 2)

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))

        customView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, initialAttributes.count)

            initialAttributes.forEach {
                XCTAssertEqual(viewEvent.attribute(forKey: $0.key), $0.value as? String)
            }
        }
    }

    func testGlobalAttributes_areAddedToActionEvents() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.addAttribute(forKey: "sameKey", value: "value1")
        monitor.addAction(type: .custom, name: "drag")
        monitor.addAction(type: .swipe, name: "swipe up")
        monitor.addAttribute(forKey: "key2", value: "value2")
        monitor.stopAction(type: .swipe, name: "swipe up", attributes: ["sameKey": "value3"] )

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(session.views.count, 1)

        let applicationView = try XCTUnwrap(session.views.first(where: { $0.isApplicationLaunchView() }))
        XCTAssertEqual(applicationView.actionEvents.count, 2)

        let firstActionEvent = applicationView.actionEvents[0]
        XCTAssertEqual(firstActionEvent.numberOfAttributes, 1)
        XCTAssertEqual(firstActionEvent.attribute(forKey: "sameKey"), "value1")

        let lastActionEvent = applicationView.actionEvents[1]
        XCTAssertEqual(lastActionEvent.numberOfAttributes, 2)
        XCTAssertEqual(lastActionEvent.attribute(forKey: "sameKey"), "value3")
        XCTAssertEqual(lastActionEvent.attribute(forKey: "key2"), "value2")
    }

    func testGlobalAttributes_areAddedToResourceEvents() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.addAttribute(forKey: "sameKey", value: "value1")

        monitor.startResource(
            resourceKey: "resource1",
            httpMethod: .get,
            urlString: .mockAny(),
            attributes: ["key1": "value1"]
        )
        monitor.addAttribute(forKey: "key2", value: "value2")
        monitor.stopResource(
            resourceKey: "resource1",
            statusCode: 500,
            kind: .fetch,
            size: nil
        )

        monitor.startResource(
            resourceKey: "resource2",
            httpMethod: .get,
            urlString: .mockAny()
        )
        monitor.addAttribute(forKey: "key3", value: "value3")
        monitor.stopResource(
            resourceKey: "resource2",
            statusCode: 200,
            kind: .fetch,
            size: nil,
            attributes: ["sameKey": "value4"]
        )

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(session.views.count, 1)

        let applicationView = try XCTUnwrap(session.views.first(where: { $0.isApplicationLaunchView() }))
        XCTAssertEqual(applicationView.resourceEvents.count, 2)

        let firstResourceEvent = applicationView.resourceEvents[0]
        XCTAssertEqual(firstResourceEvent.numberOfAttributes, 3)
        XCTAssertEqual(firstResourceEvent.attribute(forKey: "sameKey"), "value1")
        XCTAssertEqual(firstResourceEvent.attribute(forKey: "key1"), "value1")
        XCTAssertEqual(firstResourceEvent.attribute(forKey: "key2"), "value2")

        let lastResourceEvent = applicationView.resourceEvents[1]
        XCTAssertEqual(lastResourceEvent.numberOfAttributes, 3)
        XCTAssertEqual(lastResourceEvent.attribute(forKey: "sameKey"), "value4")
        XCTAssertEqual(lastResourceEvent.attribute(forKey: "key2"), "value2")
        XCTAssertEqual(lastResourceEvent.attribute(forKey: "key3"), "value3")
    }

    func testGlobalAttributes_areAddedToErrorEvents() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.addAttribute(forKey: "sameKey", value: "value1")

        monitor.addError(error: ErrorMock(), source: .custom, attributes: ["key2": "value2"])
        monitor.addAttribute(forKey: "key3", value: "value3")
        monitor.addError(message: .mockAny(), type: nil, stack: nil, source: .custom, attributes: ["sameKey": "value4"], file: nil, line: nil)

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(session.views.count, 1)

        let applicationView = try XCTUnwrap(session.views.first(where: { $0.isApplicationLaunchView() }))
        XCTAssertEqual(applicationView.errorEvents.count, 2)

        let firstErrorEvent = applicationView.errorEvents[0]
        XCTAssertEqual(firstErrorEvent.numberOfAttributes, 2)
        XCTAssertEqual(firstErrorEvent.attribute(forKey: "sameKey"), "value1")
        XCTAssertEqual(firstErrorEvent.attribute(forKey: "key2"), "value2")

        let lastResourceEvent = applicationView.errorEvents[1]
        XCTAssertEqual(lastResourceEvent.numberOfAttributes, 2)
        XCTAssertEqual(lastResourceEvent.attribute(forKey: "key3"), "value3")
        XCTAssertEqual(lastResourceEvent.attribute(forKey: "sameKey"), "value4")
    }
}

private extension RUMViewEvent {
    var numberOfAttributes: Int { context?.contextInfo.count ?? 0 }

    func attribute<T: Equatable>(forKey key: String) -> T? { (context?.contextInfo[key] as? AnyCodable)?.value as? T }
}

private extension RUMActionEvent {
    var numberOfAttributes: Int { context?.contextInfo.count ?? 0 }

    func attribute<T: Equatable>(forKey key: String) -> T? { (context?.contextInfo[key] as? AnyCodable)?.value as? T }
}

private extension RUMResourceEvent {
    var numberOfAttributes: Int { context?.contextInfo.count ?? 0 }

    func attribute<T: Equatable>(forKey key: String) -> T? { (context?.contextInfo[key] as? AnyCodable)?.value as? T }
}

private extension RUMErrorEvent {
    var numberOfAttributes: Int { context?.contextInfo.count ?? 0 }

    func attribute<T: Equatable>(forKey key: String) -> T? { (context?.contextInfo[key] as? AnyCodable)?.value as? T }
}
