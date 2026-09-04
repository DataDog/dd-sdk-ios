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
final class RUMActionsHandlerToolbarMacOSTests: XCTestCase, NSToolbarDelegate, NSToolbarItemValidation {
    private enum Scenario: String, CaseIterable {
        case explicitButtonWithNoAccessibilityIdentifiers
        case explicitButtonWithItemAccessibilityIdentifier
        case explicitButtonWithButtonAccessibilityIdentifier
        case explicitButtonWithBothAccessibilityIdentifiers
        case implicitButtonWithNoAccessibilityIdentifier
        case implicitButtonWithItemAccessibilityIdentifier

        var itemIdentifier: NSToolbarItem.Identifier {
            return .init(rawValue)
        }

        var usesExplicitButton: Bool {
            switch self {
            case .explicitButtonWithNoAccessibilityIdentifiers,
                 .explicitButtonWithItemAccessibilityIdentifier,
                 .explicitButtonWithButtonAccessibilityIdentifier,
                 .explicitButtonWithBothAccessibilityIdentifiers:
                return true
            case .implicitButtonWithNoAccessibilityIdentifier,
                 .implicitButtonWithItemAccessibilityIdentifier:
                return false
            }
        }

        var itemAccessibilityIdentifier: String? {
            switch self {
            case .explicitButtonWithItemAccessibilityIdentifier,
                 .explicitButtonWithBothAccessibilityIdentifiers,
                 .implicitButtonWithItemAccessibilityIdentifier:
                return "Item Identifier"
            case .explicitButtonWithNoAccessibilityIdentifiers,
                 .explicitButtonWithButtonAccessibilityIdentifier,
                 .implicitButtonWithNoAccessibilityIdentifier:
                return nil
            }
        }

        var buttonAccessibilityIdentifier: String? {
            switch self {
            case .explicitButtonWithButtonAccessibilityIdentifier,
                 .explicitButtonWithBothAccessibilityIdentifiers:
                return "Button Identifier"
            case .explicitButtonWithNoAccessibilityIdentifiers,
                 .explicitButtonWithItemAccessibilityIdentifier,
                 .implicitButtonWithNoAccessibilityIdentifier,
                 .implicitButtonWithItemAccessibilityIdentifier:
                return nil
            }
        }
    }

    private struct ToolbarItemHandle {
        let itemViewer: NSView
        let control: NSControl
    }

    private struct ToolbarFixture {
        let window: NSWindow
        let toolbar: NSToolbar
        let itemHandles: [Scenario: ToolbarItemHandle]
    }

    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()
    private var toolbarItems: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private var enabledItemIdentifiers: Set<NSToolbarItem.Identifier> = []

    func testGivenExplicitButtonWithNoAccessibilityIdentifiers_whenClicked_itUsesItemViewer() throws {
        try assertToolbarItem(
            .explicitButtonWithNoAccessibilityIdentifiers,
            hasActionNamed: "NSToolbarItemViewer"
        )
    }

    func testGivenExplicitButtonWithItemAccessibilityIdentifier_whenClicked_itUsesItemViewer() throws {
        try assertToolbarItem(
            .explicitButtonWithItemAccessibilityIdentifier,
            hasActionNamed: "NSToolbarItemViewer (Item Identifier)"
        )
    }

    func testGivenExplicitButtonWithButtonAccessibilityIdentifier_whenClicked_itUsesButton() throws {
        try assertToolbarItem(
            .explicitButtonWithButtonAccessibilityIdentifier,
            hasActionNamed: "NSButton (Button Identifier)"
        )
    }

    func testGivenExplicitButtonWithBothAccessibilityIdentifiers_whenClicked_itUsesItemViewer() throws {
        try assertToolbarItem(
            .explicitButtonWithBothAccessibilityIdentifiers,
            hasActionNamed: "NSToolbarItemViewer (Item Identifier)"
        )
    }

    func testGivenImplicitButtonWithNoAccessibilityIdentifier_whenClicked_itUsesItemViewer() throws {
        try assertToolbarItem(
            .implicitButtonWithNoAccessibilityIdentifier,
            hasActionNamed: "NSToolbarItemViewer"
        )
    }

    func testGivenImplicitButtonWithItemAccessibilityIdentifier_whenClicked_itUsesItemViewer() throws {
        try assertToolbarItem(
            .implicitButtonWithItemAccessibilityIdentifier,
            hasActionNamed: "NSToolbarItemViewer (Item Identifier)"
        )
    }

    private func assertToolbarItem(_ scenario: Scenario, hasActionNamed expectedName: String) throws {
        // Given
        let fixture = try makeToolbarFixture()
        let itemHandle = try XCTUnwrap(fixture.itemHandles[scenario])
        let handler = appKitHandler()

        // When
        click(itemHandle.itemViewer, in: fixture.window, using: handler)

        // Then
        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.name, expectedName)
        XCTAssertEqual(command.actionType, .click)
        XCTAssertEqual(command.instrumentation, .appKit)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(command.attributes.count, 0)

        // When
        enabledItemIdentifiers.remove(scenario.itemIdentifier)
        fixture.toolbar.validateVisibleItems()
        XCTAssertFalse(itemHandle.control.isEnabled)

