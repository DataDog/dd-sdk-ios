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

    // MARK: - Global Attributes

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
        XCTAssertEqual(firstView.viewEvents[0].numberOfAttributes, 3) // startView
        XCTAssertEqual(firstView.viewEvents[1].numberOfAttributes, 0) // stopView

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

    func testWhenGlobalAttributesAreRemoved_eventsDoNotHaveThem() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)
        let viewName = "MyView"
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: ["viewKey": "viewValue"])
        monitor.addAttribute(forKey: "globalKey", value: "globalValue")
        monitor.addTiming(name: "addViewTiming")
        monitor.removeAttribute(forKey: "globalKey")
        monitor.stopView(key: "key")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))
        XCTAssertEqual(customView.viewEvents.count, 3)
        XCTAssertEqual(customView.viewEvents[0].numberOfAttributes, 1)
        XCTAssertEqual(customView.viewEvents[0].attribute(forKey: "viewKey"), "viewValue")

        XCTAssertEqual(customView.viewEvents[1].numberOfAttributes, 2)
        XCTAssertEqual(customView.viewEvents[1].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(customView.viewEvents[1].attribute(forKey: "globalKey"), "globalValue")

        XCTAssertEqual(customView.viewEvents[2].numberOfAttributes, 1)
        XCTAssertEqual(customView.viewEvents[2].attribute(forKey: "viewKey"), "viewValue")
    }

    // MARK: - View Attributes

    func testViewAttributesManagementOnUserActions_fromGlobalMonitor() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)
        let viewName = "MyView"
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName)

        monitor.addViewAttribute(forKey: "viewKey", value: "viewValue")
        monitor.addAction(type: .custom, name: "tap")

        monitor.addViewAttributes(["newViewKey": "newViewValue", "anotherViewKey": "anotherViewValue"])
        monitor.removeViewAttribute(forKey: "viewKey")
        monitor.addAction(type: .custom, name: "tap2")

        monitor.removeViewAttributes(forKeys: ["newViewKey", "anotherViewKey"])
        monitor.stopView(key: "key")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))
        XCTAssertEqual(customView.viewEvents.count, 4)
        XCTAssertEqual(customView.viewEvents[0].numberOfAttributes, 0)
        XCTAssertEqual(customView.viewEvents[1].numberOfAttributes, 1)
        XCTAssertEqual(customView.viewEvents[1].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(customView.viewEvents[2].numberOfAttributes, 2)
        XCTAssertEqual(customView.viewEvents[2].attribute(forKey: "newViewKey"), "newViewValue")
        XCTAssertEqual(customView.viewEvents[2].attribute(forKey: "anotherViewKey"), "anotherViewValue")
        XCTAssertEqual(customView.viewEvents[3].numberOfAttributes, 0)

        XCTAssertEqual(customView.actionEvents.count, 2)
        XCTAssertEqual(customView.actionEvents[0].numberOfAttributes, 1)
        XCTAssertEqual(customView.actionEvents[0].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(customView.actionEvents[1].numberOfAttributes, 2)
        XCTAssertEqual(customView.actionEvents[1].attribute(forKey: "newViewKey"), "newViewValue")
        XCTAssertEqual(customView.actionEvents[1].attribute(forKey: "anotherViewKey"), "anotherViewValue")
    }

    func testViewAttributesManagementOnResources_fromGlobalMonitor() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)
        let viewName = "MyView"
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName)

        monitor.addViewAttribute(forKey: "viewKey", value: "viewValue")
        monitor.startResource(resourceKey: "resourceKey", url: .mockAny())
        monitor.stopResource(resourceKey: "resourceKey", kind: .fetch)

        monitor.addViewAttributes(["newViewKey": "newViewValue", "anotherViewKey": "anotherViewValue"])
        monitor.removeViewAttribute(forKey: "viewKey")
        monitor.startResource(resourceKey: "resourceKey", url: .mockAny())
        monitor.stopResource(resourceKey: "resourceKey", kind: .fetch)

        monitor.removeViewAttributes(forKeys: ["newViewKey", "anotherViewKey"])
        monitor.stopView(key: "key")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))
        XCTAssertEqual(customView.viewEvents.count, 4)
        XCTAssertEqual(customView.viewEvents[0].numberOfAttributes, 0)
        XCTAssertEqual(customView.viewEvents[1].numberOfAttributes, 1)
        XCTAssertEqual(customView.viewEvents[1].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(customView.viewEvents[2].numberOfAttributes, 2)
        XCTAssertEqual(customView.viewEvents[2].attribute(forKey: "newViewKey"), "newViewValue")
        XCTAssertEqual(customView.viewEvents[2].attribute(forKey: "anotherViewKey"), "anotherViewValue")
        XCTAssertEqual(customView.viewEvents[3].numberOfAttributes, 0)

        XCTAssertEqual(customView.resourceEvents.count, 2)
        XCTAssertEqual(customView.resourceEvents[0].numberOfAttributes, 1)
        XCTAssertEqual(customView.resourceEvents[0].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(customView.resourceEvents[1].numberOfAttributes, 2)
        XCTAssertEqual(customView.resourceEvents[1].attribute(forKey: "newViewKey"), "newViewValue")
        XCTAssertEqual(customView.resourceEvents[1].attribute(forKey: "anotherViewKey"), "anotherViewValue")
    }

    func testViewAttributesManagementOnErrors_fromGlobalMonitor() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)
        let viewName = "MyView"
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName)

        monitor.addViewAttribute(forKey: "viewKey", value: "viewValue")
        monitor.addError(error: ErrorMock(), source: .custom)

        monitor.addViewAttributes(["newViewKey": "newViewValue", "anotherViewKey": "anotherViewValue"])
        monitor.removeViewAttribute(forKey: "viewKey")
        monitor.addError(message: .mockAny(), type: nil, stack: nil, source: .custom, file: nil, line: nil)

        monitor.removeViewAttributes(forKeys: ["newViewKey", "anotherViewKey"])
        monitor.stopView(key: "key")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))
        XCTAssertEqual(customView.viewEvents.count, 4)
        XCTAssertEqual(customView.viewEvents[0].numberOfAttributes, 0)
        XCTAssertEqual(customView.viewEvents[1].numberOfAttributes, 1)
        XCTAssertEqual(customView.viewEvents[1].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(customView.viewEvents[2].numberOfAttributes, 2)
        XCTAssertEqual(customView.viewEvents[2].attribute(forKey: "newViewKey"), "newViewValue")
        XCTAssertEqual(customView.viewEvents[2].attribute(forKey: "anotherViewKey"), "anotherViewValue")
        XCTAssertEqual(customView.viewEvents[3].numberOfAttributes, 0)

        XCTAssertEqual(customView.errorEvents.count, 2)
        XCTAssertEqual(customView.errorEvents[0].numberOfAttributes, 1)
        XCTAssertEqual(customView.errorEvents[0].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(customView.errorEvents[1].numberOfAttributes, 2)
        XCTAssertEqual(customView.errorEvents[1].attribute(forKey: "newViewKey"), "newViewValue")
        XCTAssertEqual(customView.errorEvents[1].attribute(forKey: "anotherViewKey"), "anotherViewValue")
    }

    func testViewAttributesManagementOnLong_fromGlobalMonitor() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)
        let viewName = "MyView"
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName)

        monitor.addViewAttribute(forKey: "viewKey", value: "viewValue")
        monitor._internal?.addLongTask(at: Date(), duration: 1.0)

        monitor.addViewAttributes(["newViewKey": "newViewValue", "anotherViewKey": "anotherViewValue"])
        monitor.removeViewAttribute(forKey: "viewKey")
        monitor._internal?.addLongTask(at: Date(), duration: 1.0)

        monitor.removeViewAttributes(forKeys: ["newViewKey", "anotherViewKey"])
        monitor.stopView(key: "key")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))
        XCTAssertEqual(customView.viewEvents.count, 4)
        XCTAssertEqual(customView.viewEvents[0].numberOfAttributes, 0)
        XCTAssertEqual(customView.viewEvents[1].numberOfAttributes, 1)
        XCTAssertEqual(customView.viewEvents[1].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(customView.viewEvents[2].numberOfAttributes, 2)
        XCTAssertEqual(customView.viewEvents[2].attribute(forKey: "newViewKey"), "newViewValue")
        XCTAssertEqual(customView.viewEvents[2].attribute(forKey: "anotherViewKey"), "anotherViewValue")
        XCTAssertEqual(customView.viewEvents[3].numberOfAttributes, 0)

        XCTAssertEqual(customView.longTaskEvents.count, 2)
        XCTAssertEqual(customView.longTaskEvents[0].numberOfAttributes, 1)
        XCTAssertEqual(customView.longTaskEvents[0].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(customView.longTaskEvents[1].numberOfAttributes, 2)
        XCTAssertEqual(customView.longTaskEvents[1].attribute(forKey: "newViewKey"), "newViewValue")
        XCTAssertEqual(customView.longTaskEvents[1].attribute(forKey: "anotherViewKey"), "anotherViewValue")
    }

    func testGlobalAndViewAttributes_propagatingToChildScopes() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)
        let viewName = "MyView"
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: ["viewKey": "viewValue"])
        monitor.addAttribute(forKey: "globalKey", value: "globalValue")
        monitor.addAction(type: .custom, name: "tap", attributes: ["actionKey": "actionValue"])
        monitor.addViewAttribute(forKey: "newViewKey", value: "newViewValue")

        monitor.startResource(
            resourceKey: "resourceKey",
            httpMethod: .get,
            urlString: .mockAny(),
            attributes: ["resourceKey": "resourceValue"]
        )

        monitor.stopResource(
            resourceKey: "resourceKey",
            statusCode: 200,
            kind: .fetch,
            size: nil,
            attributes: ["resourceKey": "resourceValue"]
        )

        monitor.stopView(key: "key")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))
        XCTAssertEqual(customView.viewEvents.count, 4)
        XCTAssertEqual(customView.viewEvents[0].numberOfAttributes, 1)
        XCTAssertEqual(customView.viewEvents[0].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(customView.viewEvents[1].numberOfAttributes, 2)
        XCTAssertEqual(customView.viewEvents[1].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(customView.viewEvents[1].attribute(forKey: "globalKey"), "globalValue")
        customView.viewEvents.dropFirst().dropFirst().forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, 3)
            XCTAssertEqual(viewEvent.attribute(forKey: "viewKey"), "viewValue")
            XCTAssertEqual(viewEvent.attribute(forKey: "newViewKey"), "newViewValue")
            XCTAssertEqual(viewEvent.attribute(forKey: "globalKey"), "globalValue")
        }

        customView.actionEvents.forEach { actionEvent in
            XCTAssertEqual(actionEvent.numberOfAttributes, 3)
            XCTAssertEqual(actionEvent.attribute(forKey: "viewKey"), "viewValue")
            XCTAssertEqual(actionEvent.attribute(forKey: "actionKey"), "actionValue")
            XCTAssertEqual(actionEvent.attribute(forKey: "globalKey"), "globalValue")
        }

        customView.resourceEvents.forEach { resourceEvent in
            XCTAssertEqual(resourceEvent.numberOfAttributes, 4)
            XCTAssertEqual(resourceEvent.attribute(forKey: "viewKey"), "viewValue")
            XCTAssertEqual(resourceEvent.attribute(forKey: "newViewKey"), "newViewValue")
            XCTAssertEqual(resourceEvent.attribute(forKey: "resourceKey"), "resourceValue")
            XCTAssertEqual(resourceEvent.attribute(forKey: "globalKey"), "globalValue")
        }
    }

    func testViewAttributes_arePropagatedToChildScopes() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)
        let viewName = "MyView"
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: ["viewKey": "viewValue"])
        monitor.addAttribute(forKey: "globalKey", value: "globalValue")
        monitor.addAction(type: .custom, name: "tap", attributes: ["actionKey": "actionValue"])

        monitor.startResource(
            resourceKey: "resourceKey",
            httpMethod: .get,
            urlString: .mockAny(),
            attributes: ["resourceKey": "resourceValue"]
        )

        monitor.stopResource(
            resourceKey: "resourceKey",
            statusCode: 200,
            kind: .fetch,
            size: nil,
            attributes: ["resourceKey": "resourceValue"]
        )

        monitor.stopView(key: "key")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))
        XCTAssertEqual(customView.viewEvents.count, 4)
        XCTAssertEqual(customView.viewEvents[0].numberOfAttributes, 1)
        XCTAssertEqual(customView.viewEvents[0].attribute(forKey: "viewKey"), "viewValue")
        customView.viewEvents.dropFirst().forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, 2)
            XCTAssertEqual(viewEvent.attribute(forKey: "viewKey"), "viewValue")
            XCTAssertEqual(viewEvent.attribute(forKey: "globalKey"), "globalValue")
        }

        customView.actionEvents.forEach { actionEvent in
            XCTAssertEqual(actionEvent.numberOfAttributes, 3)
            XCTAssertEqual(actionEvent.attribute(forKey: "viewKey"), "viewValue")
            XCTAssertEqual(actionEvent.attribute(forKey: "actionKey"), "actionValue")
            XCTAssertEqual(actionEvent.attribute(forKey: "globalKey"), "globalValue")
        }

        customView.resourceEvents.forEach { resourceEvent in
            XCTAssertEqual(resourceEvent.numberOfAttributes, 3)
            XCTAssertEqual(resourceEvent.attribute(forKey: "viewKey"), "viewValue")
            XCTAssertEqual(resourceEvent.attribute(forKey: "resourceKey"), "resourceValue")
            XCTAssertEqual(resourceEvent.attribute(forKey: "globalKey"), "globalValue")
        }
    }

    // MARK: - Precedences

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

    func testLocalAttributesHavePrecendence_overViewAttributes_overGlobalAttributes() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)
        let viewName = "viewName"
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.addAttributes(["key": "globalValue"])
        monitor.startView(key: "key", name: viewName, attributes: ["key": "viewValue"])
        monitor.addAction(type: .custom, name: "tap", attributes: ["key": "actionValue"])
        monitor.startResource(
            resourceKey: "resourceKey",
            httpMethod: .get,
            urlString: .mockAny(),
            attributes: ["key": "resourceValue"]
        )

        monitor.stopResource(
            resourceKey: "resourceKey",
            statusCode: 200,
            kind: .fetch,
            size: nil,
            attributes: ["key": "resourceValue"]
        )

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))
        XCTAssertEqual(customView.viewEvents.count, 3)
        customView.viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, 1)
            XCTAssertEqual(viewEvent.attribute(forKey: "key"), "viewValue")
        }

        customView.actionEvents.forEach { actionEvent in
            XCTAssertEqual(actionEvent.numberOfAttributes, 1)
            XCTAssertEqual(actionEvent.attribute(forKey: "key"), "actionValue")
        }

        customView.resourceEvents.forEach { resourceEvent in
            XCTAssertEqual(resourceEvent.numberOfAttributes, 1)
            XCTAssertEqual(resourceEvent.attribute(forKey: "key"), "resourceValue")
        }
    }

    func testTimingAttributes_inheritViewAttributes_overGlobalAttributes() throws {
        // Given
        RUM.enable(with: rumConfig, in: core)
        let viewName = "viewName"
        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: ["key": "viewValue"])
        monitor.addAttributes(["key": "globalValue"])
        monitor.addTiming(name: "addViewTiming")
        monitor.addAction(type: .custom, name: "tap", attributes: ["key": "actionValue"])
        monitor.startResource(
            resourceKey: "resourceKey",
            httpMethod: .get,
            urlString: .mockAny(),
            attributes: ["key": "resourceValue"]
        )

        monitor.stopResource(
            resourceKey: "resourceKey",
            statusCode: 200,
            kind: .fetch,
            size: nil,
            attributes: ["key": "resourceValue"]
        )

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))
        XCTAssertEqual(customView.viewEvents.count, 4)

        customView.viewEvents.dropFirst().forEach { viewEvent in
            XCTAssertEqual(viewEvent.numberOfAttributes, 1)
            XCTAssertEqual(viewEvent.attribute(forKey: "key"), "viewValue")
        }

        customView.actionEvents.forEach { actionEvent in
            XCTAssertEqual(actionEvent.numberOfAttributes, 1)
            XCTAssertEqual(actionEvent.attribute(forKey: "key"), "actionValue")
        }

        customView.resourceEvents.forEach { resourceEvent in
            XCTAssertEqual(resourceEvent.numberOfAttributes, 1)
            XCTAssertEqual(resourceEvent.attribute(forKey: "key"), "resourceValue")
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
        XCTAssertEqual(lastCustomViewEvent?.attribute(forKey: "sameKey"), "value1") // view attributes take precedence
    }

    // MARK: - Session

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

    // View attributes are not added or overwritten after a view has “stopped”, even if that view is still active because of Resource or Action events.
    // Changes to global attributes also do not affect “stopped” views, but should be transferred to other active events when they are stopped.
    func testWhenAttributesChange_onStoppedViews_withActiveResources() throws {
        // Given
        let view1 = "MyView1"
        let view2 = "MyView2"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.addAttribute(forKey: "globalKey", value: "globalValue")
        monitor.startView(key: view1, name: view1, attributes: ["viewKey": "viewValue"])
        monitor.startResource(
            resourceKey: "resourceKey",
            httpMethod: .get,
            urlString: .mockAny(),
            attributes: ["resourceKey": "resourceValue"]
        )

        monitor.addViewAttribute(forKey: "newViewKey", value: "newViewValue")
        monitor.startView(key: view2, name: view2, attributes: ["view2Key": "view2Value"])

        monitor.addAttribute(forKey: "newGlobalKey", value: "newGlobalValue")
        monitor.addViewAttribute(forKey: "newView2Key", value: "newView2Value")

        monitor.stopResource(
            resourceKey: "resourceKey",
            statusCode: 200,
            kind: .fetch,
            size: nil,
            attributes: ["resourceKey": "resourceValue"]
        )

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        let firstView = try XCTUnwrap(session.views.first(where: { $0.name == view1 }))
        let secondView = try XCTUnwrap(session.views.first(where: { $0.name == view2 }))

        XCTAssertEqual(firstView.viewEvents.count, 3)
        XCTAssertEqual(firstView.resourceEvents.count, 1)
        XCTAssertEqual(secondView.viewEvents.count, 1)

        // start view event
        XCTAssertEqual(firstView.viewEvents[0].numberOfAttributes, 2)
        XCTAssertEqual(firstView.viewEvents[0].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(firstView.viewEvents[0].attribute(forKey: "globalKey"), "globalValue")

        // stop view event
        XCTAssertEqual(firstView.viewEvents[1].numberOfAttributes, 3)
        XCTAssertEqual(firstView.viewEvents[1].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(firstView.viewEvents[1].attribute(forKey: "newViewKey"), "newViewValue")
        XCTAssertEqual(firstView.viewEvents[1].attribute(forKey: "globalKey"), "globalValue")

        // resource view event
        XCTAssertEqual(firstView.viewEvents[2].numberOfAttributes, 3)
        XCTAssertEqual(firstView.viewEvents[2].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(firstView.viewEvents[2].attribute(forKey: "newViewKey"), "newViewValue")
        XCTAssertEqual(firstView.viewEvents[2].attribute(forKey: "globalKey"), "globalValue")

        // start view2 event
        XCTAssertEqual(secondView.viewEvents[0].numberOfAttributes, 2)
        XCTAssertEqual(secondView.viewEvents[0].attribute(forKey: "view2Key"), "view2Value")
        XCTAssertEqual(secondView.viewEvents[0].attribute(forKey: "globalKey"), "globalValue")

        // resource event
        XCTAssertEqual(firstView.resourceEvents[0].numberOfAttributes, 5)
        XCTAssertEqual(firstView.resourceEvents[0].attribute(forKey: "resourceKey"), "resourceValue")
        XCTAssertEqual(firstView.resourceEvents[0].attribute(forKey: "viewKey"), "viewValue")
        XCTAssertEqual(firstView.resourceEvents[0].attribute(forKey: "newViewKey"), "newViewValue")
        XCTAssertEqual(firstView.resourceEvents[0].attribute(forKey: "globalKey"), "globalValue")
        XCTAssertEqual(firstView.resourceEvents[0].attribute(forKey: "newGlobalKey"), "newGlobalValue")
    }

    // MARK: - User Actions

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
        XCTAssertEqual(applicationView.actionEvents.count, 3)

        let firstActionEvent = applicationView.actionEvents[1]
        XCTAssertEqual(firstActionEvent.numberOfAttributes, 1)
        XCTAssertEqual(firstActionEvent.attribute(forKey: "sameKey"), "value1")

        let lastActionEvent = applicationView.actionEvents[2]
        XCTAssertEqual(lastActionEvent.numberOfAttributes, 2)
        XCTAssertEqual(lastActionEvent.attribute(forKey: "sameKey"), "value3")
        XCTAssertEqual(lastActionEvent.attribute(forKey: "key2"), "value2")
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

    // MARK: - Resources

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

    // MARK: - Error tracking

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

private extension RUMLongTaskEvent {
    var numberOfAttributes: Int { context?.contextInfo.count ?? 0 }

    func attribute<T: Equatable>(forKey key: String) -> T? { (context?.contextInfo[key] as? AnyCodable)?.value as? T }
}
