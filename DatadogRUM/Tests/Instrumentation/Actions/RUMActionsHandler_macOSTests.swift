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
class RUMActionsHandlerMacOSTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let commandSubscriber = RUMCommandSubscriberMock()

    private func appKitHandler(
        appKitPredicate: AppKitRUMActionsPredicate? = DefaultAppKitRUMActionsPredicate(),
        swiftUIPredicate: SwiftUIRUMActionsPredicate? = nil,
        swiftUIDetector: SwiftUIComponentDetector? = nil
    ) -> RUMActionsHandler {
        let handler = RUMActionsHandler(
            dateProvider: dateProvider,
            appKitPredicate: appKitPredicate,
            swiftUIPredicate: swiftUIPredicate,
            swiftUIDetector: swiftUIDetector
        )
        handler.publish(to: commandSubscriber)
        return handler
    }

    // MARK: - AppKit Automatic Action Tracking

    func testGivenAppKitControlWithAccessibilityIdentifier_whenLeftMouseDown_itSendsRUMAction() throws {
        // Given
        let window = makeWindow()
        let button = NSButton(frame: .init(x: 20, y: 20, width: 100, height: 40))
        button.setAccessibilityIdentifier("Some Button")
        window.contentView?.addSubview(button)
        let handler = appKitHandler()

        // When
        handler.notify_sendEvent(event: MockNSEvent.mockWith(window: window, locationInWindow: .init(x: 30, y: 30)))

        // Then
        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.name, "NSButton (Some Button)")
        XCTAssertEqual(command.actionType, .click)
        XCTAssertEqual(command.instrumentation, .appKit)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(command.attributes.count, 0)
    }

    func testGivenAppKitControlWithNoAccessibilityIdentifier_whenLeftMouseDown_itSendsRUMAction() throws {
        // Given
        let window = makeWindow()
        let button = NSButton(frame: .init(x: 20, y: 20, width: 100, height: 40))
        window.contentView?.addSubview(button)
        let handler = appKitHandler()

        // When
        handler.notify_sendEvent(event: MockNSEvent.mockWith(window: window, locationInWindow: .init(x: 30, y: 30)))

        // Then
        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.name, "NSButton")
        XCTAssertEqual(command.actionType, .click)
        XCTAssertEqual(command.instrumentation, .appKit)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(command.attributes.count, 0)
    }

    func testGivenViewInsideAppKitControl_whenLeftMouseDown_itSendsActionForControl() throws {
        // Given
        let window = makeWindow()
        let button = NSButton(frame: .init(x: 20, y: 20, width: 100, height: 40))
        button.setAccessibilityIdentifier("Parent Button")
        let child = NSView(frame: button.bounds)
        button.addSubview(child)
        window.contentView?.addSubview(button)
        let handler = appKitHandler()

        // When
        handler.notify_sendEvent(event: MockNSEvent.mockWith(window: window, locationInWindow: .init(x: 30, y: 30)))

        // Then
        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.name, "NSButton (Parent Button)")
        XCTAssertEqual(command.actionType, .click)
        XCTAssertEqual(command.instrumentation, .appKit)
    }

    func testGivenTableViewRow_whenLeftMouseDown_itSendsActionForRow() throws {
        // Given
        let window = makeWindow()
        let tableDataSource = TableDataSource()
        let tableView = makeTableView(dataSource: tableDataSource)
        window.contentView?.addSubview(tableView.enclosingScrollView!)

        let rowView = try XCTUnwrap(tableView.rowView(atRow: 0, makeIfNecessary: true))
        rowView.setAccessibilityIdentifier("Row 0")
        let handler = appKitHandler()
        let rowCenterInWindow = tableView.convert(
            .init(x: rowView.frame.midX, y: rowView.frame.midY),
            to: nil
        )

        // When
        handler.notify_sendEvent(event: MockNSEvent.mockWith(window: window, locationInWindow: rowCenterInWindow))

        // Then
        withExtendedLifetime(tableDataSource) {
            let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
            XCTAssertEqual(command?.name, "NSTableRowView (Row 0)")
            XCTAssertEqual(command?.actionType, .click)
            XCTAssertEqual(command?.instrumentation, .appKit)
        }
    }

    func testGivenCollectionViewItem_whenLeftMouseDown_itSendsActionForItem() throws {
        // Given
        let window = makeWindow()
        let collectionDataSource = CollectionDataSource()
        let collectionView = makeCollectionView(dataSource: collectionDataSource)
        window.contentView?.addSubview(collectionView.enclosingScrollView!)

        let item = try XCTUnwrap(collectionView.item(at: .init(item: 0, section: 0)))
        item.view.setAccessibilityIdentifier("Item 0")
        let handler = appKitHandler()
        let itemCenterInWindow = collectionView.convert(
            .init(x: item.view.frame.midX, y: item.view.frame.midY),
            to: nil
        )

        // When
        handler.notify_sendEvent(event: MockNSEvent.mockWith(window: window, locationInWindow: itemCenterInWindow))

        // Then
        withExtendedLifetime(collectionDataSource) {
            let command = commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand
            XCTAssertEqual(command?.name, "NSView (Item 0)")
            XCTAssertEqual(command?.actionType, .click)
            XCTAssertEqual(command?.instrumentation, .appKit)
        }
    }

    func testGivenUnrecognizedAppKitHierarchy_whenLeftMouseDown_itGetsIgnored() {
        // Given
        let window = makeWindow()
        let container = NSView(frame: .init(x: 20, y: 20, width: 100, height: 40))
        let child = NSView(frame: container.bounds)
        container.addSubview(child)
        window.contentView?.addSubview(container)
        let handler = appKitHandler()

        // When
        handler.notify_sendEvent(event: MockNSEvent.mockWith(window: window, locationInWindow: .init(x: 30, y: 30)))

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testGivenAppKitControl_whenEventIsNotLeftMouseDown_itGetsIgnored() {
        // Given
        let window = makeWindow()
        let button = NSButton(frame: .init(x: 20, y: 20, width: 100, height: 40))
        window.contentView?.addSubview(button)
        let handler = appKitHandler()

        // When
        handler.notify_sendEvent(
            event: MockNSEvent.mockWith(window: window, type: .rightMouseDown, locationInWindow: .init(x: 30, y: 30))
        )

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testGivenAppKitEventWithNoWindow_itGetsIgnored() {
        // Given
        let handler = appKitHandler()

        // When
        handler.notify_sendEvent(event: MockNSEvent.mockWith(window: nil))

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testGivenAppKitEvent_itAppliesUserAttributesAndCustomName() throws {
        // Given
        let mockAttributes: [AttributeKey: AttributeValue] = mockRandomAttributes()
        let predicate = AppKitRUMActionsPredicateMock(
            result: RUMAction(name: "foobar", attributes: mockAttributes)
        )
        let window = makeWindow()
        window.contentView?.addSubview(NSButton(frame: .init(x: 20, y: 20, width: 100, height: 40)))
        let handler = appKitHandler(appKitPredicate: predicate)

        // When
        handler.notify_sendEvent(event: MockNSEvent.mockWith(window: window, locationInWindow: .init(x: 30, y: 30)))

        // Then
        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.name, "foobar")
        DDAssertDictionariesEqual(command.attributes, mockAttributes)
    }

    func testGivenAppKitActionPredicateReturnsNil_itDoesntSendClickAction() {
        // Given
        let window = makeWindow()
        window.contentView?.addSubview(NSButton(frame: .init(x: 20, y: 20, width: 100, height: 40)))
        let handler = appKitHandler(appKitPredicate: AppKitRUMActionsPredicateMock(result: nil))

        // When
        handler.notify_sendEvent(event: MockNSEvent.mockWith(window: window, locationInWindow: .init(x: 30, y: 30)))

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    // MARK: - AppKit Menu Action Tracking

    func testGivenMenuItemWithAccessibilityIdentifier_whenSelected_itSendsRUMAction() throws {
        // Given
        let menuItem = NSMenuItem(title: "Private title", action: nil, keyEquivalent: "")
        menuItem.setAccessibilityIdentifier("File Menu Item")
        let handler = appKitHandler()

        // When
        handler.notify_menuItemSelected(menuItem)

        // Then
        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.name, "NSMenuItem(File Menu Item)")
        XCTAssertEqual(command.actionType, .click)
        XCTAssertEqual(command.instrumentation, .appKit)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(command.attributes.count, 0)
    }

    func testGivenMenuItemWithNoAccessibilityIdentifier_whenSelected_itSendsRUMAction() throws {
        // Given
        let menuItem = NSMenuItem(title: "Private title", action: nil, keyEquivalent: "")
        let handler = appKitHandler()

        // When
        handler.notify_menuItemSelected(menuItem)

        // Then
        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.name, "NSMenuItem")
        XCTAssertEqual(command.actionType, .click)
        XCTAssertEqual(command.instrumentation, .appKit)
        XCTAssertEqual(command.time, .mockDecember15th2019At10AMUTC())
        XCTAssertEqual(command.attributes.count, 0)
    }

    func testGivenMenuItem_itAppliesUserAttributesAndCustomName() throws {
        // Given
        let mockAttributes: [AttributeKey: AttributeValue] = mockRandomAttributes()
        let predicate = AppKitRUMActionsPredicateMock(
            result: RUMAction(name: "foobar", attributes: mockAttributes)
        )
        let handler = appKitHandler(appKitPredicate: predicate)

        // When
        handler.notify_menuItemSelected(NSMenuItem())

        // Then
        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.name, "foobar")
        DDAssertDictionariesEqual(command.attributes, mockAttributes)
    }

    func testGivenAppKitActionPredicateReturnsNil_itDoesntSendMenuItemAction() {
        // Given
        let handler = appKitHandler(appKitPredicate: AppKitRUMActionsPredicateMock(result: nil))

        // When
        handler.notify_menuItemSelected(NSMenuItem())

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    // MARK: - SwiftUI Actions

    func testGivenAppKitAndSwiftUIPredicates_whenAppKitDetectsAction_itDoesNotUseSwiftUIDetector() throws {
        // Given
        let window = makeWindow()
        window.contentView?.addSubview(NSButton(frame: .init(x: 20, y: 20, width: 100, height: 40)))
        let detector = SwiftUIComponentDetectorMock(command: .mockSwiftUIAutomatic())
        let handler = appKitHandler(
            swiftUIPredicate: MockSwiftUIRUMActionsPredicate(),
            swiftUIDetector: detector
        )

        // When
        handler.notify_sendEvent(event: MockNSEvent.mockWith(window: window, locationInWindow: .init(x: 30, y: 30)))

        // Then
        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.instrumentation, .appKit)
        XCTAssertEqual(detector.receivedEvents.count, 0)
    }

    func testGivenSwiftUIPredicate_whenAppKitDoesNotDetectAction_itUsesSwiftUIDetector() throws {
        // Given
        let expectedCommand = RUMAddUserActionCommand.mockSwiftUIAutomatic()
        let detector = SwiftUIComponentDetectorMock(command: expectedCommand)
        let window = makeWindow()
        window.contentView?.addSubview(NSView(frame: .init(x: 20, y: 20, width: 100, height: 40)))
        let handler = appKitHandler(
            appKitPredicate: nil,
            swiftUIPredicate: MockSwiftUIRUMActionsPredicate(),
            swiftUIDetector: detector
        )

        // When
        let event = MockNSEvent.mockWith(window: window, locationInWindow: .init(x: 30, y: 30))
        handler.notify_sendEvent(event: event)

        // Then
        let command = try XCTUnwrap(commandSubscriber.lastReceivedCommand as? RUMAddUserActionCommand)
        XCTAssertEqual(command.name, expectedCommand.name)
        XCTAssertEqual(command.actionType, .click)
        XCTAssertEqual(command.instrumentation, .swiftuiAutomatic)
        XCTAssertEqual(detector.receivedEvents.count, 1)
        XCTAssertIdentical(detector.receivedEvents[0], event)
    }

    func testGivenNoAutomaticPredicates_whenEventOrMenuItemIsReceived_itDoesntSendAction() {
        // Given
        let handler = appKitHandler(appKitPredicate: nil, swiftUIPredicate: nil, swiftUIDetector: nil)

        // When
        handler.notify_sendEvent(event: MockNSEvent.mockWith(window: nil))
        handler.notify_menuItemSelected(NSMenuItem())

        // Then
        XCTAssertNil(commandSubscriber.lastReceivedCommand)
    }

    func testWhenSwiftUIViewModifierIsTapped_itSendsRUMAction() throws {
        // Given
        let handler = appKitHandler(appKitPredicate: nil, swiftUIPredicate: nil, swiftUIDetector: nil)

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

    // MARK: - Fixtures

    private func makeWindow() -> NSWindow {
        return NSWindow(
            contentRect: .init(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    private func makeTableView(dataSource: TableDataSource) -> NSTableView {
        let scrollView = NSScrollView(frame: .init(x: 20, y: 20, width: 200, height: 100))
        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = nil
        tableView.rowHeight = 30
        tableView.addTableColumn(NSTableColumn(identifier: .init("column")))
        tableView.dataSource = dataSource
        tableView.delegate = dataSource
        scrollView.documentView = tableView
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()
        return tableView
    }

    private func makeCollectionView(dataSource: CollectionDataSource) -> NSCollectionView {
        let scrollView = NSScrollView(frame: .init(x: 20, y: 20, width: 200, height: 100))
        let collectionView = NSCollectionView(frame: scrollView.bounds)
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = .init(width: 80, height: 40)
        collectionView.collectionViewLayout = layout
        collectionView.register(CollectionItem.self, forItemWithIdentifier: CollectionItem.identifier)
        collectionView.dataSource = dataSource
        scrollView.documentView = collectionView
        collectionView.reloadData()
        collectionView.layoutSubtreeIfNeeded()
        return collectionView
    }
}

// MARK: - Mocks

private final class MockNSEvent: NSEvent {
    private let mockType: NSEvent.EventType
    private let mockWindow: NSWindow?
    private let mockLocationInWindow: NSPoint

    static func mockWith(
        window: NSWindow?,
        type: NSEvent.EventType = .leftMouseDown,
        locationInWindow: NSPoint = .zero
    ) -> MockNSEvent {
        return MockNSEvent(type: type, window: window, locationInWindow: locationInWindow)
    }

    private init(type: NSEvent.EventType, window: NSWindow?, locationInWindow: NSPoint) {
        self.mockType = type
        self.mockWindow = window
        self.mockLocationInWindow = locationInWindow
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var type: NSEvent.EventType { mockType }
    override var window: NSWindow? { mockWindow }
    override var locationInWindow: NSPoint { mockLocationInWindow }
}

private final class SwiftUIComponentDetectorMock: SwiftUIComponentDetector {
    let command: RUMAddUserActionCommand?
    private(set) var receivedEvents: [NSEvent] = []

    init(command: RUMAddUserActionCommand?) {
        self.command = command
    }

    func createActionCommand(
        from event: NSEvent,
        predicate: SwiftUIRUMActionsPredicate?,
        dateProvider: DateProvider
    ) -> RUMAddUserActionCommand? {
        receivedEvents.append(event)
        return command
    }
}

private final class TableDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return 1
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        return NSTableCellView(frame: .init(x: 0, y: 0, width: 200, height: 30))
    }
}

private final class CollectionDataSource: NSObject, NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return 1
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        return collectionView.makeItem(withIdentifier: CollectionItem.identifier, for: indexPath)
    }
}

private final class CollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("collection-item")

    override func loadView() {
        view = NSView(frame: .init(x: 0, y: 0, width: 80, height: 40))
    }
}

private extension RUMAddUserActionCommand {
    static func mockSwiftUIAutomatic() -> RUMAddUserActionCommand {
        return RUMAddUserActionCommand(
            time: .mockDecember15th2019At10AMUTC(),
            attributes: [:],
            instrumentation: .swiftuiAutomatic,
            actionType: .click,
            name: "SwiftUI_Button"
        )
    }
}

#endif
