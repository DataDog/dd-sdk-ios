/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(macOS)
import XCTest
@testable import TestUtilities
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
        heatmapRegistry: HeatmapIdentifierRegistryMock = HeatmapIdentifierRegistryMock()
    ) -> RUMActionsHandler {
        let handler = RUMActionsHandler(
            dateProvider: dateProvider,
            heatmapIdentifierRegistry: heatmapRegistry,
            uiKitPredicate: uiKitPredicate,
            swiftUIPredicate: swiftUIPredicate,
            swiftUIDetector: SwiftUIComponentFactory.createDetector()
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

    func testWhenTapViewLayerIsInRegistry_itLooksUpHeatmapByTapViewLayer() {
        // Given
        let cell = UITableViewCell(frame: .init(x: 0, y: 0, width: 320, height: 88))
        mockAppWindow.addSubview(cell)
        cell.accessibilityIdentifier = "Item: 3"
        let leaf = UIView(frame: .init(x: 10, y: 20, width: 100, height: 30))
        cell.contentView.addSubview(leaf)

        let registry = HeatmapIdentifierRegistryMock(identifiers: [
            ObjectIdentifier(cell.layer): HeatmapIdentifier(rawValue: "cell-id"),
            ObjectIdentifier(leaf.layer): HeatmapIdentifier(rawValue: "leaf-id"),
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

    func testWhenDescendantLookupIsNotRequired_itUsesTapViewLayerHeatmapAttributes() {
        // Given
        let view = UIControl(frame: .init(x: 0, y: 0, width: 200, height: 100))
            .attached(to: mockAppWindow)
        let targetLayer = CALayer()
        targetLayer.frame = .init(x: 20, y: 30, width: 80, height: 40)
        view.layer.addSublayer(targetLayer)

        let registry = HeatmapIdentifierRegistryMock(identifiers: [
            ObjectIdentifier(view.layer): HeatmapIdentifier(rawValue: "view-id"),
            ObjectIdentifier(targetLayer): HeatmapIdentifier(rawValue: "layer-id"),
        ], requiresDescendantLookup: false)
        let handler = touchHandler(heatmapRegistry: registry)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(
                touch: UITouchMock(phase: .ended, location: .init(x: 50, y: 50), view: view)
            )
        )

        // Then
        let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
        XCTAssertEqual(command?.heatmapAttributes?.targetPermanentID, "view-id")
        XCTAssertEqual(command?.heatmapAttributes?.targetWidth, 200)
        XCTAssertEqual(command?.heatmapAttributes?.targetHeight, 100)
        XCTAssertEqual(command?.heatmapAttributes?.positionX, 50)
        XCTAssertEqual(command?.heatmapAttributes?.positionY, 50)
    }

    func testWhenTapHitsRegisteredSublayer_itUsesSublayerHeatmapAttributes() {
        // Given
        let view = UIControl(frame: .init(x: 100, y: 200, width: 200, height: 100))
            .attached(to: mockAppWindow)
        let targetLayer = CALayer()
        targetLayer.frame = .init(x: 20, y: 30, width: 80, height: 40)
        targetLayer.bounds.origin = .init(x: 10, y: 15)
        view.layer.addSublayer(targetLayer)

        let registry = HeatmapIdentifierRegistryMock(identifiers: [
            ObjectIdentifier(view.layer): HeatmapIdentifier(rawValue: "view-id"),
            ObjectIdentifier(targetLayer): HeatmapIdentifier(rawValue: "layer-id"),
        ], requiresDescendantLookup: true)
        let handler = touchHandler(heatmapRegistry: registry)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(
                touch: UITouchMock(phase: .ended, location: .init(x: 50, y: 50), view: view)
            )
        )

        // Then
        let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
        XCTAssertEqual(command?.heatmapAttributes?.targetPermanentID, "layer-id")
        XCTAssertEqual(command?.heatmapAttributes?.targetWidth, 80)
        XCTAssertEqual(command?.heatmapAttributes?.targetHeight, 40)
        XCTAssertEqual(command?.heatmapAttributes?.positionX, 30)
        XCTAssertEqual(command?.heatmapAttributes?.positionY, 20)
    }

    func testWhenHitSublayerIsNotRegistered_itUsesTapViewLayerHeatmapAttributes() {
        // Given
        let view = UIControl(frame: .init(x: 0, y: 0, width: 200, height: 100))
            .attached(to: mockAppWindow)
        let sublayer = CALayer()
        sublayer.frame = .init(x: 20, y: 30, width: 80, height: 40)
        view.layer.addSublayer(sublayer)

        let registry = HeatmapIdentifierRegistryMock(identifiers: [
            ObjectIdentifier(view.layer): HeatmapIdentifier(rawValue: "view-id"),
        ], requiresDescendantLookup: true)
        let handler = touchHandler(heatmapRegistry: registry)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(
                touch: UITouchMock(phase: .ended, location: .init(x: 50, y: 50), view: view)
            )
        )

        // Then
        let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
        XCTAssertEqual(command?.heatmapAttributes?.targetPermanentID, "view-id")
        XCTAssertEqual(command?.heatmapAttributes?.targetWidth, 200)
        XCTAssertEqual(command?.heatmapAttributes?.targetHeight, 100)
        XCTAssertEqual(command?.heatmapAttributes?.positionX, 50)
        XCTAssertEqual(command?.heatmapAttributes?.positionY, 50)
    }

    func testWhenSwiftUIAutomaticTapHitsRegisteredSublayer_itAttachesHeatmapAttributes() {
        // Given
        let view = SwiftUIActionViewMock(frame: .init(x: 0, y: 0, width: 200, height: 100))
        mockAppWindow.addSubview(view)
        let targetLayer = CALayer()
        targetLayer.frame = .init(x: 20, y: 30, width: 80, height: 40)
        view.layer.addSublayer(targetLayer)

        let registry = HeatmapIdentifierRegistryMock(identifiers: [
            ObjectIdentifier(targetLayer): HeatmapIdentifier(rawValue: "layer-id"),
        ], requiresDescendantLookup: true)
        let handler = RUMActionsHandler(
            dateProvider: dateProvider,
            heatmapIdentifierRegistry: registry,
            uiKitPredicate: nil,
            swiftUIPredicate: DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true),
            swiftUIDetector: LegacySwiftUIComponentDetector()
        )
        handler.publish(to: commandSubscriber)

        // When
        handler.notify_sendEvent(
            application: .shared,
            event: .mockWith(
                touch: UITouchMock(phase: .ended, location: .init(x: 50, y: 50), view: view)
            )
        )

        // Then
        let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
        XCTAssertEqual(command?.instrumentation, .swiftuiAutomatic)
        XCTAssertEqual(command?.heatmapAttributes?.targetPermanentID, "layer-id")
        XCTAssertEqual(command?.heatmapAttributes?.targetWidth, 80)
        XCTAssertEqual(command?.heatmapAttributes?.targetHeight, 40)
        XCTAssertEqual(command?.heatmapAttributes?.positionX, 30)
        XCTAssertEqual(command?.heatmapAttributes?.positionY, 20)
    }

    func testWhenTapViewLayerIsNotInRegistry_itDoesNotAttachHeatmapAttributes() {
        // Given
        let cell = UITableViewCell()
        mockAppWindow.addSubview(cell)
        cell.accessibilityIdentifier = "Item: 3"
        let leaf = UIView()
        cell.contentView.addSubview(leaf)

        let registry = HeatmapIdentifierRegistryMock(identifiers: [
            ObjectIdentifier(cell.layer): HeatmapIdentifier(rawValue: "cell-id"),
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

private class SwiftUIActionViewMock: UIView {}

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

#endif // !os(watchOS)
#endif

#if os(iOS)
@available(iOS 27.0, *)
@MainActor
extension RUMActionsHandlerTests {
    private func inputFixture(predicate: UITouchRUMActionsPredicate = DefaultUIKitRUMActionsPredicate(), startA: Bool = true) -> SceneInputFixture {
        SceneInputFixture(predicate: predicate, startA: startA)
    }

    func testSceneInput_capturesOriginalWindowBeforePredicateReparenting() throws {
        let predicate = SceneInputPredicate()
        let fixture = inputFixture(predicate: predicate)
        defer { predicate.onAction = nil; fixture.monitor.onAction = nil }
        let view = UIButton()
        fixture.windowB.addSubview(view)
        let event = UIEvent.mockWith(touch: SceneInputTouch(originalWindow: fixture.windowA, view: view))
        let a = try XCTUnwrap(fixture.monitor.rumContextSnapshot(for: .scene(fixture.sceneA)))
        let b = try XCTUnwrap(fixture.monitor.rumContextSnapshot(for: .processRepresentative))
        XCTAssertNotEqual(a.viewID, b.viewID)
        var order: [String] = []
        predicate.onAction = { _ in
            order.append("predicate")
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.rumContext?.viewID, a.viewID)
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.hasPendingUserAction, false)
            fixture.windowA.addSubview(view)
        }
        fixture.monitor.onAction = { command in
            order.append("publish")
            XCTAssertEqual(command.target, .scene(fixture.sceneA))
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.rumContext?.viewID, a.viewID)
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.hasPendingUserAction, true)
        }
        fixture.handler.intercept(application: .shared, event: event) {
            order.append("previous")
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.rumContext?.viewID, a.viewID)
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.sceneIdentifier, "a")
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.hasPendingUserAction, true)
        }
        XCTAssertEqual(order, ["predicate", "publish", "previous"])
        XCTAssertEqual(fixture.factory.calls, 1)
        XCTAssertNil(RUMContextHandoff.current(for: fixture.owner))
    }

    func testSceneInput_predicateMovesViewToPeerAfterSourceCapture() {
        let predicate = SceneInputPredicate()
        let fixture = inputFixture(predicate: predicate)
        defer { predicate.onAction = nil }
        let view = UIButton()
        fixture.windowA.addSubview(view)
        predicate.onAction = { _ in fixture.windowB.addSubview(view) }
        fixture.handler.intercept(application: .shared, event: .mockWith(touch: SceneInputTouch(originalWindow: fixture.windowA, view: view))) {
            XCTAssertIdentical(view.window, fixture.windowB)
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.sceneIdentifier, "a")
        }
        XCTAssertEqual(fixture.monitor.actions.last?.target, .scene(fixture.sceneA))
    }

    func testSceneInput_monitorReleasedAfterEligibilityCallsPreviousWithoutPending() {
        let owner = RUMContextHandoff.Owner()
        let clock = DateProviderMock()
        var monitor: SceneInputMonitor? = SceneInputMonitor(owner: owner, clock: clock)
        weak var weakMonitor = monitor
        let factory = UITouchCommandFactory(dateProvider: clock, heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock(), uiKitPredicate: DefaultUIKitRUMActionsPredicate(), swiftUIPredicate: nil, swiftUIDetector: nil)
        let handler = RUMSceneActionsHandler(legacyHandler: RUMActionsHandler(dateProvider: clock, eventCommandsFactory: factory), eventCommandsFactory: factory, dateProvider: clock, owner: owner, expectedMonitor: monitor!, sceneIdentifier: { _ in RUMSceneIdentifier(rawValue: "a") })
        handler.publish(to: monitor!)
        var ownerReads = 0
        monitor?.onOwnerRead = {
            ownerReads += 1
            if ownerReads == 2 { monitor = nil }
        }
        let window = UIWindow(frame: .zero)
        let view = UIButton()
        window.addSubview(view)
        var previousCalls = 0
        handler.intercept(application: .shared, event: .mockWith(touch: SceneInputTouch(originalWindow: window, view: view))) {
            previousCalls += 1
            XCTAssertNil(weakMonitor)
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.sceneIdentifier, "a")
            XCTAssertEqual(RUMContextHandoff.current(for: owner)?.hasPendingUserAction, false)
        }
        XCTAssertEqual(ownerReads, 2)
        XCTAssertEqual(previousCalls, 1)
        XCTAssertNil(weakMonitor)
    }

    func testSceneInput_nilOriginalUsesCurrentWindowButUnattachedOriginalDoesNotBorrowIt() {
        let fixture = inputFixture()
        let view = UIButton()
        fixture.windowB.addSubview(view)
        fixture.handler.intercept(application: .shared, event: .mockWith(touch: SceneInputTouch(originalWindow: nil, view: view))) {
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.sceneIdentifier, "b")
        }
        XCTAssertEqual(fixture.monitor.actions.last?.target, .scene(fixture.sceneB))
        let unattached = UIWindow(frame: .zero)
        let beforeReads = fixture.monitor.ownerReads
        fixture.handler.intercept(application: .shared, event: .mockWith(touch: SceneInputTouch(originalWindow: unattached, view: view))) {
            XCTAssertNil(RUMContextHandoff.current(for: fixture.owner))
        }
        XCTAssertEqual(fixture.monitor.actions.last?.target, .processRepresentative)
        XCTAssertEqual(fixture.monitor.ownerReads, beforeReads)
    }

    func testSceneInput_missingAndAmbiguousSourcesPreserveInheritedContextWithoutPending() {
        let fixture = inputFixture()
        let outer = RUMContextHandoff.CurrentValue(rumContext: nil, sceneIdentifier: "outer", hasPendingUserAction: false, excludedUserActionID: nil)
        let view = UIButton()
        let sourceLessWindow = UIWindow(frame: .zero)
        sourceLessWindow.addSubview(view)
        let absent = SceneInputTouch(originalWindow: nil, view: view)
        let attached = SceneInputTouch(originalWindow: fixture.windowA, view: view)
        var previousCalls = 0
        let beforeReads = fixture.monitor.ownerReads
        RUMContextHandoff.withValue(outer, for: fixture.owner) {
            for event in [UIEvent.mockWith(touch: absent), UIEvent.mockWith(touches: [absent, attached]), UIEvent()] {
                fixture.handler.intercept(application: .shared, event: event) {
                    previousCalls += 1
                    XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.sceneIdentifier, "outer")
                    XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.hasPendingUserAction, false)
                }
            }
        }
        XCTAssertEqual(previousCalls, 3)
        XCTAssertEqual(fixture.monitor.ownerReads, beforeReads)
        XCTAssertEqual(fixture.monitor.actions.map(\.target), [.processRepresentative])
        XCTAssertNil(RUMContextHandoff.current(for: fixture.owner))
    }

    func testSceneInput_missingSnapshotIsAuthoritativeForAttachedScene() {
        let fixture = inputFixture(startA: false)
        let view = UIButton()
        fixture.windowA.addSubview(view)
        XCTAssertNotNil(fixture.monitor.rumContextSnapshot(for: .processRepresentative))
        fixture.handler.intercept(application: .shared, event: .mockWith(touch: SceneInputTouch(originalWindow: fixture.windowA, view: view))) {
            let value = RUMContextHandoff.current(for: fixture.owner)
            XCTAssertNotNil(value)
            XCTAssertNil(value?.rumContext)
            XCTAssertEqual(value?.sceneIdentifier, "a")
            XCTAssertEqual(value?.hasPendingUserAction, true)
        }
        XCTAssertEqual(fixture.monitor.actions.last?.target, .scene(fixture.sceneA))
    }

    func testSceneInput_filteredCommandKeepsCapturedSceneWithoutPending() {
        let fixture = inputFixture(predicate: UITouchRUMActionsPredicateMock())
        let view = UIButton()
        fixture.windowA.addSubview(view)
        fixture.handler.intercept(application: .shared, event: .mockWith(touch: SceneInputTouch(originalWindow: fixture.windowA, view: view))) {
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.sceneIdentifier, "a")
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.hasPendingUserAction, false)
            XCTAssertNil(RUMContextHandoff.current(for: fixture.owner)?.excludedUserActionID)
        }
        XCTAssertTrue(fixture.monitor.actions.isEmpty)
        XCTAssertEqual(fixture.factory.calls, 1)
    }

    func testSceneInput_pendingExcludesOnlyCapturedPriorAction() throws {
        let fixture = inputFixture()
        fixture.monitor.startAction(type: .custom, name: "prior-a", attributes: [:], explicitTarget: .scene(fixture.sceneA))
        let prior = try XCTUnwrap(fixture.monitor.rumContextSnapshot(for: .scene(fixture.sceneA))?.userActionID)
        let view = UIButton()
        fixture.windowA.addSubview(view)
        fixture.handler.intercept(application: .shared, event: .mockWith(touch: SceneInputTouch(originalWindow: fixture.windowA, view: view))) {
            let current = RUMContextHandoff.current(for: fixture.owner)
            XCTAssertEqual(current?.rumContext?.userActionID, prior)
            XCTAssertEqual(current?.excludedUserActionID, prior)
            XCTAssertEqual(current?.hasPendingUserAction, true)
        }
    }

    func testSceneInput_replacedSubscriberAfterEligibilityCallsPreviousWithoutPending() {
        let fixture = inputFixture()
        let foreign = RUMCommandSubscriberMock()
        fixture.monitor.onOwnerRead = {
            if fixture.monitor.ownerReads == 2 {
                fixture.handler.publish(to: foreign)
            }
        }
        let view = UIButton()
        fixture.windowA.addSubview(view)
        var previousCalls = 0
        fixture.handler.intercept(application: .shared, event: .mockWith(touch: SceneInputTouch(originalWindow: fixture.windowA, view: view))) {
            previousCalls += 1
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.sceneIdentifier, "a")
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.hasPendingUserAction, false)
        }
        XCTAssertEqual(previousCalls, 1)
        XCTAssertTrue(fixture.monitor.actions.isEmpty)
        XCTAssertTrue(foreign.receivedCommands.isEmpty)
        fixture.monitor.onOwnerRead = nil
    }

    func testSceneInput_foreignOwnerCannotSupplySnapshotOrReceiveTargetedCommand() {
        let fixture = inputFixture()
        fixture.monitor.currentOwner = RUMContextHandoff.Owner()
        let view = UIButton()
        fixture.windowA.addSubview(view)
        fixture.handler.intercept(application: .shared, event: .mockWith(touch: SceneInputTouch(originalWindow: fixture.windowA, view: view))) {
            let current = RUMContextHandoff.current(for: fixture.owner)
            XCTAssertNotNil(current)
            XCTAssertNil(current?.rumContext)
            XCTAssertEqual(current?.sceneIdentifier, "a")
            XCTAssertEqual(current?.hasPendingUserAction, false)
        }
        XCTAssertTrue(fixture.monitor.actions.isEmpty)
    }

    func testSceneInput_predicateInvalidationDoesNotPublishOrOverrideFreshOwner() {
        let predicate = SceneInputPredicate()
        let fixture = inputFixture(predicate: predicate)
        defer { predicate.onAction = nil }
        let freshOwner = RUMContextHandoff.Owner()
        predicate.onAction = { _ in fixture.owner.invalidate(); fixture.monitor.currentOwner = freshOwner }
        let view = UIButton()
        fixture.windowA.addSubview(view)
        var previousCalls = 0
        fixture.handler.intercept(application: .shared, event: .mockWith(touch: SceneInputTouch(originalWindow: fixture.windowA, view: view))) {
            previousCalls += 1
            XCTAssertNil(RUMContextHandoff.current(for: fixture.owner))
            XCTAssertNil(RUMContextHandoff.current(for: freshOwner))
        }
        XCTAssertEqual(previousCalls, 1)
        XCTAssertTrue(fixture.monitor.actions.isEmpty)
    }

    func testSceneInput_nestedDifferentAndSourceLessEventsRestoreOuterBinding() {
        let fixture = inputFixture()
        let view = UIButton()
        fixture.windowA.addSubview(view)
        let a = UIEvent.mockWith(touch: SceneInputTouch(originalWindow: fixture.windowA, view: view))
        let b = UIEvent.mockWith(touch: SceneInputTouch(originalWindow: fixture.windowB, view: view))
        fixture.handler.intercept(application: .shared, event: a) {
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.sceneIdentifier, "a")
            fixture.handler.intercept(application: .shared, event: b) {
                XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.sceneIdentifier, "b")
            }
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.sceneIdentifier, "a")
            fixture.handler.intercept(application: .shared, event: UIEvent()) {
                XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.sceneIdentifier, "a")
            }
            XCTAssertEqual(RUMContextHandoff.current(for: fixture.owner)?.sceneIdentifier, "a")
        }
        XCTAssertNil(RUMContextHandoff.current(for: fixture.owner))
    }

    func testSceneInput_reusesFactoryOutputsAndForwardsManualNotifications() throws {
        let fixture = inputFixture()
        let view = UIButton()
        view.accessibilityIdentifier = "button"
        fixture.windowA.addSubview(view)
        let event = UIEvent.mockWith(touch: SceneInputTouch(originalWindow: fixture.windowA, view: view))
        let expected = try XCTUnwrap(fixture.factory.base.command(from: event))
        fixture.handler.intercept(application: .shared, event: event, operation: {})
        let actual = try XCTUnwrap(fixture.monitor.actions.last)
        XCTAssertEqual(actual.name, expected.name)
        XCTAssertEqual(actual.time, expected.time)
        XCTAssertEqual(actual.instrumentation, expected.instrumentation)
        XCTAssertEqual(actual.actionType, expected.actionType)
        DDAssertDictionariesEqual(actual.attributes, expected.attributes)
        XCTAssertEqual(actual.heatmapAttributes, expected.heatmapAttributes)
        XCTAssertEqual(fixture.factory.calls, 1)
        fixture.handler.notify_viewModifierTapped(actionName: "manual", actionAttributes: ["key": "value"])
        XCTAssertEqual(fixture.monitor.actions.last?.target, .processRepresentative)
        XCTAssertEqual(fixture.monitor.actions.last?.instrumentation, .swiftui)
        XCTAssertEqual(fixture.monitor.actions.last?.name, "manual")
    }

    func testSceneInput_doesNotRetainExpectedMonitorOrSubscriber() {
        let owner = RUMContextHandoff.Owner()
        let clock = DateProviderMock()
        var monitor: SceneInputMonitor? = SceneInputMonitor(owner: owner, clock: clock)
        weak var weakMonitor = monitor
        let handler = RUMSceneActionsHandler(
            legacyHandler: RUMActionsHandler(dateProvider: clock, eventCommandsFactory: nil),
            eventCommandsFactory: nil,
            dateProvider: clock,
            owner: owner,
            expectedMonitor: monitor!
        )
        handler.publish(to: monitor!)
        monitor = nil
        XCTAssertNil(weakMonitor)
        var previousCalls = 0
        handler.intercept(application: .shared, event: UIEvent()) { previousCalls += 1 }
        XCTAssertEqual(previousCalls, 1)
    }

    func testSceneInput_expiredSnapshotDoesNotBorrowRepresentativeOrPriorAction() {
        let fixture = inputFixture()
        fixture.clock.now = fixture.clock.now.addingTimeInterval(16 * 60)
        let view = UIButton()
        fixture.windowA.addSubview(view)
        fixture.handler.intercept(application: .shared, event: .mockWith(touch: SceneInputTouch(originalWindow: fixture.windowA, view: view))) {
            let value = RUMContextHandoff.current(for: fixture.owner)
            XCTAssertNotNil(value)
            XCTAssertNil(value?.rumContext)
            XCTAssertEqual(value?.sceneIdentifier, "a")
            XCTAssertNil(value?.excludedUserActionID)
        }
        XCTAssertEqual(fixture.monitor.actions.last?.target, .scene(fixture.sceneA))
    }
}

