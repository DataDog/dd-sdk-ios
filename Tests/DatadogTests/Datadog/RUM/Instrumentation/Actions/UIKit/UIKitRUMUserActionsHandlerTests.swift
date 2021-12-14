/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class UIKitRUMUserActionsHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()

    private func createHandler(userActionsPredicate: UIKitRUMUserActionsPredicate = DefaultUIKitRUMUserActionsPredicate()) -> UIKitRUMUserActionsHandler {
        let handler = UIKitRUMUserActionsHandler(dateProvider: dateProvider, predicate: userActionsPredicate)
        handler.publish(to: commandSubscriber)
        return handler
    }

    private lazy var handler = createHandler()

    private var mockAppWindow: UIWindow! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        mockAppWindow = UIWindow(frame: .zero)
    }

    override func tearDown() {
        mockAppWindow = nil
        super.tearDown()
    }

    // MARK: - Scenarios For Accepting Tap Events

    func testGivenViewWithAccessibilityIdentifier_whenSingleTouchEnds_itSendsRUMAction() {
        // Given
        let fixtures: [(view: UIView, expectedRUMActionName: String)] = [
            (
                view: UIButton()
                    .attached(to: mockAppWindow)
                    .with(accessibilityIdentifier: "Some Button"),
                expectedRUMActionName: "UIButton(Some Button)"
            ),
            (
                view: UIView().attached(
                    to: UITableViewCell()
                        .attached(to: mockAppWindow)
                        .with(accessibilityIdentifier: "Item: 3")
                ),
                expectedRUMActionName: "UITableViewCell(Item: 3)"
            ),
            (
                view: UIView().attached(
                    to: UICollectionViewCell()
                        .attached(to: mockAppWindow)
                        .with(accessibilityIdentifier: "Item: 3")
                ),
                expectedRUMActionName: "UICollectionViewCell(Item: 3)"
            )
        ]

        fixtures.forEach { view, expectedRUMActionName in
            // When
            handler.notify_sendEvent(
                application: .shared,
                event: .mockWith(touches: [.mockWith(phase: .ended, view: view)])
            )

            // Then
            let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
            XCTAssertEqual(command?.name, expectedRUMActionName)
            XCTAssertEqual(command?.actionType, .tap)
            XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(command?.attributes.count, 0)
        }
    }

    func testGivenViewWithNoAccessibilityIdentifier_whenSingleTouchEnds_itSendsRUMAction() {
        // Given
        let fixtures: [(view: UIView, expectedRUMActionName: String)] = [
            (
                view: UIButton()
                    .attached(to: mockAppWindow),
                expectedRUMActionName: "UIButton"
            ),
            (
                view: UIView()
                    .attached(to: UITableViewCell().attached(to: mockAppWindow)),
                expectedRUMActionName: "UITableViewCell"
            ),
            (
                view: UIView()
                    .attached(to: UICollectionViewCell().attached(to: mockAppWindow)),
                expectedRUMActionName: "UICollectionViewCell"
            )
        ]

        fixtures.forEach { view, expectedRUMActionName in
            // When
            handler.notify_sendEvent(
                application: .shared,
                event: .mockWith(touches: [.mockWith(phase: .ended, view: view)])
            )

            // Then
            let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
            XCTAssertEqual(command?.name, expectedRUMActionName)
            XCTAssertEqual(command?.actionType, .tap)
            XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(command?.attributes.count, 0)
        }
    }

    // MARK: - Scenarios For Ignoring Tap Events

    func testGivenAnyViewWithUnrecognizedHierarchy_whenTouchEnds_itGetsIgnored() {
        // Given
        let superview = UIView().attached(to: mockAppWindow)
        let view = UIView().attached(to: superview)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touches: [.mockWith(phase: .ended, view: view)])
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testGivenAnyViewPresentedInKeyboardWindow_whenTouchEnds_itGetsIgnoredForPrivacyReason() {
        let mockKeyboardWindow = MockUIRemoteKeyboardWindow(frame: .zero)

        // Given
        let view = UIView().attached(to: mockKeyboardWindow)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touches: [.mockWith(phase: .ended, view: view)])
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testGivenAnyUIControlNotAttachedToAnyWindow_itGetsIgnoredForPrivacyReason() {
        // Given
        let uiControl = UIControl()

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touches: [.mockWith(phase: .ended, view: uiControl)])
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testItIgnoresSingleTouchEventWithPhaseOtherThanEnded() {
        // Given
        let view = UIControl().attached(to: mockAppWindow)

        let ignoredTouchPhases: [UITouch.Phase]
        if #available(iOS 13.4, *) {
            ignoredTouchPhases = [.began, .moved, .stationary, .cancelled, .regionEntered, .regionMoved, .regionExited]
        } else {
            ignoredTouchPhases = [.began, .moved, .stationary, .cancelled]
        }

        ignoredTouchPhases.forEach { touchPhase in
            // When
            handler.notify_sendEvent(
                application: .shared,
                event: .mockWith(touches: [.mockWith(phase: touchPhase, view: view)])
            )

            // Then
            XCTAssertNil(commandSubscriber.lastReceivedCommand)
        }
    }

    func testItIgnoresMultitouchEvents() {
        // Given
        let view = UIControl().attached(to: mockAppWindow)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(
                touches: [
                    .mockWith(phase: .ended, view: view), // 1st touch
                    .mockWith(phase: .ended, view: view)  // 2nd touch
                ]
            )
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testItIgnoresEventsWithNoTouch() {
        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touches: nil)
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testItAppliesUserAttributesAndCustomName() {
        // Given
        let mockAttributes: [AttributeKey: AttributeValue] = mockRandomAttributes()
        let handler = createHandler(
            userActionsPredicate: MockUIKitRUMUserActionsPredicate(
                actionOverride: (name: "foobar", attributes: mockAttributes)
            )
        )
        let view = UIButton()
            .attached(to: mockAppWindow)
            .with(accessibilityIdentifier: "Some Button")
        let event = UIEvent.mockWith(touches: [.mockWith(phase: .ended, view: view)])

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: event
        )

        // Then
        let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
        XCTAssertEqual(command?.name, "foobar")
        AssertDictionariesEqual(command!.attributes, mockAttributes)
    }

    func testGivenUserActionPredicateReturnsNil_itDoesntSendAction() {
        // Given
        let handler = createHandler(
            userActionsPredicate: MockUIKitRUMUserActionsPredicate(actionOverride: nil)
        )
        let view = UIButton()
            .attached(to: mockAppWindow)
            .with(accessibilityIdentifier: "Some Button")
        let event = UIEvent.mockWith(touches: [.mockWith(phase: .ended, view: view)])

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: event
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }
}

// MARK: - Helpers

private extension UIView {
    func attached(to parent: UIView) -> UIView {
        parent.addSubview(self)
        return self
    }

    func with(accessibilityIdentifier: String) -> UIView {
        self.accessibilityIdentifier = accessibilityIdentifier
        return self
    }
}

/// The mock the keyboard window by having the class name contain "UIRemoteKeyboardWindow" string.
private class MockUIRemoteKeyboardWindow: UIWindow {}

private class MockUIKitRUMUserActionsPredicate: UIKitRUMUserActionsPredicate {
    private let actionOverride: (name: String, attributes: [AttributeKey: AttributeValue])?

    init(actionOverride: (name: String, attributes: [AttributeKey: AttributeValue])?) {
        self.actionOverride = actionOverride
    }

    func rumAction(targetView: UIView) -> RUMAction? {
        if let action = actionOverride {
            return RUMAction(name: action.name, attributes: action.attributes)
        } else {
            return nil
        }
    }
}
