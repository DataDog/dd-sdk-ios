/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import DatadogInternal
import os.log

/// Factory responsible for creating RUM Action commands events that are target of `.leftMouseDown` `NSEvent`s,
/// and selected `NSMenuItem`s.
internal protocol AppKitEventCommandFactory {
    /// Creates a RUM command from a `NSEvent` with type of `leftMouseDown` if applicable.
    ///
    /// - Parameter event: The `NSEvent` to process.
    /// - Returns: A command to add a user action, or `nil` if the event shouldn't be tracked.
    func command(from event: NSEvent) -> RUMAddUserActionCommand?

    /// Creates a RUM command from a menu item selected by the user.
    ///
    /// - Parameter menuItem: The `NSMenuItem` to process.
    /// - Returns: A command to add a user action, or `nil` if the event shouldn't be tracked.
    func command(from menuItem: NSMenuItem) -> RUMAddUserActionCommand?
}

// MARK: macOS implementation
/// macOS-specific implementation that detects user interactions through touches.
/// Handles both AppKit and SwiftUI components using different detection strategies.
internal final class AppKitCommandFactory: AppKitEventCommandFactory {
    let dateProvider: DateProvider
    let appKitPredicate: AppKitRUMActionsPredicate?
    let swiftUIPredicate: SwiftUIRUMActionsPredicate?
    let swiftUIDetector: SwiftUIComponentDetector?

    init(
        dateProvider: DateProvider,
        appKitPredicate: AppKitRUMActionsPredicate?,
        swiftUIPredicate: SwiftUIRUMActionsPredicate?,
        swiftUIDetector: SwiftUIComponentDetector?
    ) {
        self.dateProvider = dateProvider
        self.appKitPredicate = appKitPredicate
        self.swiftUIPredicate = swiftUIPredicate
        self.swiftUIDetector = swiftUIDetector
    }

    func command(from event: NSEvent) -> RUMAddUserActionCommand? {
        if let rumAction = createAppKitActionCommand(from: event) {
            return rumAction
        }

        return swiftUIDetector?.createActionCommand(from: event, predicate: swiftUIPredicate, dateProvider: dateProvider)
    }

    func command(from menuItem: NSMenuItem) -> RUMAddUserActionCommand? {
        if let rumAction = createAppKitActionCommand(from: menuItem) {
            return rumAction
        }

        return nil
    }

    // MARK: AppKit

    enum BestTarget {
        case appKit(NSView?)
        case trySwiftUIFallbackTo(NSView?)

        var view: NSView? {
            switch self {
            case .appKit(let view), .trySwiftUIFallbackTo(let view): view
            }
        }
    }

    /// Creates a RUM Action command if appropriate based on the given `NSEvent`.
    ///
    /// - Parameters:
    ///   - event: The `NSEvent` being processed. Only `.leftMouseDown` events are supported for now.
    /// - Returns: A `RUMAddUserActionCommand` if all the conditions for a RUM Action command creation
    /// are met, `nil` otherwise.
    private func createAppKitActionCommand(from event: NSEvent) -> RUMAddUserActionCommand? {
        guard let appKitPredicate else {
            return nil
        }

        guard event.type == .leftMouseDown else {
            return nil // Handle mouse down only for now
        }

        // Run hitTesting on the root view to include toolbar buttons and chrome.
        guard let clickedView = event.window?.rootView?.hitTest(event.locationInWindow) else {
            return nil // We don't know what was clicked
        }

        // If it's not safe for privacy, bail out immediately.
        guard clickedView.isSafeForPrivacy else {
            return nil // no valid view
        }

        let bestTarget = bestActionTargetFor(view: clickedView, event: event)

        if case let .trySwiftUIFallbackTo(view) = bestTarget,
           let swiftUIResult = swiftUIDetector?.createActionCommand(from: event, predicate: swiftUIPredicate, dateProvider: dateProvider)
            {
            return swiftUIResult
        }

        guard let targetView = bestTarget.view else {
            return nil // Clicked view is not eligible for producing RUM Action
        }

        guard let action = appKitPredicate.rumAction(targetView: targetView) else {
            return nil
        }

        return RUMAddUserActionCommand(
            time: dateProvider.now,
            attributes: action.attributes,
            instrumentation: .appKit,
            actionType: .click,
            name: action.name
        )
    }

    /// Creates a RUM Action command if appropriate based on the given `NSMenuItem`.
    ///
    /// - Parameters:
    ///   - event: The `NSMenuItem` being processed.
    /// - Returns: A `RUMAddUserActionCommand` if all the conditions for a RUM Action command creation
    /// are met, `nil` otherwise.
    private func createAppKitActionCommand(from menuItem: NSMenuItem) -> RUMAddUserActionCommand? {
        guard let appKitPredicate else {
            return nil
        }

        guard menuItem.isSafeForPrivacy else {
            return nil // no valid menu item
        }

        guard let action = appKitPredicate.rumAction(targetMenuItem: menuItem) else {
            return nil
        }

        return RUMAddUserActionCommand(
            time: dateProvider.now,
            attributes: action.attributes,
            instrumentation: .appKit,
            actionType: .click,
            name: action.name
        )
    }