@MainActor
@available(iOS 27.0, *)
private final class SceneInputFixture {
    let owner = RUMContextHandoff.Owner()
    let clock = DateProviderMock(now: Date(timeIntervalSince1970: 1_600_000_000))
    let windowA = UIWindow(frame: .zero)
    let windowB = UIWindow(frame: .zero)
    let sceneA = RUMSceneIdentifier(rawValue: "a")
    let sceneB = RUMSceneIdentifier(rawValue: "b")
    let monitor: SceneInputMonitor
    let factory: SceneInputFactory
    let handler: RUMSceneActionsHandler

    init(predicate: UITouchRUMActionsPredicate = DefaultUIKitRUMActionsPredicate(), startA: Bool = true) {
        monitor = SceneInputMonitor(owner: owner, clock: clock)
        factory = SceneInputFactory(base: UITouchCommandFactory(dateProvider: clock, heatmapIdentifierRegistry: HeatmapIdentifierRegistryMock(), uiKitPredicate: predicate, swiftUIPredicate: nil, swiftUIDetector: nil))
        let a = windowA, b = windowB
        handler = RUMSceneActionsHandler(legacyHandler: RUMActionsHandler(dateProvider: clock, eventCommandsFactory: factory), eventCommandsFactory: factory, dateProvider: clock, owner: owner, expectedMonitor: monitor, sceneIdentifier: { window in
            window === a ? RUMSceneIdentifier(rawValue: "a") : (window === b ? RUMSceneIdentifier(rawValue: "b") : nil)
        })
        handler.publish(to: monitor)
        for (key, target) in [("a", sceneA), ("b", sceneB)] where startA || key == "b" {
            monitor.process(command: RUMStartViewCommand(time: clock.now, identity: ViewIdentifier(key), name: key, path: key, globalAttributes: [:], attributes: [:], instrumentationType: .manual, target: .scene(target)))
        }
        monitor.ownerReads = 0
    }
}

