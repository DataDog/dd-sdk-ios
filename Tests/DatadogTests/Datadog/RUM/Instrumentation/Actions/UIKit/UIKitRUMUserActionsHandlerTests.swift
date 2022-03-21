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

    private func touchHandler(with predicate: UITouchRUMUserActionsPredicate = DefaultUIKitRUMUserActionsPredicate()) -> UIKitRUMUserActionsHandler {
        let handler = UIKitRUMUserActionsHandler(dateProvider: dateProvider, predicate: predicate)
        handler.publish(to: commandSubscriber)
        return handler
    }

    private func pressHandler(with predicate: UIPressRUMUserActionsPredicate = DefaultUIKitRUMUserActionsPredicate()) -> UIKitRUMUserActionsHandler {
        let handler = UIKitRUMUserActionsHandler(dateProvider: dateProvider, predicate: predicate)
        handler.publish(to: commandSubscriber)
        return handler
    }

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
        let handler = touchHandler()
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
                event: .mockWith(touch: .mockWith(view: view))
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
        let handler = touchHandler()
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
                event: .mockWith(touch: .mockWith(view: view))
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
        let handler = touchHandler()
        let superview = UIView().attached(to: mockAppWindow)
        let view = UIView().attached(to: superview)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touch: .mockWith(view: view))
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testGivenAnyViewPresentedInKeyboardWindow_whenTouchEnds_itGetsIgnoredForPrivacyReason() {
        let mockKeyboardWindow = MockUIRemoteKeyboardWindow(frame: .zero)

        // Given
        let handler = touchHandler()
        let view = UIView().attached(to: mockKeyboardWindow)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touch: .mockWith(view: view))
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testGivenAnyUIControlTouchNotAttachedToAnyWindow_itGetsIgnoredForPrivacyReason() {
        // Given
        let handler = touchHandler()
        let uiControl = UIControl()

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touch: .mockWith(view: uiControl))
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testItIgnoresSingleTouchEventWithPhaseOtherThanEnded() {
        // Given
        let handler = touchHandler()
        let view = UIControl().attached(to: mockAppWindow)

        let ignoredTouchPhases: [UITouch.Phase]
        if #available(iOS 13.4, tvOS 13.4, *) {
            ignoredTouchPhases = [.began, .moved, .stationary, .cancelled, .regionEntered, .regionMoved, .regionExited]
        } else {
            ignoredTouchPhases = [.began, .moved, .stationary, .cancelled]
        }

        ignoredTouchPhases.forEach { touchPhase in
            // When
            handler.notify_sendEvent(
                application: .shared,
                event: .mockWith(touch: .mockWith(phase: touchPhase, view: view))
            )

            // Then
            XCTAssertNil(commandSubscriber.lastReceivedCommand)
        }
    }

    func testItIgnoresMultitouchEvents() {
        // Given
        let handler = touchHandler()
        let view = UIControl().attached(to: mockAppWindow)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(
                touches: [
                    .mockWith(view: view), // 1st touch
                    .mockWith(view: view)  // 2nd touch
                ]
            )
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testItIgnoresEventsWithNoTouch() {
        // Given
        let handler = touchHandler()

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touches: nil)
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testGivenTouchEvent_itAppliesUserAttributesAndCustomName() {
        // Given
        let mockAttributes: [AttributeKey: AttributeValue] = mockRandomAttributes()
        let handler = touchHandler(
            with: MockUIKitRUMUserActionsPredicate(
                actionOverride: (name: "foobar", attributes: mockAttributes)
            )
        )
        let view = UIButton()
            .attached(to: mockAppWindow)
            .with(accessibilityIdentifier: "Some Button")
        let event = UIEvent.mockWith(touch: .mockWith(view: view))

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

    func testGivenUserActionPredicateReturnsNil_itDoesntSendTapAction() {
        // Given
        let handler = touchHandler(
            with: MockUIKitRUMUserActionsPredicate(actionOverride: nil)
        )
        let view = UIButton()
            .attached(to: mockAppWindow)
            .with(accessibilityIdentifier: "Some Button")
        let event = UIEvent.mockWith(touch: .mockWith(view: view))

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: event
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    // MARK: - Scenarios For Accepting Click Events

    func testGivenUIPress_whenSinglePressEnds_itSendsRUMAction() {
        // Given
        let handler = pressHandler()
        let fixtures: [(event: UIEvent, expect: String)] = [
            (
                event: .mockWith(
                    press: .mockWith(
                        type: .select,
                        view: UIView()
                            .attached(to: mockAppWindow)
                            .with(accessibilityIdentifier: "Some View")
                    )
                ),
                expect: "UIView(Some View)"
            ),
            (
                event: .mockWith(press: .mockWith(type: .menu, view: UIView().attached(to: mockAppWindow))),
                expect: "menu"
            ),
            (
                event: .mockWith(press: .mockWith(type: .playPause, view: UIView().attached(to: mockAppWindow))),
                expect: "play-pause"
            )
        ]

        fixtures.forEach { event, expect in
            // When
            handler.notify_sendEvent(application: .shared, event: event)

            // Then
            let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
            XCTAssertEqual(command?.name, expect)
            XCTAssertEqual(command?.actionType, .click)
            XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(command?.attributes.count, 0)
        }
    }

    // MARK: - Scenarios For Ignoring Tap Events

    func testGivenAnyViewPresentedInKeyboardWindow_whenPressEnds_itGetsIgnoredForPrivacyReason() {
        let mockKeyboardWindow = MockUIRemoteKeyboardWindow(frame: .zero)

        // Given
        let handler = pressHandler()
        let view = UIView().attached(to: mockKeyboardWindow)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(press: .mockWith(view: view))
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testGivenAnyUIControlPressNotAttachedToAnyWindow_itGetsIgnoredForPrivacyReason() {
        // Given
        let handler = pressHandler()
        let uiControl = UIControl()

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(press: .mockWith(view: uiControl))
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testItIgnoresSinglePressEventWithPhaseOtherThanEnded() {
        // Given
        let handler = pressHandler()
        let view = UIControl().attached(to: mockAppWindow)

        let ignoredPressPhases: [UIPress.Phase] = [.began, .stationary, .cancelled]

        ignoredPressPhases.forEach { phase in
            // When
            handler.notify_sendEvent(
                application: .shared,
                event: .mockWith(press: .mockWith(phase: phase, view: view))
            )

            // Then
            XCTAssertNil(commandSubscriber.lastReceivedCommand)
        }
    }

    func testItIgnoresMultiPressEvents() {
        // Given
        let handler = pressHandler()
        let view = UIControl().attached(to: mockAppWindow)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(
                presses: [
                    .mockWith(view: view), // 1st touch
                    .mockWith(view: view)  // 2nd touch
                ]
            )
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testGivenPressEvent_ItAppliesUserAttributesAndCustomName() {
        // Given
        let mockAttributes: [AttributeKey: AttributeValue] = mockRandomAttributes()
        let handler = pressHandler(
            with: MockUIKitRUMUserActionsPredicate(
                actionOverride: (name: "foobar", attributes: mockAttributes)
            )
        )
        let view = UIButton()
            .attached(to: mockAppWindow)
            .with(accessibilityIdentifier: "Some Button")
        let event = UIEvent.mockWith(press: .mockWith(view: view))

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

    func testGivenUserActionPredicateReturnsNil_itDoesntSendClickAction() {
        // Given
        let handler = pressHandler(
            with: MockUIKitRUMUserActionsPredicate(actionOverride: nil)
        )
        let view = UIButton()
            .attached(to: mockAppWindow)
            .with(accessibilityIdentifier: "Some Button")
        let event = UIEvent.mockWith(press: .mockWith(view: view))

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

private class MockUIKitRUMUserActionsPredicate: UITouchRUMUserActionsPredicate & UIPressRUMUserActionsPredicate {
    private let actionOverride: (name: String, attributes: [AttributeKey: AttributeValue])?

    init(actionOverride: (name: String, attributes: [AttributeKey: AttributeValue])?) {
        self.actionOverride = actionOverride
    }

    func rumAction(targetView: UIView) -> RUMAction? {
        guard let action = actionOverride else {
            return nil
        }

        return RUMAction(name: action.name, attributes: action.attributes)
    }

    func rumAction(press type: UIPress.PressType, targetView: UIView) -> RUMAction? {
        return rumAction(targetView: targetView)
    }
}