    /// Find the best action target for a given `NSControl`.
    ///
    /// If the control is a button inside a toolbar item, this function returns the ancestor `NSToolbarItemViewer` view instead.
    /// Depending on how toolbars are built, the event target may be `NSToolbarItemViewer` itself or a button inside it. Changing
    /// it always to the `NSToolbarItemViewer` provides better instrumenting, making it clear this was a click on a toolbar item.
    ///
    /// - Parameter control: The target control of the event being processed.
    /// - Returns: The best target for the event, as described above.
    private func bestActionTargetFor(control: NSControl, event: NSEvent) -> NSView {
        if let toolbarItemViewer = control.findInParentHierarchy(viewMatching: { $0.className == "NSToolbarItemViewer" }) {
            return toolbarItemViewer
        }

        if let tableView = control as? NSTableView {
            return tableRowIn(tableView: tableView, windowCoordinates: event.locationInWindow)
        }

        return control
    }

    /// Traverses the hierarchy of the `view` bottom-up to find the best view which could be considered for RUM Action's target.
    ///
    /// May return `nil` if there's no good guess and the RUM Action for given `view` should not be produced.
    ///
    /// - parameters:
    ///   - view: The target view of `event`.
    ///   - event: The `NSEvent` being processed.
    ///
    /// - Returns: The best target for the event being processed, or `nil` if no suitable view is found.
    private func bestActionTargetFor(view: DDView, event: NSEvent) -> BestTarget {
        // In toolbars, if no button was explicitly attributed to item.view, the
        // class that returns itself from hitTest is NSToolbarItemViewer, not the
        // synthesized button inside it (NSToolbarButton instance).
        if view.className == "NSToolbarItemViewer"
            // In tables, a click on a header hits a view (not control) of class NSTableHeaderView.
            // We avoid the path of finding the NSTableView parent and then digging in to look for
            // the clicked header view since we already know it, so we shortcut it here.
            || view is NSTableHeaderView {
            return .appKit(view)
        } else if let ddControl = view as? DDControl {
            return .appKit(bestActionTargetFor(control: ddControl, event: event))
        } else {
            let classNameFirstElement = String(describing: type(of: view)).prefix { char in
                char.isLetter || char.isNumber
            }
            let isSwiftUICellView = Self.swiftUIContainerViewPrefixes.contains(classNameFirstElement)

            var result: NSView?

            // If the `view` is not an interactive element, check if it's a child of a known view hierarchy
            // which can be considered as interactive.
            let bestParent = view.findInParentHierarchy { parent in
                return parent is NSControl
                    || parent is NSCollectionView
            }

            if let collectionView = bestParent as? NSCollectionView {
                result = collectionViewItemView(collectionView: collectionView, windowCoordinates: event.locationInWindow)
            } else if let control = bestParent as? NSControl {
                result = bestActionTargetFor(control: control, event: event)
            } else {
                result = bestParent
            }

            return isSwiftUICellView ? .trySwiftUIFallbackTo(result) : .appKit(result)
        }
    }

    private static let swiftUIContainerViewPrefixes: Set<Substring> = [
        "CellHostingView",
        "TableCellHostingView",
        "PlatformGroupContainer"
    ]

    private func bestActionTargetFor(accessibilityElement: AnyObject, event: NSEvent) -> AnyObject? {
        guard let role = accessibilityElement.accessibilityRole() else {
            return nil
        }

        let roleString = "\(role)"

        Logger().error("\(roleString, privacy: .public)")
        return nil
    }

    /// Finds the table row the user clicked on, and returns the corresponding `NSTableRowView`.
    ///
    /// On macOS, `NSTableView` does not select individual cells, but rows, so we consider the row to be
    /// the interactive element.
    ///
    /// - Parameters:
    ///   - tableView: The clicked table view.
    ///   - windowCoordinates: The event window coordinates, obtained from `event.locationInWindow`.
    ///
    /// - Returns: If the user clicked on an existing row, the corresponding `NSTableRow` is returned. Otherwise,
    /// `tableView` itself is returned. This may happen if the user clicked on empty space in a table (the visible area
    /// is larger than all existing rows) or any other view inside a table.
    ///
    /// - Note: If the user clicks on a header view, this is handled directly in `bestActionTargetFor(view:event:)`
    /// and this method is not invoked.
    private func tableRowIn(tableView: NSTableView, windowCoordinates: NSPoint) -> NSView {
        let coordinates = tableView.convert(windowCoordinates, from: nil)
        let row = tableView.row(at: coordinates)

        guard row >= 0 else {
            // The coordinate did not hit any cell view, so return the table itself.
            return tableView
        }

        return tableView.rowView(atRow: row, makeIfNecessary: false) ?? tableView
    }

    /// Finds and returns the view of the collection view item the user clicked on.
    ///
    /// - Parameters:
    ///   - collectionView: The clicked table view.
    ///   - windowCoordinates: The event window coordinates, obtained from `event.locationInWindow`.
    ///
    /// - Returns: If the user clicked on an existing collection view item view, that view is returned. Otherwise, if the
    /// user clicked on the empty space between item views, the collection view itself is returned.
    private func collectionViewItemView(collectionView: NSCollectionView, windowCoordinates: NSPoint) -> NSView {
        let coordinates = collectionView.convert(windowCoordinates, from: nil)
        let itemView = collectionView.indexPathForItem(at: coordinates).flatMap {
            collectionView.item(at: $0)
        }?.view
        return itemView ?? collectionView
    }
}
#endif