private final class SceneInputMonitor: Monitor {
    var currentOwner: RUMContextHandoff.Owner?
    var ownerReads = 0
    var onOwnerRead: (() -> Void)?
    var actions: [RUMAddUserActionCommand] = []
    var onAction: ((RUMAddUserActionCommand) -> Void)?
    override var rumContextHandoffOwner: RUMContextHandoff.Owner? {
        ownerReads += 1
        let owner = currentOwner
        onOwnerRead?()
        return owner
    }
    init(owner: RUMContextHandoff.Owner, clock: DateProvider) {
        currentOwner = owner
        let scope = FeatureScopeMock(context: .mockWith(
            sdkInitDate: clock.now,
            applicationStateHistory: .mockWith(initialState: .active, date: clock.now)
        ))
        super.init(dependencies: .mockWith(featureScope: scope, viewCache: ViewCache(dateProvider: clock, isMultiSceneTrackingEnabled: true), featureFlags: [.multiSceneTracking: true]), dateProvider: clock, executionContextProvider: RUMContextHandoff.current(for:))
    }
    override func process(command: RUMCommand) {
        if let action = command as? RUMAddUserActionCommand { actions.append(action); onAction?(action) }
        super.process(command: command)
    }
}

private final class SceneInputFactory: UIEventCommandFactory {
    let base: UIEventCommandFactory
    var calls = 0
    init(base: UIEventCommandFactory) { self.base = base }
    func command(from event: UIEvent) -> RUMAddUserActionCommand? { calls += 1; return base.command(from: event) }
}

