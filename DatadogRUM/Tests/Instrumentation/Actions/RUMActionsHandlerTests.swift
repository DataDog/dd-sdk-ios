/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@_spi(Internal)
import DatadogInternal
@testable import DatadogRUM

class RUMActionsHandlerTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()

    #if !os(watchOS)
    private func touchHandler(
        with uiKitPredicate: UITouchRUMActionsPredicate = DefaultUIKitRUMActionsPredicate(),
        swiftUIPredicate: SwiftUIRUMActionsPredicate = DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true),
        heatmapRegistry: HeatmapIdentifierRegistryMock = HeatmapIdentifierRegistryMock(),
        sceneIdentifierProvider: @escaping (UIView) -> RUMSceneIdentifier? = { _ in nil }
    ) -> RUMActionsHandler {
        let handler = RUMActionsHandler(
            dateProvider: dateProvider,
            eventCommandsFactory: UITouchCommandFactory(
                dateProvider: dateProvider,
                heatmapIdentifierRegistry: heatmapRegistry,
                uiKitPredicate: uiKitPredicate,
                swiftUIPredicate: swiftUIPredicate,
                swiftUIDetector: SwiftUIComponentFactory.createDetector(),
                sceneIdentifierProvider: sceneIdentifierProvider
            )
        )
        handler.publish(to: commandSubscriber)
        return handler
    }

    private func pressHandler(with predicate: UIPressRUMActionsPredicate = DefaultUIKitRUMActionsPredicate()) -> RUMActionsHandler {
        let handler = RUMActionsHandler(
            dateProvider: dateProvider,
            uiKitPredicate: predicate
        )
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
    #else
    private func watchHandler() -> RUMActionsHandler {
        let handler = RUMActionsHandler(dateProvider: dateProvider)
        handler.publish(to: commandSubscriber)
        return handler
    }
    #endif

    // MARK: - UIKit Automatic Action Tracking

    #if !os(watchOS)

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
            XCTAssertEqual(command?.instrumentation, .uikit)
            XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(command?.attributes.count, 0)
        }
    }

    func testGivenUIKitViewInScene_whenSingleTouchEnds_itTargetsThatScene() {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let handler = touchHandler(sceneIdentifierProvider: { _ in scene })
        let view = UIButton().attached(to: mockAppWindow)

        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touch: .mockWith(view: view))
        )

        let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
        XCTAssertEqual(command?.target, .scene(scene))
    }

    func testGivenUIKitViewInScene_whenDispatchingEvent_itScopesThatScenesRUMContext() {
        let scene = RUMSceneIdentifier(rawValue: "scene-B")
        let context: RUMCoreContext = .mockWith(viewName: "View B")
        let subscriber = SceneContextSubscriber(target: .scene(scene), context: context)
        let handler = RUMActionsHandler(
            dateProvider: dateProvider,
            eventCommandsFactory: UITouchCommandFactory(
                dateProvider: dateProvider,
                heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock(),
                uiKitPredicate: DefaultUIKitRUMActionsPredicate(),
                swiftUIPredicate: DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true),
                swiftUIDetector: SwiftUIComponentFactory.createDetector(),
                sceneIdentifierProvider: { _ in scene }
            ),
            isUIEventContextHandoffEnabled: true
        )
        handler.publish(to: subscriber)
        let view = UIButton().attached(to: mockAppWindow)

        let result = handler.intercept_sendEvent(
            application: .shared,
            event: .mockWith(touch: .mockWith(view: view))
        ) {
            XCTAssertEqual(RUMUIEventNetworkContext.currentSceneIdentifier, scene)
            XCTAssertEqual(RUMUIEventNetworkContext.currentRUMContext?.viewID, context.viewID)
            XCTAssertNil(RUMUIEventNetworkContext.currentRUMContext?.userActionID)
            return true
        }

        XCTAssertTrue(result)
        XCTAssertEqual(subscriber.receivedCommands.count, 1)
        XCTAssertNil(RUMUIEventNetworkContext.currentSceneIdentifier)
        XCTAssertNil(RUMUIEventNetworkContext.currentRUMContext)
    }

    func testGivenUIEventContextHandoffDisabled_whenDispatchingSceneEvent_itKeepsActionOnlyBehavior() {
        let scene = RUMSceneIdentifier(rawValue: "scene-B")
        let context: RUMCoreContext = .mockWith(viewName: "View B")
        let subscriber = SceneContextSubscriber(target: .scene(scene), context: context)
        let handler = RUMActionsHandler(
            dateProvider: dateProvider,
            eventCommandsFactory: UITouchCommandFactory(
                dateProvider: dateProvider,
                heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock(),
                uiKitPredicate: DefaultUIKitRUMActionsPredicate(),
                swiftUIPredicate: DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true),
                swiftUIDetector: SwiftUIComponentFactory.createDetector(),
                sceneIdentifierProvider: { _ in scene }
            )
        )
        handler.publish(to: subscriber)
        let view = UIButton().attached(to: mockAppWindow)

        _ = handler.intercept_sendEvent(
            application: .shared,
            event: .mockWith(touch: .mockWith(view: view))
        ) {
            XCTAssertNil(RUMContextHandoff.current)
            return true
        }

        XCTAssertEqual(subscriber.receivedCommands.count, 1)
    }

    func testGivenActionPredicateRejectsTouch_whenDispatchingEvent_itStillScopesItsScene() {
        let scene = RUMSceneIdentifier(rawValue: "scene-B")
        let context: RUMCoreContext = .mockWith(viewName: "View B")
        let subscriber = SceneContextSubscriber(target: .scene(scene), context: context)
        let handler = RUMActionsHandler(
            dateProvider: dateProvider,
            eventCommandsFactory: UITouchCommandFactory(
                dateProvider: dateProvider,
                heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock(),
                uiKitPredicate: UITouchRUMActionsPredicateMock(result: nil),
                swiftUIPredicate: nil,
                swiftUIDetector: nil,
                sceneIdentifierProvider: { _ in scene }
            ),
            isUIEventContextHandoffEnabled: true
        )
        handler.publish(to: subscriber)
        let view = UIButton().attached(to: mockAppWindow)

        _ = handler.intercept_sendEvent(
            application: .shared,
            event: .mockWith(touch: .mockWith(view: view))
        ) {
            XCTAssertEqual(RUMUIEventNetworkContext.currentSceneIdentifier, scene)
            XCTAssertEqual(RUMUIEventNetworkContext.currentRUMContext?.viewID, context.viewID)
            return true
        }

        XCTAssertTrue(subscriber.receivedCommands.isEmpty)
        XCTAssertNil(RUMUIEventNetworkContext.currentSceneIdentifier)
    }

    func testGivenSceneEventScope_whenCreatingChildTask_itInheritsContextButDetachedTaskDoesNot() async {
        let scene = RUMSceneIdentifier(rawValue: "scene-A")
        let context: RUMCoreContext = .mockWith(viewName: "View A")

        let childTask = RUMUIEventNetworkContext.withValue(
            sceneIdentifier: scene,
            rumContext: context
        ) {
            Task {
                (
                    RUMUIEventNetworkContext.currentSceneIdentifier,
                    RUMUIEventNetworkContext.currentRUMContext
                )
            }
        }
        let childValue = await childTask.value
        XCTAssertEqual(childValue.0, scene)
        XCTAssertEqual(childValue.1, context)

        let detachedTask = RUMUIEventNetworkContext.withValue(
            sceneIdentifier: scene,
            rumContext: context
        ) {
            Task.detached {
                (
                    RUMUIEventNetworkContext.currentSceneIdentifier,
                    RUMUIEventNetworkContext.currentRUMContext
                )
            }
        }
        let detachedValue = await detachedTask.value
        XCTAssertNil(detachedValue.0)
        XCTAssertNil(detachedValue.1)
    }

    func testGivenMultiTouchEvent_whenAllTouchesShareScene_itScopesWithoutCreatingTapAction() {
        let sceneA = RUMSceneIdentifier(rawValue: "scene-A")
        let sceneB = RUMSceneIdentifier(rawValue: "scene-B")
        let firstView = UIView().attached(to: mockAppWindow)
        let secondView = UIView().attached(to: mockAppWindow)
        let otherSceneView = UIView().attached(to: mockAppWindow)
        let subscriber = SceneContextSubscriber(
            target: .scene(sceneA),
            context: .mockWith(viewName: "View A")
        )
        let handler = RUMActionsHandler(
            dateProvider: dateProvider,
            eventCommandsFactory: UITouchCommandFactory(
                dateProvider: dateProvider,
                heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock(),
                uiKitPredicate: nil,
                swiftUIPredicate: nil,
                swiftUIDetector: nil,
                sceneIdentifierProvider: { view in
                    view === otherSceneView ? sceneB : sceneA
                }
            ),
            isUIEventContextHandoffEnabled: true
        )
        handler.publish(to: subscriber)

        _ = handler.intercept_sendEvent(
            application: .shared,
            event: .mockWith(touches: [
                .mockWith(view: firstView),
                .mockWith(view: secondView)
            ])
        ) {
            XCTAssertEqual(RUMUIEventNetworkContext.currentSceneIdentifier, sceneA)
            return true
        }
        XCTAssertTrue(subscriber.receivedCommands.isEmpty)

        _ = handler.intercept_sendEvent(
            application: .shared,
            event: .mockWith(touches: [
                .mockWith(view: firstView),
                .mockWith(view: otherSceneView)
            ])
        ) {
            XCTAssertNil(RUMUIEventNetworkContext.currentSceneIdentifier)
            return true
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
            XCTAssertEqual(command?.instrumentation, .uikit)
            XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(command?.attributes.count, 0)
        }
    }

    // MARK: - Heatmap attributes

    func testWhenTapViewIsInRegistry_itLooksUpHeatmapByTapView() {
        // Given
        let cell = UITableViewCell(frame: .init(x: 0, y: 0, width: 320, height: 88))
        mockAppWindow.addSubview(cell)
        cell.accessibilityIdentifier = "Item: 3"
        let leaf = UIView(frame: .init(x: 10, y: 20, width: 100, height: 30))
        cell.contentView.addSubview(leaf)

        let registry = HeatmapIdentifierRegistryMock(identifiers: [
            ObjectIdentifier(cell): HeatmapIdentifier(rawValue: "cell-id"),
            ObjectIdentifier(leaf): HeatmapIdentifier(rawValue: "leaf-id"),
        ])
        let handler = touchHandler(heatmapRegistry: registry)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touch: .mockWith(view: leaf))
        )

        // Then
        let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
        XCTAssertEqual(command?.heatmapAttributes?.targetPermanentID, "leaf-id")
        XCTAssertEqual(command?.heatmapAttributes?.targetWidth, 100)
        XCTAssertEqual(command?.heatmapAttributes?.targetHeight, 30)
    }

    func testWhenTapViewIsNotInRegistry_itDoesNotAttachHeatmapAttributes() {
        // Given
        let cell = UITableViewCell()
        mockAppWindow.addSubview(cell)
        cell.accessibilityIdentifier = "Item: 3"
        let leaf = UIView()
        cell.contentView.addSubview(leaf)

        let registry = HeatmapIdentifierRegistryMock(identifiers: [
            ObjectIdentifier(cell): HeatmapIdentifier(rawValue: "cell-id"),
        ])
        let handler = touchHandler(heatmapRegistry: registry)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touch: .mockWith(view: leaf))
        )

        // Then
        let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
        XCTAssertNotNil(command)
        XCTAssertNil(command?.heatmapAttributes)
    }

    // MARK: - UIKit Automatic Action Tracking (iOS, UITouch events)

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

        let ignoredTouchPhases: [UITouch.Phase] = [.began, .moved, .stationary, .cancelled, .regionEntered, .regionMoved, .regionExited]

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

    // MARK: - UIKit Automatic Action Tracking (tvOS, UIPress events)

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
            XCTAssertEqual(command?.instrumentation, .uikit)
            XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
            XCTAssertEqual(command?.attributes.count, 0)
        }
    }

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

    #endif // !os(watchOS)

    // MARK: - SwiftUI View Modifier Actions

    func testWhenSwiftUIViewModifierIsTapped_itSendsRUMAction() throws {
        // Given
        #if os(watchOS)
        let handler = watchHandler()
        #else
        let handler = oneOf([
            { self.touchHandler() },
            { self.pressHandler() }
        ])
        #endif

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

    #if !os(watchOS)
    func testWhenSwiftUIViewModifierIsTappedInScene_itTargetsThatScene() throws {
        let handler = touchHandler()
        let scene = RUMSceneIdentifier(rawValue: "scene-A")

        handler.notify_viewModifierTapped(
            actionName: "Action in A",
            actionAttributes: [:],
            sceneIdentifier: scene
        )

        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.target, .scene(scene))
    }
    #endif
}

// MARK: - Helpers

#if !os(watchOS)

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

private final class SceneContextSubscriber: RUMCommandSubscriber, RUMContextSnapshotProviding {
    var receivedCommands: [RUMCommand] = []
    let target: RUMCommandTarget
    let context: RUMCoreContext

    init(target: RUMCommandTarget, context: RUMCoreContext) {
        self.target = target
        self.context = context
    }

    func process(command: RUMCommand) {
        receivedCommands.append(command)
    }

    func rumContextSnapshot(for target: RUMCommandTarget) -> RUMCoreContext? {
        target == self.target ? context : nil
    }
}

#endif // !os(watchOS)
