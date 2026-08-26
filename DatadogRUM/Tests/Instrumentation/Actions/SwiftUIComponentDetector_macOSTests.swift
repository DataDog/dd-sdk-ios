/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(macOS)

import AppKit
import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

@MainActor
class MacOSSwiftUIComponentDetectorTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())

    func testGivenSupportedAccessibilityRole_itCreatesActionCommand() {
        // Given
        let supportedRoles: [NSAccessibility.Role] = [
            .button,
            .radioButton,
            .checkBox,
            .popUpButton,
            .menuButton,
            .outline,
            .row,
            .comboBox,
            .slider,
            .incrementor,
            .textField,
            .textArea
        ]

        for role in supportedRoles {
            let element = MockAccessibilityElement(role: role)
            let predicate = RecordingSwiftUIRUMActionsPredicate()
            let (detector, event, _) = makeDetectorInput(hitTestResult: element)

            // When
            let command = detector.createActionCommand(
                from: event,
                predicate: predicate,
                dateProvider: dateProvider
            )

            // Then
            XCTAssertNotNil(command, "Expected \(role.rawValue) to produce an action")
            XCTAssertEqual(predicate.receivedComponentNames, [role.rawValue])
        }
    }

    func testGivenAccessibilityIdentifier_itIncludesIdentifierInComponentName() {
        // Given
        let element = MockAccessibilityElement(role: .button, identifier: "Save")
        let predicate = RecordingSwiftUIRUMActionsPredicate()
        let (detector, event, _) = makeDetectorInput(hitTestResult: element)

        // When
        _ = detector.createActionCommand(from: event, predicate: predicate, dateProvider: dateProvider)

        // Then
        XCTAssertEqual(predicate.receivedComponentNames, ["AXButton (Save)"])
    }

    func testGivenNoAccessibilityIdentifier_itUsesRoleAsComponentName() {
        for identifier in [nil, ""] as [String?] {
            // Given
            let element = MockAccessibilityElement(role: .button, identifier: identifier)
            let predicate = RecordingSwiftUIRUMActionsPredicate()
            let (detector, event, _) = makeDetectorInput(hitTestResult: element)

            // When
            _ = detector.createActionCommand(from: event, predicate: predicate, dateProvider: dateProvider)

            // Then
            XCTAssertEqual(predicate.receivedComponentNames, ["AXButton"])
        }
    }

    func testGivenPredicateAction_itCreatesCommandWithExpectedMetadata() throws {
        // Given
        let attributes: [AttributeKey: AttributeValue] = ["key": "value"]
        let predicate = RecordingSwiftUIRUMActionsPredicate(
            action: RUMAction(name: "custom-action", attributes: attributes)
        )
        let element = MockAccessibilityElement(role: .button)
        let (detector, event, _) = makeDetectorInput(hitTestResult: element)

        // When
        let command = try XCTUnwrap(
            detector.createActionCommand(from: event, predicate: predicate, dateProvider: dateProvider)
        )

        // Then
        XCTAssertEqual(command.name, "custom-action")
        XCTAssertEqual(command.actionType, .click)
        XCTAssertEqual(command.instrumentation, .swiftuiAutomatic)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
        DDAssertDictionariesEqual(command.attributes, attributes)
    }

    func testGivenNilOrRejectingPredicate_itDoesNotCreateActionCommand() {
        // Given
        let element = MockAccessibilityElement(role: .button)
        let (detector, event, _) = makeDetectorInput(hitTestResult: element)
        let rejectingPredicate = RecordingSwiftUIRUMActionsPredicate(action: nil)

        // When
        let commandWithoutPredicate = detector.createActionCommand(
            from: event,
            predicate: nil,
            dateProvider: dateProvider
        )
        let commandRejectedByPredicate = detector.createActionCommand(
            from: event,
            predicate: rejectingPredicate,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNil(commandWithoutPredicate)
        XCTAssertNil(commandRejectedByPredicate)
    }

    func testGivenUninterestingElementWithInterestingParent_itUsesParentAsTarget() {
        // Given
        let parent = MockAccessibilityElement(role: .button, identifier: "Parent")
        let child = MockAccessibilityElement(role: .group, parent: parent)
        let predicate = RecordingSwiftUIRUMActionsPredicate()
        let (detector, event, _) = makeDetectorInput(hitTestResult: child)

        // When
        _ = detector.createActionCommand(from: event, predicate: predicate, dateProvider: dateProvider)

        // Then
        XCTAssertEqual(predicate.receivedComponentNames, ["AXButton (Parent)"])
    }

    func testGivenElementWithoutRole_itCanUseInterestingParentAsTarget() {
        // Given
        let parent = MockAccessibilityElement(role: .checkBox)
        let child = MockAccessibilityElement(role: nil, parent: parent)
        let predicate = RecordingSwiftUIRUMActionsPredicate()
        let (detector, event, _) = makeDetectorInput(hitTestResult: child)

        // When
        _ = detector.createActionCommand(from: event, predicate: predicate, dateProvider: dateProvider)

        // Then
        XCTAssertEqual(predicate.receivedComponentNames, ["AXCheckBox"])
    }

    func testGivenNoInterestingElementInHierarchy_itDoesNotCreateActionCommand() {
        // Given
        let element = MockAccessibilityElement(role: .group)
        let predicate = RecordingSwiftUIRUMActionsPredicate()
        let (detector, event, _) = makeDetectorInput(hitTestResult: element)

        // When
        let command = detector.createActionCommand(
            from: event,
            predicate: predicate,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNil(command)
        XCTAssertTrue(predicate.receivedComponentNames.isEmpty)
    }

    func testGivenNestedHostingScrollViews_itHitTestsLazyNodesAndUsesDescendant() {
        // Given
        let button = MockAccessibilityElement(role: .button, identifier: "Nested")
        let innerLazyNode = MockAccessibilityLazyLayoutNode(hitTestResult: button)
        let innerScrollView = MockHostingScrollViewAccessibilityElement(
            role: .scrollArea,
            children: [innerLazyNode]
        )
        let outerLazyNode = MockAccessibilityLazyLayoutNode(hitTestResult: innerScrollView)
        let outerScrollView = MockHostingScrollViewAccessibilityElement(
            role: .scrollArea,
            children: [outerLazyNode]
        )
        let predicate = RecordingSwiftUIRUMActionsPredicate()
        let (detector, event, window) = makeDetectorInput(hitTestResult: outerScrollView)
        let expectedScreenPoint = window.convertPoint(toScreen: event.locationInWindow)

        // When
        _ = detector.createActionCommand(from: event, predicate: predicate, dateProvider: dateProvider)

        // Then
        XCTAssertEqual(predicate.receivedComponentNames, ["AXButton (Nested)"])
        XCTAssertEqual(window.receivedHitTestPoints, [expectedScreenPoint])
        XCTAssertEqual(outerLazyNode.receivedHitTestPoints, [expectedScreenPoint])
        XCTAssertEqual(innerLazyNode.receivedHitTestPoints, [expectedScreenPoint])
    }

    func testGivenHostingScrollViewWithoutLazyNode_itFallsBackToInterestingParent() {
        // Given
        let parent = MockAccessibilityElement(role: .outline, identifier: "List")
        let scrollView = MockHostingScrollViewAccessibilityElement(
            role: .scrollArea,
            parent: parent,
            children: []
        )
        let predicate = RecordingSwiftUIRUMActionsPredicate()
        let (detector, event, _) = makeDetectorInput(hitTestResult: scrollView)

        // When
        _ = detector.createActionCommand(from: event, predicate: predicate, dateProvider: dateProvider)

        // Then
        XCTAssertEqual(predicate.receivedComponentNames, ["AXOutline (List)"])
    }

    func testGivenHostingScrollViewHitTestReturnsItself_itDoesNotLoop() {
        // Given
        let parent = MockAccessibilityElement(role: .button)
        let lazyNode = MockAccessibilityLazyLayoutNode()
        let scrollView = MockHostingScrollViewAccessibilityElement(
            role: .scrollArea,
            parent: parent,
            children: [lazyNode]
        )
        lazyNode.hitTestResult = scrollView
        let predicate = RecordingSwiftUIRUMActionsPredicate()
        let (detector, event, _) = makeDetectorInput(hitTestResult: scrollView)

        // When
        _ = detector.createActionCommand(from: event, predicate: predicate, dateProvider: dateProvider)

        // Then
        XCTAssertEqual(predicate.receivedComponentNames, ["AXButton"])
        XCTAssertEqual(lazyNode.receivedHitTestPoints.count, 1)
    }

    func testGivenMissingEventContext_itDoesNotCreateActionCommand() {
        // Given
        let detector = MacOSSwiftUIComponentDetector()
        let predicate = RecordingSwiftUIRUMActionsPredicate()
        let windowWithoutHitTestResult = MockNSWindow(hitTestResult: nil)

        // When
        let commandWithoutWindow = detector.createActionCommand(
            from: MockNSEvent(window: nil),
            predicate: predicate,
            dateProvider: dateProvider
        )
        let commandWithoutHitTestResult = detector.createActionCommand(
            from: MockNSEvent(window: windowWithoutHitTestResult),
            predicate: predicate,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNil(commandWithoutWindow)
        XCTAssertNil(commandWithoutHitTestResult)
        XCTAssertTrue(predicate.receivedComponentNames.isEmpty)
    }

    private func makeDetectorInput(
        hitTestResult: Any?
    ) -> (MacOSSwiftUIComponentDetector, MockNSEvent, MockNSWindow) {
        let window = MockNSWindow(hitTestResult: hitTestResult)
        let event = MockNSEvent(window: window, locationInWindow: .init(x: 30, y: 40))
        return (MacOSSwiftUIComponentDetector(), event, window)
    }
}

// MARK: - Test Mocks

private final class RecordingSwiftUIRUMActionsPredicate: SwiftUIRUMActionsPredicate {
    private let action: RUMAction?
    private(set) var receivedComponentNames: [String] = []

    init(action: RUMAction? = RUMAction(name: "action", attributes: [:])) {
        self.action = action
    }

    func rumAction(with componentName: String) -> RUMAction? {
        receivedComponentNames.append(componentName)
        return action
    }
}

private final class MockNSEvent: NSEvent {
    private let mockWindow: NSWindow?
    private let mockLocationInWindow: NSPoint

    init(window: NSWindow?, locationInWindow: NSPoint = .zero) {
        self.mockWindow = window
        self.mockLocationInWindow = locationInWindow
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var window: NSWindow? { mockWindow }
    override var locationInWindow: NSPoint { mockLocationInWindow }
}

private final class MockNSWindow: NSWindow {
    private let hitTestResult: Any?
    private(set) var receivedHitTestPoints: [NSPoint] = []

    init(hitTestResult: Any?) {
        self.hitTestResult = hitTestResult
        super.init(
            contentRect: .init(x: 100, y: 200, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        receivedHitTestPoints.append(point)
        return hitTestResult
    }
}

private class MockAccessibilityElement: NSObject {
    let role: NSAccessibility.Role?
    let identifier: String?
    let parent: Any?
    let children: [Any]?
    var hitTestResult: Any?
    private(set) var receivedHitTestPoints: [NSPoint] = []

    init(
        role: NSAccessibility.Role? = nil,
        identifier: String? = nil,
        parent: Any? = nil,
        children: [Any]? = nil,
        hitTestResult: Any? = nil
    ) {
        self.role = role
        self.identifier = identifier
        self.parent = parent
        self.children = children
        self.hitTestResult = hitTestResult
    }

    @objc
    func accessibilityRole() -> NSAccessibility.Role? {
        return role
    }

    @objc
    func accessibilityIdentifier() -> String? {
        return identifier
    }

    @objc
    func accessibilityParent() -> Any? {
        return parent
    }

    @objc
    func accessibilityChildren() -> [Any]? {
        return children
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        receivedHitTestPoints.append(point)
        return hitTestResult
    }
}

private final class MockHostingScrollViewAccessibilityElement: MockAccessibilityElement { }

private final class MockAccessibilityLazyLayoutNode: MockAccessibilityElement { }

#endif