private final class SceneInputPredicate: UITouchRUMActionsPredicate {
    var onAction: ((UIView) -> Void)?
    func rumAction(targetView: UIView) -> RUMAction? { onAction?(targetView); return RUMAction(name: "selected") }
}

private final class SceneInputTouch: UITouch {
    private let originalWindow: UIWindow?
    private let currentView: UIView
    init(originalWindow: UIWindow?, view: UIView) {
        self.originalWindow = originalWindow
        currentView = view
        super.init()
    }
    override var window: UIWindow? { originalWindow }
    override var view: UIView? { currentView }
    override var phase: UITouch.Phase { .ended }
    override func location(in view: UIView?) -> CGPoint { .zero }
}
#endif

#if os(iOS)
import UIKit

@available(iOS 27.0, *)
@MainActor
final class SceneApplicationInstrumentationTests: XCTestCase {
    private func actualApplication() throws -> UIApplication {
        let application = UIApplication.shared
        _ = try XCTUnwrap(object_getClass(application), "Requires a live UIKit test host")
        return application
    }

    private func verifyPreviousCall(_ spy: UIKitPreviousSpy, application: UIApplication, event: UIEvent) {
        application.sendEvent(event)
        XCTAssertEqual(spy.calls, 1, "The independent UIKit call-through must work before installing the SDK layer")
        spy.calls = 0
    }

