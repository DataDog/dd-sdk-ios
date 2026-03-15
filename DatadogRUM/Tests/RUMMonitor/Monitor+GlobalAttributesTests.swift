/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@_spi(Experimental)
@testable import DatadogRUM
@testable import TestUtilities

class Monitor_GlobalAttributesTests: XCTestCase {
    private let featureScope = FeatureScopeMock()
    private var monitor: Monitor! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope),
            dateProvider: SystemDateProvider()
        )
    }

    override func tearDown() {
        monitor = nil
    }

    // MARK: - Changing Global Attributes After SDK Init

    func testAddingGlobalAttributeAfterSDKInit() async throws {
        // When
        monitor.notifySDKInit()
        monitor.addAttribute(forKey: "attribute", value: "value")
        await monitor.flush()

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastView.view.name, RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName)
        XCTAssertNil(lastView.attribute(forKey: "attribute"))
    }

    func testAddingMultipleGlobalAttributes() async throws {
        // Given
        let mockAttributes: [AttributeKey: AttributeValue] = (0...99).reduce(into: [:]) { $0[String(describing: $1)] = $1 }

        // When
        monitor.notifySDKInit()
        monitor.addAttributes(mockAttributes)
        monitor.startView(key: "IgnoredView")
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let appLaunchViewEvent = try XCTUnwrap(viewEvents.last(where: { $0.view.name == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName }))
        XCTAssertTrue(appLaunchViewEvent.numberOfAttributes == 100)
    }

    func testAddingAndRemovingMultipleGlobalAttributes() async throws {
        // Given
        let mockAttributes: [AttributeKey: AttributeValue] = (0...99).reduce(into: [:]) { $0[String(describing: $1)] = $1 }

        // When
        monitor.notifySDKInit()
        monitor.addAttributes(mockAttributes)
        monitor.removeAttributes(forKeys: Array(mockAttributes.keys))
        monitor.startView(key: "IgnoredView")
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let appLaunchViewEvent = try XCTUnwrap(viewEvents.last(where: { $0.view.name == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName }))
        XCTAssertTrue(appLaunchViewEvent.numberOfAttributes == 0)
    }

    func testAddingIsolatedAttributesAndRemovingMultipleAttributes() async throws {
        // Given
        let attributeKeys: [AttributeKey] = (0...99).map { "key\($0)" }

        // When
        monitor.notifySDKInit()
        attributeKeys.forEach {
            monitor.addAttribute(forKey: $0, value: "value")
        }
        monitor.removeAttributes(forKeys: attributeKeys)
        monitor.startView(key: "IgnoredView")
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let appLaunchViewEvent = try XCTUnwrap(viewEvents.last(where: { $0.view.name == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName }))
        XCTAssertTrue(appLaunchViewEvent.numberOfAttributes == 0)
    }

    func testAddingMultipleAttributesAndRemovingSomeAttributes() async throws {
        // Given
        let mockAttributes: [AttributeKey: AttributeValue] = (0...99).reduce(into: [:]) { $0[String(describing: $1)] = $1 }
        let keyToRemove = try XCTUnwrap(mockAttributes.first?.key)
        var expectedAttributes = mockAttributes
        expectedAttributes.removeValue(forKey: keyToRemove)

        // When
        monitor.notifySDKInit()
        monitor.addAttributes(mockAttributes)
        monitor.removeAttribute(forKey: keyToRemove)
        monitor.startView(key: "IgnoredView")
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let appLaunchViewEvent = try XCTUnwrap(viewEvents.last(where: { $0.view.name == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName }))
        XCTAssertTrue(appLaunchViewEvent.numberOfAttributes == mockAttributes.count - 1)
    }

    func testAddingGlobalAttributeAfterSDKInit_thenStartingView() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.addAttribute(forKey: "attribute", value: "value")

        // When
        monitor.startView(key: "View")
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let appLaunchView = try XCTUnwrap(viewEvents.last(where: { $0.view.name == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName }))
        XCTAssertEqual(appLaunchView.attribute(forKey: "attribute"), "value")
    }

    func testAddingGlobalAttributeAfterSDKInit_thenSendingInteractiveEvent() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.addAttribute(forKey: "attribute", value: "value")

        // When
        monitor.addAction(type: .custom, name: "custom action")
        await monitor.flush()

        // Then
        let actionViewEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(actionViewEvent.view.name, RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName)
        XCTAssertEqual(actionViewEvent.attribute(forKey: "attribute"), "value") // "ApplicationLaunch" event triggered by RUM action
    }

    func testAddingGlobalAttributesAfterSDKInit_thenRemovingAttribute() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.addAttribute(forKey: "attribute1", value: "value1")
        monitor.addAttribute(forKey: "attribute2", value: "value2")

        // When
        monitor.removeAttribute(forKey: "attribute1")
        await monitor.flush()

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastView.view.name, RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName)
        XCTAssertNil(lastView.attribute(forKey: "attribute1"))
        XCTAssertNil(lastView.attribute(forKey: "attribute2"))
    }

    func testAddingGlobalAttributeAfterSDKInit_thenRemovingAttributeAndStartingView() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.addAttribute(forKey: "attribute1", value: "value1")
        monitor.addAttribute(forKey: "attribute2", value: "value2")

        // When
        monitor.removeAttribute(forKey: "attribute1")
        monitor.startView(key: "View")
        await monitor.flush()

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastView.view.name, "View")
        XCTAssertNil(lastView.attribute(forKey: "attribute1"))
        XCTAssertEqual(lastView.attribute(forKey: "attribute2"), "value2")
    }

    func testAddingGlobalAttributeAfterSDKInit_thenRemovingAttributeAndStartingAndStoppingView() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.addAttribute(forKey: "attribute1", value: "value1")
        monitor.addAttribute(forKey: "attribute2", value: "value2")

        // When
        monitor.removeAttribute(forKey: "attribute1")
        monitor.startView(key: "View")
        monitor.stopView(key: "View")
        await monitor.flush()

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastView.view.name, "View")
        XCTAssertNil(lastView.attribute(forKey: "attribute1"))
        XCTAssertEqual(lastView.attribute(forKey: "attribute2"), "value2")
    }

    func testUpdatingGlobalAttributesAfterSDKInit_thenStartingAndStoppingView() async throws {
        // Given
        monitor.notifySDKInit()

        // When
        monitor.addAttribute(forKey: "attribute", value: "value")
        monitor.addAttribute(forKey: "attribute", value: "new-value")
        monitor.removeAttribute(forKey: "unknown-attribute")
        monitor.startView(key: "View")
        monitor.stopView(key: "View")
        await monitor.flush()

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastView.view.name, "View")
        XCTAssertEqual(lastView.attribute(forKey: "attribute"), "new-value")
        XCTAssertEqual(lastView.numberOfAttributes, 1)
    }

    // MARK: - Changing Global Attributes After Starting View

    func testAddingGlobalAttributeAfterViewIsStarted() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "View")
        await monitor.flush()

        // When
        monitor.addAttribute(forKey: "attribute", value: "value")

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastView.view.name, "View")
        XCTAssertNil(lastView.attribute(forKey: "attribute"))
    }

    func testAddingGlobalAttributeAfterViewIsStarted_thenSendingInteractiveEvent() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "View")
        monitor.addAttribute(forKey: "attribute", value: "value")

        // When
        monitor.addAction(type: .custom, name: "custom action")
        await monitor.flush()

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastView.view.name, "View")
        XCTAssertEqual(lastView.attribute(forKey: "attribute"), "value")
    }

    func testAddingGlobalAttributesAfterViewIsStarted_thenRemovingAttribute() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "View")
        monitor.addAttribute(forKey: "attribute1", value: "value1")
        monitor.addAttribute(forKey: "attribute2", value: "value2")
        await monitor.flush()

        // When
        monitor.removeAttribute(forKey: "attribute1")

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastView.view.name, "View")
        XCTAssertNil(lastView.attribute(forKey: "attribute1"))
        XCTAssertNil(lastView.attribute(forKey: "attribute2"))
    }

    func testAddingGlobalAttributesAfterViewIsStarted_thenRemovingAttributeAndStoppingView() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "View")
        monitor.addAttribute(forKey: "attribute1", value: "value1")
        monitor.addAttribute(forKey: "attribute2", value: "value2")

        // When
        monitor.removeAttribute(forKey: "attribute1")
        monitor.stopView(key: "View")
        await monitor.flush()

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        XCTAssertEqual(lastView.view.name, "View")
        XCTAssertNil(lastView.attribute(forKey: "attribute1"))
        XCTAssertEqual(lastView.attribute(forKey: "attribute2"), "value2")
    }

    func testAddingGlobalAttributeAfterViewIsStarted_thenStartingNextViewsWhileAddingAttributes() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "View1")
        monitor.addAttribute(forKey: "attribute1", value: "value1")

        // When
        monitor.startView(key: "View2")
        monitor.addAttribute(forKey: "attribute2", value: "value2")
        monitor.startView(key: "View3")
        monitor.addAttribute(forKey: "attribute3", value: "value3")
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let lastView1 = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "View1" }))
        let lastView2 = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "View2" }))
        let lastView3 = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "View3" }))

        XCTAssertEqual(lastView1.attribute(forKey: "attribute1"), "value1")
        XCTAssertNil(lastView1.attribute(forKey: "attribute2"))
        XCTAssertNil(lastView1.attribute(forKey: "attribute3"))

        XCTAssertEqual(lastView2.attribute(forKey: "attribute1"), "value1")
        XCTAssertEqual(lastView2.attribute(forKey: "attribute2"), "value2")
        XCTAssertNil(lastView2.attribute(forKey: "attribute3"))

        XCTAssertEqual(lastView3.attribute(forKey: "attribute1"), "value1")
        XCTAssertEqual(lastView3.attribute(forKey: "attribute2"), "value2")
        XCTAssertNil(lastView2.attribute(forKey: "attribute3"))
    }

    func testAddingGlobalAttributesAfterViewIsStarted_thenStartingNextViewsWhileRemovingAttributes() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "View1")
        monitor.addAttributes(
            [
                "attribute1": "value1",
                "attribute2": "value2",
                "attribute3": "value3"
            ]
        )

        // When
        monitor.startView(key: "View2")
        monitor.removeAttribute(forKey: "attribute1")
        monitor.startView(key: "View3")
        monitor.removeAttribute(forKey: "attribute2")
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let lastView1 = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "View1" }))
        let lastView2 = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "View2" }))
        let lastView3 = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "View3" }))

        XCTAssertEqual(lastView1.attribute(forKey: "attribute1"), "value1")
        XCTAssertEqual(lastView1.attribute(forKey: "attribute2"), "value2")
        XCTAssertEqual(lastView1.attribute(forKey: "attribute3"), "value3")

        XCTAssertNil(lastView2.attribute(forKey: "attribute1"))
        XCTAssertEqual(lastView2.attribute(forKey: "attribute2"), "value2")
        XCTAssertEqual(lastView2.attribute(forKey: "attribute3"), "value3")

        XCTAssertNil(lastView3.attribute(forKey: "attribute1"))
        XCTAssertEqual(lastView3.attribute(forKey: "attribute2"), "value2")
        XCTAssertEqual(lastView3.attribute(forKey: "attribute3"), "value3")
    }

    func testAddingGlobalAttributesAfterViewIsStarted_thenStartingNextViewsWhileUpdatingAttributes() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "View1")
        monitor.addAttributes(
            [
                "attribute1": "value1",
                "attribute2": "value2",
                "attribute3": "value3"
            ]
        )

        // When
        monitor.startView(key: "View2")
        monitor.addAttribute(forKey: "attribute1", value: "new-value1")
        monitor.startView(key: "View3")
        monitor.addAttribute(forKey: "attribute2", value: "new-value1")
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let lastView1 = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "View1" }))
        let lastView2 = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "View2" }))
        let lastView3 = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "View3" }))

        XCTAssertEqual(lastView1.attribute(forKey: "attribute1"), "value1")
        XCTAssertEqual(lastView1.attribute(forKey: "attribute2"), "value2")
        XCTAssertEqual(lastView1.attribute(forKey: "attribute3"), "value3")

        XCTAssertEqual(lastView2.attribute(forKey: "attribute1"), "new-value1")
        XCTAssertEqual(lastView2.attribute(forKey: "attribute2"), "value2")
        XCTAssertEqual(lastView2.attribute(forKey: "attribute3"), "value3")

        XCTAssertEqual(lastView3.attribute(forKey: "attribute1"), "new-value1")
        XCTAssertEqual(lastView3.attribute(forKey: "attribute2"), "value2")
        XCTAssertEqual(lastView3.attribute(forKey: "attribute3"), "value3")
    }

    // MARK: - Changing Global Attributes While There Is An Inactive View

    func testAddingGlobalAttributeWhileInactiveView_thenImplicitlyStoppingInactiveView() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "InactiveView")
        monitor.startResource(resourceKey: "pending resource", url: .mockAny())
        monitor.startView(key: "ActiveView")

        // When
        monitor.addAttribute(forKey: "attribute", value: "value")
        monitor.stopResource(resourceKey: "pending resource", response: .mockAny())
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let lastInactiveView = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "InactiveView" }))
        let lastActiveView = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "ActiveView" }))

        XCTAssertEqual(lastInactiveView.view.resource.count, 1)
        XCTAssertNil(lastInactiveView.attribute(forKey: "attribute"))
        XCTAssertNil(lastActiveView.attribute(forKey: "attribute"))
    }

    func testAddingGlobalAttributesWhileInactiveView_thenRemovingAttributeAndImplicitlyStoppingInactiveView() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "InactiveView")
        monitor.startResource(resourceKey: "pending resource", url: .mockAny())
        monitor.startView(key: "ActiveView")

        // When
        monitor.addAttribute(forKey: "attribute1", value: "value1")
        monitor.addAttribute(forKey: "attribute2", value: "value2")
        monitor.removeAttribute(forKey: "attribute1")
        monitor.stopResource(resourceKey: "pending resource", response: .mockAny())
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let lastInactiveView = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "InactiveView" }))
        let lastActiveView = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "ActiveView" }))

        XCTAssertEqual(lastInactiveView.view.resource.count, 1)
        XCTAssertNil(lastInactiveView.attribute(forKey: "attribute1"))
        XCTAssertNil(lastInactiveView.attribute(forKey: "attribute2"))
        XCTAssertNil(lastActiveView.attribute(forKey: "attribute1"))
        XCTAssertNil(lastActiveView.attribute(forKey: "attribute2"))
    }

    func testAddingGlobalAttributesWhileInactiveView_thenRemovingAttributeAndImplicitlyStoppingInactiveViewAndStoppingActiveView() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "InactiveView")
        monitor.startResource(resourceKey: "pending resource", url: .mockAny())
        monitor.startView(key: "ActiveView")

        // When
        monitor.addAttribute(forKey: "attribute1", value: "value1")
        monitor.addAttribute(forKey: "attribute2", value: "value2")
        monitor.removeAttribute(forKey: "attribute1")
        monitor.stopResource(resourceKey: "pending resource", response: .mockAny())
        monitor.stopView(key: "ActiveView")
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self)
        let lastInactiveView = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "InactiveView" }))
        let lastActiveView = try XCTUnwrap(viewEvents.last(where: { $0.view.name == "ActiveView" }))

        XCTAssertEqual(lastInactiveView.view.resource.count, 1)
        XCTAssertNil(lastInactiveView.attribute(forKey: "attribute1"))
        XCTAssertNil(lastInactiveView.attribute(forKey: "attribute2"))
        XCTAssertNil(lastActiveView.attribute(forKey: "attribute1"))
        XCTAssertEqual(lastActiveView.attribute(forKey: "attribute2"), "value2")
    }

    // MARK: - Including Up-to-date Global Attributes In Events

    func testAddingGlobalAttributeToActiveView_thenCollectingViewEvents() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "ActiveView")
        monitor.addAttribute(forKey: "attribute", value: "value")

        // When
        monitor.addError(message: "error event")
        monitor.addAction(type: .custom, name: "custom action event")
        monitor.startResource(resourceKey: "resource", url: .mockAny())
        monitor.stopResource(resourceKey: "resource", response: .mockAny())
        await monitor.flush()

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last)
        let errorEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMErrorEvent.self).last)
        let actionEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMActionEvent.self).last)
        let resourceEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMResourceEvent.self).last)

        XCTAssertEqual(lastView.view.error.count, 1)
        XCTAssertEqual(lastView.view.action.count, 1)
        XCTAssertEqual(lastView.view.resource.count, 1)
        XCTAssertEqual(lastView.context?.contextInfo["attribute"] as? String, "value") // "ActiveView" event triggered by `stopResource`
        XCTAssertEqual(errorEvent.context?.contextInfo["attribute"] as? String, "value")
        XCTAssertEqual(actionEvent.context?.contextInfo["attribute"] as? String, "value")
        XCTAssertEqual(resourceEvent.context?.contextInfo["attribute"] as? String, "value")
    }

    func testAddingGlobalAttributesToActiveView_thenRemovingAttributeAndCollectingViewEvents() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "ActiveView")
        monitor.addAttribute(forKey: "attribute1", value: "value1")
        monitor.addAttribute(forKey: "attribute2", value: "value2")

        // When
        monitor.removeAttribute(forKey: "attribute1")
        monitor.addError(message: "error event")
        monitor.addAction(type: .custom, name: "custom action event")
        monitor.startResource(resourceKey: "resource", url: .mockAny())
        monitor.stopResource(resourceKey: "resource", response: .mockAny())
        await monitor.flush()

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last) // "ActiveView" event triggered by RUM resource
        let errorEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMErrorEvent.self).last)
        let actionEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMActionEvent.self).last)
        let resourceEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMResourceEvent.self).last)

        XCTAssertEqual(lastView.view.error.count, 1)
        XCTAssertEqual(lastView.view.action.count, 1)
        XCTAssertEqual(lastView.view.resource.count, 1)
        XCTAssertNil(lastView.attribute(forKey: "attribute1"))
        XCTAssertEqual(lastView.context?.contextInfo["attribute2"] as? String, "value2")
        XCTAssertNil(errorEvent.context?.contextInfo["attribute1"])
        XCTAssertEqual(errorEvent.context?.contextInfo["attribute2"] as? String, "value2")
        XCTAssertNil(actionEvent.context?.contextInfo["attribute1"])
        XCTAssertEqual(actionEvent.context?.contextInfo["attribute2"] as? String, "value2")
        XCTAssertNil(resourceEvent.context?.contextInfo["attribute1"])
        XCTAssertEqual(resourceEvent.context?.contextInfo["attribute2"] as? String, "value2")
    }

    func testUpdatingGlobalAttributeInActiveView_thenCollectingViewEvents() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "ActiveView")
        monitor.addAttribute(forKey: "attribute", value: "value")
        monitor.addAttribute(forKey: "attribute", value: "new-value")

        // When
        monitor.addError(message: "error event")
        monitor.addAction(type: .custom, name: "custom action event")
        monitor.startResource(resourceKey: "resource", url: .mockAny())
        monitor.stopResource(resourceKey: "resource", response: .mockAny())
        await monitor.flush()

        // Then
        let lastView = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMViewEvent.self).last) // "ActiveView" event triggered by RUM resource
        let errorEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMErrorEvent.self).last)
        let actionEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMActionEvent.self).last)
        let resourceEvent = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMResourceEvent.self).last)

        XCTAssertEqual(lastView.view.error.count, 1)
        XCTAssertEqual(lastView.view.action.count, 1)
        XCTAssertEqual(lastView.view.resource.count, 1)
        XCTAssertEqual(lastView.context?.contextInfo["attribute"] as? String, "new-value")
        XCTAssertEqual(errorEvent.context?.contextInfo["attribute"] as? String, "new-value")
        XCTAssertEqual(actionEvent.context?.contextInfo["attribute"] as? String, "new-value")
        XCTAssertEqual(resourceEvent.context?.contextInfo["attribute"] as? String, "new-value")
    }

    func testAddingGlobalAttributesToActiveView_thenCollectingViewTimingsAndRemovingAttribute() async throws {
        // Given
        monitor.notifySDKInit()
        monitor.startView(key: "ActiveView")
        monitor.addAttribute(forKey: "attribute1", value: "value1")
        monitor.addAttribute(forKey: "attribute2", value: "value2")

        // When
        monitor.addTiming(name: "timing1")
        monitor.removeAttribute(forKey: "attribute1")
        monitor.addTiming(name: "timing2")
        await monitor.flush()

        // Then
        let viewEvents = featureScope.eventsWritten(ofType: RUMViewEvent.self).filter { $0.view.name == "ActiveView" }
        let viewAfterFirstTiming = try XCTUnwrap(viewEvents.last(where: { $0.view.customTimings?.customTimingsInfo.count == 1 }))
        let viewAfterSecondTiming = try XCTUnwrap(viewEvents.last(where: { $0.view.customTimings?.customTimingsInfo.count == 2 }))

        XCTAssertEqual(viewAfterFirstTiming.attribute(forKey: "attribute1"), "value1")
        XCTAssertEqual(viewAfterFirstTiming.attribute(forKey: "attribute2"), "value2")
        XCTAssertEqual(viewAfterSecondTiming.attribute(forKey: "attribute2"), "value2")
    }

    // MARK: - Updating Fatal Error Context With Global Attributes

    func testGivenSDKInitialized_whenGlobalAttributeIsAdded_thenFatalErrorContextIsUpdatedWithNewAttributes() async throws {
        let fatalErrorContext = FatalErrorContextNotifierMock()

        // Given
        monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, fatalErrorContext: fatalErrorContext),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()

        // When
        monitor.addAttribute(forKey: "attribute", value: "value")
        await monitor.flush()

        // Then
        XCTAssertEqual(fatalErrorContext.globalAttributes["attribute"] as? String, "value")
        XCTAssertEqual(fatalErrorContext.globalAttributes.count, 1)
    }

    func testGivenSDKInitialized_whenMultipleGlobalAttributesAreAdded_thenFatalErrorContextIsUpdatedWithNewAttributes() async throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifierMock()
        let mockAttributes: [AttributeKey: AttributeValue] = (0...99).reduce(into: [:]) { $0[String(describing: $1)] = $1 }
        monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, fatalErrorContext: fatalErrorContext),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()

        // When
        monitor.addAttributes(mockAttributes)
        await monitor.flush()

        // Then
        XCTAssertEqual(fatalErrorContext.globalAttributes.count, mockAttributes.count)
        fatalErrorContext.globalAttributes.forEach {
            XCTAssertEqual(mockAttributes[$0.key] as? String, $0.value as? String)
        }
    }

    func testGivenSDKInitialized_whenGlobalAttributesAreAddedAndRemoved_thenFatalErrorContextIsUpdatedWithNewAttributes() async throws {
        let fatalErrorContext = FatalErrorContextNotifierMock()

        // Given
        monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, fatalErrorContext: fatalErrorContext),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()

        // When
        monitor.addAttribute(forKey: "attribute1", value: "value1")
        monitor.addAttribute(forKey: "attribute2", value: "value2")
        monitor.removeAttribute(forKey: "attribute1")
        await monitor.flush()

        // Then
        XCTAssertEqual(fatalErrorContext.globalAttributes["attribute2"] as? String, "value2")
        XCTAssertEqual(fatalErrorContext.globalAttributes.count, 1)
    }

    func testGivenSDKInitialized_whenMultipleGlobalAttributesAreAddedAndRemoved_thenFatalErrorContextIsUpdatedWithNewAttributes() async throws {
        // Given
        let fatalErrorContext = FatalErrorContextNotifierMock()
        let mockAttributes: [AttributeKey: AttributeValue] = (0...99).reduce(into: [:]) { $0[String(describing: $1)] = $1 }
        let keysToRemove = [try XCTUnwrap(mockAttributes.first?.key)]
        monitor = Monitor(
            dependencies: .mockWith(featureScope: featureScope, fatalErrorContext: fatalErrorContext),
            dateProvider: SystemDateProvider()
        )
        monitor.notifySDKInit()

        // When
        monitor.addAttributes(mockAttributes)
        monitor.removeAttributes(forKeys: keysToRemove)
        await monitor.flush()

        // Then
        XCTAssertEqual(fatalErrorContext.globalAttributes.count, (mockAttributes.count - keysToRemove.count))
        keysToRemove.forEach {
            XCTAssertNil(fatalErrorContext.globalAttributes[$0])
        }
    }
}

// MARK: - Helpers

private extension RUMViewEvent {
    func attribute(forKey key: String) -> Any? {
        return context?.contextInfo[key]
    }

    func attribute<T: Equatable>(forKey key: String) -> T? {
        return context?.contextInfo[key] as? T
    }

    var numberOfAttributes: Int {
        return context?.contextInfo.count ?? 0
    }
}