        let receivedCommandCount = commandSubscriber.receivedCommands.count
        click(itemHandle.itemViewer, in: fixture.window, using: handler)

        // Then
        XCTAssertEqual(commandSubscriber.receivedCommands.count, receivedCommandCount)
    }

    private func makeToolbarFixture() throws -> ToolbarFixture {
        toolbarItems.removeAll()
        enabledItemIdentifiers = Set(Scenario.allCases.map(\.itemIdentifier))

        var explicitButtons: [Scenario: NSButton] = [:]

        for (index, scenario) in Scenario.allCases.enumerated() {
            let item = ValidatingToolbarItem(itemIdentifier: scenario.itemIdentifier)
            item.label = "Item \(index)"
            item.paletteLabel = "Item \(index)"

            if scenario.usesExplicitButton {
                let button = NSButton(title: "Button \(index)", target: nil, action: nil)
                item.view = button
                explicitButtons[scenario] = button
            } else {
                item.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
            }

            item.target = self
            item.action = #selector(toolbarItemSelected(_:))
            toolbarItems[item.itemIdentifier] = item
        }

        let toolbar = NSToolbar(identifier: .init("RUMActionsHandlerToolbarMacOSTests"))
        toolbar.delegate = self

        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 1_600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.toolbar = toolbar
        window.contentView?.superview?.layoutSubtreeIfNeeded()

        let rootView = try XCTUnwrap(window.rootView)
        let itemViewers = allSubviews(in: rootView)
            .filter(\.isNSToolbarItemViewer)
            .sorted { lhs, rhs in
                lhs.convert(lhs.bounds, to: nil).minX < rhs.convert(rhs.bounds, to: nil).minX
            }

        XCTAssertEqual(itemViewers.count, Scenario.allCases.count)
        let itemViewersByScenario = Dictionary(uniqueKeysWithValues: zip(Scenario.allCases, itemViewers))
        var itemHandles: [Scenario: ToolbarItemHandle] = [:]

        for scenario in Scenario.allCases {
            let itemViewer = try XCTUnwrap(itemViewersByScenario[scenario])
            let control = try XCTUnwrap(itemViewer.subviews.lazy.compactMap { $0 as? NSControl }.first)

            explicitButtons[scenario]?.setAccessibilityIdentifier(scenario.buttonAccessibilityIdentifier)

            // AppKit initially mirrors a custom button's identifier onto its item viewer. Set the viewer last so
            // the fixture can represent the item-only, button-only, both, and neither combinations independently.
            itemViewer.setAccessibilityIdentifier(scenario.itemAccessibilityIdentifier)
            itemHandles[scenario] = ToolbarItemHandle(itemViewer: itemViewer, control: control)
        }

        toolbar.validateVisibleItems()
        return ToolbarFixture(window: window, toolbar: toolbar, itemHandles: itemHandles)
    }

    private func appKitHandler() -> RUMActionsHandler {
        let eventCommandsFactory = AppKitCommandFactory(
            dateProvider: dateProvider,
            macOSPredicate: DefaultMacOSRUMActionsPredicate(),
            accessibilityHierarchyDetectorCreator: { NoDecisionAccessibilityHierarchyDetector() }
        )
        let handler = RUMActionsHandler(
            dateProvider: dateProvider,
            eventCommandsFactory: eventCommandsFactory
        )
        handler.publish(to: commandSubscriber)
        return handler
    }

    private func click(_ view: NSView, in window: NSWindow, using handler: RUMActionsHandler) {
        let locationInWindow = view.convert(
            .init(x: view.bounds.midX, y: view.bounds.midY),
            to: nil
        )
        handler.notify_sendEvent(
            event: ToolbarMockNSEvent(
                window: window,
                locationInWindow: locationInWindow
            )
        )
    }

    private func allSubviews(in view: NSView) -> [NSView] {
        return view.subviews.flatMap { subview in
            [subview] + allSubviews(in: subview)
        }
    }

    @objc
    private func toolbarItemSelected(_ sender: Any?) {}

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return Scenario.allCases.map(\.itemIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return Scenario.allCases.map(\.itemIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        return toolbarItems[itemIdentifier]
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        return enabledItemIdentifiers.contains(item.itemIdentifier)
    }
}

private final class ValidatingToolbarItem: NSToolbarItem {
    override func validate() {
        guard let validator = target as? NSToolbarItemValidation else {
            super.validate()
            return
        }

        isEnabled = validator.validateToolbarItem(self)
    }
}

private final class ToolbarMockNSEvent: NSEvent {
    private let mockWindow: NSWindow?
    private let mockLocationInWindow: NSPoint

    init(window: NSWindow?, locationInWindow: NSPoint) {
        self.mockWindow = window
        self.mockLocationInWindow = locationInWindow
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var type: NSEvent.EventType { .leftMouseDown }
    override var window: NSWindow? { mockWindow }
    override var locationInWindow: NSPoint { mockLocationInWindow }
}

private final class NoDecisionAccessibilityHierarchyDetector: AccessibilityHierarchyDetector {
    func createActionCommand(
        from event: NSEvent,
        predicate: MacOSRUMActionsPredicate?,
        dateProvider: DateProvider
    ) -> AccessibilityCommandResult {
        return .noDecision
    }
}

#endif
