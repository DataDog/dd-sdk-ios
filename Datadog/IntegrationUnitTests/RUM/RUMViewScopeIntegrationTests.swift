/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM
@testable import DatadogInternal

final class RUMViewScopeIntegrationTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional
    private var rumConfig: RUM.Configuration! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
        rumConfig = RUM.Configuration(applicationID: .mockAny())
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testWhenViewStops_theViewAttributesAreNotUpdated_withGlobalAttributes() throws {
        // Given
        let initialAttributes: [AttributeKey: AnyCodable] = ["key1": .init("value1"), "key2": .init("value2")]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: initialAttributes)
        monitor.stopView(key: "key")
        // Flushing the commands in the current thread to prevent data races accessing the attributes
        core.flush()
        monitor.addAttribute(forKey: "additionalKey", value: "additionalValue")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(session.views.count, 2)

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))

        customView.viewEvents.forEach { viewEvent in

            XCTAssertEqual(viewEvent.context?.contextInfo as? [AttributeKey: AnyCodable], initialAttributes)
        }
    }

    func testWhenViewRelyingOnGlobalAttributes_doesNotUpdateTheViewAttributes_afterStopView() throws {
        // Given
        let initialAttributes: [AttributeKey: AnyCodable] = ["key1": .init("value1"), "key2": .init("value2")]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName)
        monitor.addAttribute(forKey: "key1", value: initialAttributes["key1"])
        monitor.addAttribute(forKey: "key2", value: initialAttributes["key2"])
        monitor.stopView(key: "key")
        // Flushing the commands in the current thread to prevent data races accessing the attributes
        core.flush()
        monitor.addAttribute(forKey: "additionalKey", value: "additionalValue")

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(session.views.count, 2)

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))

        customView.viewEvents.forEach { viewEvent in

            XCTAssertEqual(viewEvent.context?.contextInfo as? [AttributeKey: AnyCodable], initialAttributes)
        }
    }

    func testWhenSessionEnds_theViewAttributesAreNotUpdated_withAStopView() throws {
        // Given
        let initialAttributes: [AttributeKey: AnyCodable] = ["key1": .init("value1"), "key2": .init("value2")]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: initialAttributes)
        monitor.stopSession()
        monitor.stopView(key: "key", attributes: ["additionalKey" : "additionalValue"])

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(session.views.count, 2)

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))

        customView.viewEvents.forEach { viewEvent in

            XCTAssertEqual(viewEvent.context?.contextInfo as? [AttributeKey: AnyCodable], initialAttributes)
        }
    }

    func testWhenViewReceivesActions_theViewAttributesAreNotUpdated_withActionAttributes() throws {
        // Given
        let initialAttributes: [AttributeKey: AnyCodable] = ["key1": .init("value1"), "key2": .init("value2")]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: initialAttributes)
        monitor.addAction(type: .custom, name: "drag", attributes: ["additionalKey" : "additionalValue"])
        monitor.stopView(key: "key")
        monitor.addAction(type: .tap, name: "tap", attributes: ["anotherAdditionalKey" : "anotherAdditionalValue"])

        // Then
        let session = try RUMSessionMatcher
            .groupMatchersBySessions(try core.waitAndReturnRUMEventMatchers())
            .takeSingle()

        // It should have the `ApplicationLaunchView` and `MyView` views
        XCTAssertEqual(session.views.count, 2)

        let customView = try XCTUnwrap(session.views.first(where: { $0.name == viewName }))

        customView.viewEvents.forEach { viewEvent in

            XCTAssertEqual(viewEvent.context?.contextInfo as? [AttributeKey: AnyCodable], initialAttributes)
        }
    }

    func testWhenViewReceivesResources_theViewAttributesAreNotUpdated_withResourceAttributes() throws {
        // Given
        let initialAttributes: [AttributeKey: AnyCodable] = ["key1": .init("value1"), "key2": .init("value2")]
        let viewName = "MyView"
        RUM.enable(with: rumConfig, in: core)

        let monitor = RUMMonitor.shared(in: core)

        // When
        monitor.startView(key: "key", name: viewName, attributes: initialAttributes)
        monitor.startResource(
            resourceKey: "resourceKey",
            httpMethod: .get,
            urlString: .mockAny(),
            attributes:   ["additionalKey" : "additionalValue"]
        )

        monitor.stopResource(
            resourceKey: "resourceKey",
            statusCode: 200,
            kind: .fetch,
            size: nil,
            attributes: ["resourceAdditionalKey" : "resourceAdditionalValue"]
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

            XCTAssertEqual(viewEvent.context?.contextInfo as? [AttributeKey: AnyCodable], initialAttributes)
        }
    }
}
