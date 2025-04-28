/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

class RUMActionsHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()

    private func touchHandler(with predicate: UITouchRUMActionsPredicate = DefaultUIKitRUMActionsPredicate()) -> RUMActionsHandler {
        let handler = RUMActionsHandler(dateProvider: dateProvider, predicate: predicate)
        handler.publish(to: commandSubscriber)
        return handler
    }

    private func pressHandler(with predicate: UIPressRUMActionsPredicate = DefaultUIKitRUMActionsPredicate()) -> RUMActionsHandler {
        let handler = RUMActionsHandler(dateProvider: dateProvider, predicate: predicate)
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

    func testGivenUIKitViewWithAccessibilityIdentifier_whenSingleTouchEnds_itSendsRUMAction() {
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
            XCTAssertEqual(command?.instrumentation, .predicate)
            XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(command?.attributes.count, 0)
        }
    }

    func testGivenUIKitViewWithNoAccessibilityIdentifier_whenSingleTouchEnds_itSendsRUMAction() {
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
            XCTAssertEqual(command?.instrumentation, .predicate)
            XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(command?.attributes.count, 0)
        }
    }

    // MARK: - Scenarios For Ignoring Tap Events

    func testGivenAnyUIKitViewWithUnrecognizedHierarchy_whenTouchEnds_itGetsIgnored() {
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

    func testGivenAnyUIKitViewPresentedInKeyboardWindow_whenTouchEnds_itGetsIgnoredForPrivacyReason() {
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

    func testItIgnoresSingleUIKitTouchEventWithPhaseOtherThanEnded() {
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

    func testItIgnoresUIKitMultitouchEvents() {
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

    func testItIgnoresUIKitEventsWithNoTouch() {
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

    func testGivenUIKitTouchEvent_itAppliesUserAttributesAndCustomName() {
        // Given
        let mockAttributes: [AttributeKey: AttributeValue] = mockRandomAttributes()
        let handler = touchHandler(
            with: MockUIKitRUMActionsPredicate(
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
        DDAssertDictionariesEqual(command!.attributes, mockAttributes)
    }

    func testGivenUIKitActionPredicateReturnsNil_itDoesntSendTapAction() {
        // Given
        let handler = touchHandler(
            with: MockUIKitRUMActionsPredicate(actionOverride: nil)
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

    func testGivenUIKitPressEvent_whenSinglePressEnds_itSendsRUMAction() {
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
            XCTAssertEqual(command?.instrumentation, .predicate)
            XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(command?.attributes.count, 0)
        }
    }

    // MARK: - Scenarios For Ignoring Tap Events

    func testGivenAnyUIKitViewPresentedInKeyboardWindow_whenPressEnds_itGetsIgnoredForPrivacyReason() {
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

    func testItIgnoresSingleUIKitPressEventWithPhaseOtherThanEnded() {
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

    func testItIgnoresUIKitMultiPressEvents() {
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

    func testGivenUIKitPressEvent_ItAppliesUserAttributesAndCustomName() {
        // Given
        let mockAttributes: [AttributeKey: AttributeValue] = mockRandomAttributes()
        let handler = pressHandler(
            with: MockUIKitRUMActionsPredicate(
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
        DDAssertDictionariesEqual(command!.attributes, mockAttributes)
    }

    func testGivenUIKitActionPredicateReturnsNil_itDoesntSendClickAction() {
        // Given
        let handler = pressHandler(
            with: MockUIKitRUMActionsPredicate(actionOverride: nil)
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

    // MARK: - SwiftUI Actions

    func testWhenSwiftUIViewModifierIsTapped_itSendsRUMAction() throws {
        // Given
        let handler = oneOf([
            { self.touchHandler() },
            { self.pressHandler() }
        ])

        // When
        let actionName: String = .mockRandom()
        let actionAttributes = mockRandomAttributes()
        handler.notify_viewModifierTapped(actionName: actionName, actionAttributes: actionAttributes)

        // Then
        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.name, actionName)
        XCTAssertEqual(command.actionType, .tap)
        XCTAssertEqual(command.instrumentation, .swiftui)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
        DDAssertReflectionEqual(command.attributes, actionAttributes)
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

private class MockUIKitRUMActionsPredicate: UITouchRUMActionsPredicate & UIPressRUMActionsPredicate {
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