    func testSceneSendEvent_callsActualVoidUIKitImplementationOnceWithoutLegacyNotification() throws {
        let application = try actualApplication()
        let target = UIEvent()
        let previous = UIKitPreviousSpy(target: target)
        try previous.install()
        defer { previous.unswizzle() }
        verifyPreviousCall(previous, application: application, event: target)
        let handler = SceneDispatchHandler()
        let instrumentation = try DDSceneApplicationInstrumentation(handler: handler)
        instrumentation.install()
        defer { instrumentation.uninstall() }
        application.sendEvent(target)
        XCTAssertEqual(handler.intercepts, 1)
        XCTAssertEqual(handler.legacyNotifications, 0, "The unused base layer must not be installed")
        XCTAssertEqual(previous.calls, 1)
        let method = try dd_class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:)))
        XCTAssertTrue(String(cString: method_getTypeEncoding(method)!).hasPrefix("v"))
    }

    func testSceneSendEvent_uninstallAndDeinitPreserveIndependentVoidLayer() throws {
        let application = try actualApplication()
        let target = UIEvent()
        let previous = UIKitPreviousSpy(target: target)
        try previous.install()
        defer { previous.unswizzle() }
        verifyPreviousCall(previous, application: application, event: target)
        let handler = SceneDispatchHandler()
        var instrumentation: DDSceneApplicationInstrumentation? = try DDSceneApplicationInstrumentation(handler: handler)
        instrumentation?.install()
        let later = UIKitPreviousSpy(target: target)
        try later.install()
        defer { later.unswizzle() }
        application.sendEvent(target)
        XCTAssertEqual(handler.intercepts, 1)
        XCTAssertEqual(previous.calls, 1)
        XCTAssertEqual(later.calls, 1)
        instrumentation?.uninstall()
        application.sendEvent(target)
        XCTAssertEqual(handler.intercepts, 1)
        XCTAssertEqual(previous.calls, 2)
        XCTAssertEqual(later.calls, 2)
        instrumentation?.install()
        application.sendEvent(target)
        XCTAssertEqual(handler.intercepts, 2)
        XCTAssertEqual(previous.calls, 3)
        XCTAssertEqual(later.calls, 3)
        instrumentation = nil
        application.sendEvent(target)
        XCTAssertEqual(handler.intercepts, 2)
        XCTAssertEqual(handler.legacyNotifications, 0)
        XCTAssertEqual(previous.calls, 4)
        XCTAssertEqual(later.calls, 4)
    }

    func testSceneSendEvent_releasedHandlerStillCallsActualUIKitImplementationOnce() throws {
        let application = try actualApplication()
        let target = UIEvent()
        let previous = UIKitPreviousSpy(target: target)
        try previous.install()
        defer { previous.unswizzle() }
        verifyPreviousCall(previous, application: application, event: target)
        var handler: SceneDispatchHandler? = SceneDispatchHandler()
        weak var weakHandler = handler
        let swizzler = try DDSceneApplicationInstrumentation.SceneSendEvent(handler: handler!)
        swizzler.swizzle()
        defer { swizzler.unswizzle() }
        handler = nil
        XCTAssertNil(weakHandler)
        application.sendEvent(target)
        XCTAssertEqual(previous.calls, 1)
    }

    func testSceneSendEvent_nestedDispatchCallsEachPreviousImplementationOnce() throws {
        let application = try actualApplication()
        let outer = UIEvent()
        let inner = UIEvent()
        let outerSpy = UIKitPreviousSpy(target: outer)
        let innerSpy = UIKitPreviousSpy(target: inner)
        try outerSpy.install()
        try innerSpy.install()
        defer { innerSpy.unswizzle(); outerSpy.unswizzle() }
        verifyPreviousCall(outerSpy, application: application, event: outer)
        verifyPreviousCall(innerSpy, application: application, event: inner)
        let handler = SceneDispatchHandler()
        var isNested = false
        handler.onIntercept = {
            if !isNested {
                isNested = true
                application.sendEvent(inner)
            }
        }
        let instrumentation = try DDSceneApplicationInstrumentation(handler: handler)
        instrumentation.install()
        defer { instrumentation.uninstall() }
        application.sendEvent(outer)
        XCTAssertEqual(handler.intercepts, 2)
        XCTAssertEqual(handler.legacyNotifications, 0)
        XCTAssertEqual(outerSpy.calls, 1)
        XCTAssertEqual(innerSpy.calls, 1)
    }
}

@available(iOS 27.0, *)
private final class SceneDispatchHandler: RUMSceneActionsHandling {
    var intercepts = 0
    var legacyNotifications = 0
    var onIntercept: (() -> Void)?
    func publish(to subscriber: RUMCommandSubscriber) {}
    func notify_viewModifierTapped(actionName: String, actionAttributes: [String: Encodable]) {}
    func notify_sendEvent(application: UIApplication, event: UIEvent) { legacyNotifications += 1 }
    func intercept(application: UIApplication, event: UIEvent, operation: () -> Void) {
        intercepts += 1
        onIntercept?()
        operation()
    }
}

private final class UIKitPreviousSpy: MethodSwizzler<
    @convention(c) (UIApplication, Selector, UIEvent) -> Void,
    @convention(block) (UIApplication, UIEvent) -> Void
> {
    private static let selector = #selector(UIApplication.sendEvent(_:))
    private let target: UIEvent
    var calls = 0
    init(target: UIEvent) { self.target = target }
    func install() throws {
        let method = try dd_class_getInstanceMethod(UIApplication.self, Self.selector)
        typealias Signature = @convention(block) (UIApplication, UIEvent) -> Void
        swizzle(method) { previous -> Signature in
            return { [weak self] application, event in
                if event === self?.target { self?.calls += 1 }
                previous(application, Self.selector, event)
            }
        }
    }
}
#endif
