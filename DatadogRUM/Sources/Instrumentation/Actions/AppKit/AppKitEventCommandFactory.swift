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
    typealias AccessibilityHierarchyDetectorCreator = () -> AccessibilityHierarchyDetector

    let dateProvider: DateProvider
    let macOSPredicate: MacOSRUMActionsPredicate
    let accessibilityHierarchyDetectorCreator: AccessibilityHierarchyDetectorCreator
    private(set) lazy var accessibilityHierarchyDetector = accessibilityHierarchyDetectorCreator()

    init(
        dateProvider: DateProvider,
        macOSPredicate: MacOSRUMActionsPredicate,
        accessibilityHierarchyDetectorCreator: @escaping AccessibilityHierarchyDetectorCreator
    ) {
        self.dateProvider = dateProvider
        self.macOSPredicate = macOSPredicate
        self.accessibilityHierarchyDetectorCreator = accessibilityHierarchyDetectorCreator
    }

    func command(from event: NSEvent) -> RUMAddUserActionCommand? {
        guard event.type == .leftMouseDown else {
            return nil // Handle mouse down only for now
        }

        switch createAppKitActionCommand(from: event) {
        case .command(let command): return command
        case .ignore: return nil
        case .tryAccessibility:
            // In some situations (see the documentation of`createAppKitActionCommand(from:)`),
            // `createAppKitActionCommand` will use the accessibility detector to obtain an action,
            // if possible.
            //
            // Here, the detector covers situations not handled by `createAppKitActionCommand`.
            // These are situations where a SwiftUI interactive view (like a button) is on a window,
            // either in a fully native SwiftUI window, or a NSHostingView in an AppKit window,
            // but not inside an AppKit container (like a NSTableRowView or NSCollectionView) that
            // would otherwise be detected by `createAppKitActionCommand`.
            switch accessibilityHierarchyDetector.createActionCommand(from: event, predicate: macOSPredicate, dateProvider: dateProvider) {
            case .command(let command): return command
            case .ignore, .noDecision:  return nil
            }
        }
    }

    func command(from menuItem: NSMenuItem) -> RUMAddUserActionCommand? {
        if let rumAction = createAppKitActionCommand(from: menuItem) {
            return rumAction
        }

        return nil
    }

    // MARK: AppKit

    /// Result from `bestActionTargetFor(view:event:)` function.
    private enum BestTarget {
        /// The best target is a possible view in the AppKit domain.
        ///
        /// If the associated optional has a value, it means this is the view that should be used as the target
        /// of the event. If `nil`, it means the function determined this cannot be a SwiftUI view, and the
        /// event happened at a location where there is no interactive element throughout the entire hierarchy.
        case appKit(NSView?)

        /// The best target is a SwiftUI view inside an AppView container, and the accessibility detector should
        /// be called to try to obtain a RUM action out of the SwiftUI view hierarchy.
        ///
        /// If no action is obtained from the accessibility detector, then the view in the associated value, if any,
        /// should be used as the best target. This happens in situations where the clicked SwiftUI view is
        /// inside a traditional AppKit container like an `NSTableView` or `NSCollectionView` (but
        /// **not** a view whose single purpose is to host SwiftUI views, like `NSHostingView`). Usually
        /// the associated view is the container or one of its subviews, like `NSTableRowView`.
        ///
        /// If the associated view is `nil`, it usually means the container is not an interactive element. In
        /// this case, the code should follow the same path as the `.appKit` case.
        case tryAccessibilityHierarchyWithFallbackTo(NSView?)

        /// Obtains the view from either case above.
        ///
        /// If not `nil`, this is the best target to use if either the target is `.appKit` or if the SwiftUI
        /// Detector failed to create an action. If `nil`, there is no suitable view in the AppKit hierarchy
        /// we are interested in.
        var view: NSView? {
            switch self {
            case .appKit(let view), .tryAccessibilityHierarchyWithFallbackTo(let view): view
            }
        }
    }

    private enum AppKitCommandResult {
        case command(RUMAddUserActionCommand)
        case tryAccessibility
        case ignore
    }

    /// Creates a RUM Action command if appropriate based on the given `NSEvent`.
    ///
    /// - Parameters:
    ///   - event: The `NSEvent` being processed. Only `.leftMouseDown` events are supported for now.
    /// - Returns: A `RUMAddUserActionCommand` if all the conditions for a RUM Action command creation
    /// are met, `nil` otherwise.
    private func createAppKitActionCommand(from event: NSEvent) -> AppKitCommandResult {
        // Run hitTesting on the root view to include toolbar buttons and chrome.
        guard let clickedView = event.window?.rootView?.hitTest(event.locationInWindow) else {
            return .tryAccessibility // We don't know what was clicked
        }

        // If it's not safe for privacy, bail out immediately.
        guard clickedView.isSafeForPrivacy else {
            return .ignore // no valid view
        }

        let bestTarget = bestActionTargetFor(view: clickedView, event: event)

        // If the best target is determined to be a possible SwiftUI view, `accessibilityHierarchyDetector`
        // is called to obtain an action from the SwiftUI hierarchy.
        //
        // The reason it's important to do it here instead of falling back to the
        // `accessibilityHierarchyDetector.createActionCommand(…)` call in `AppKitCommandFactory.command(from:)`
        // is we may have a fallback container view, present in the `.tryAccessibilityHierarchyWithFallbackTo`
        // associated value. This happens in situations like a SwiftUI Table that, on macOS, is implemented
        // by a NSTableView, with SwiftUI views inside cells. If there is no interesting SwiftUI
        // view to be used as target, we fallback to the container view. If we just returned `nil`
        // and relied on `accessibilityHierarchyDetector.createActionCommand(…)`, the container view
        // context would be lost and no action would be returned.
        if case .tryAccessibilityHierarchyWithFallbackTo(let fallback) = bestTarget {
            switch accessibilityHierarchyDetector.createActionCommand(from: event, predicate: macOSPredicate, dateProvider: dateProvider) {
            case .command(let command):
                return .command(command)
            case .ignore:
                return .ignore
            case .noDecision:
                if fallback == nil {
                    // If bestTarget result was to try SwiftUI without any fallback view,
                    // if the accessibilityHierarchyDetector fails to generate an action
                    // here we know it's not going to generate one in command(from:). So
                    // we avoid the second call there by returning .ignore.
                    return .ignore
                }
            }
        }

        guard let targetView = bestTarget.view else {
            return .tryAccessibility
        }

        guard let action = macOSPredicate.rumAction(targetView: targetView) else {
            return .ignore
        }

        return
            .command(
                RUMAddUserActionCommand(
                time: dateProvider.now,
                attributes: action.attributes,
                instrumentation: .appKit,
                actionType: .click,
                name: action.name
            )
        )
    }

    /// Creates a RUM Action command if appropriate based on the given `NSMenuItem`.
    ///
    /// - Parameters:
    ///   - event: The `NSMenuItem` being processed.
    /// - Returns: A `RUMAddUserActionCommand` if all the conditions for a RUM Action command creation
    /// are met, `nil` otherwise.
    private func createAppKitActionCommand(from menuItem: NSMenuItem) -> RUMAddUserActionCommand? {
        guard menuItem.isSafeForPrivacy else {
            return nil // no valid menu item
        }

        guard let action = macOSPredicate.rumAction(targetMenuItem: menuItem) else {
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
    /// If the control is a `NSTableView`, this method obtains the row the user clicked in, if any. Otherwise, the `NSTableView`
    /// itself is returned. See the documentation of `tableRowIn(tableView:windowCoordinates:)` for details.
    ///
    /// - Parameter control: The target control of the event being processed.
    /// - Returns: The best target for the event, as described above.
    private func bestActionTargetFor(control: NSControl, event: NSEvent) -> NSView? {
        // Ignore disabled controls.
        guard control.isEnabled else {
            return nil
        }

        if let toolbarItemViewer = control.findInParentHierarchy(viewMatching: { $0.className == "NSToolbarItemViewer" }) {
            return toolbarItemViewer
        }

        if let tableView = control as? NSTableView {
            return tableRowIn(tableView: tableView, windowCoordinates: event.locationInWindow)
        }

        return control
    }

    /// Based on the given view, obtain the most appropriate view to be used as the target of a RUM event, if any.
    ///
    /// Read the inline comments to understand how this function works.
    ///
    /// - parameters:
    ///   - view: The target view of `event`.
    ///   - event: The `NSEvent` being processed.
    ///
    /// - Returns: As instance of `BestTarget` indicating if this is a pure AppKit view or if the accessibility detector should
    /// try to obtain the target view. If AppKit, also provides the target view, if any. For SwiftUI, it provides the fallback target view
    /// to be used if the accessibility detector fails to generate a RUM action.
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
            // NSTableView interactive element is the row, not the cell. If the click hits a row,
            // outside of a specific control present in a table cell, it's caught here, as a click
            // on the NSTableView itself (NSTableView extends NSControl). The bestActionTargetFor(control:event:)
            // method digs in to find the clicked row.
            return .appKit(bestActionTargetFor(control: ddControl, event: event))
        } else {
            // If the `view` is not an interactive element, check if it's a child of a known view
            // hierarchy which can be considered as interactive.
            //
            // First, check if the target is actually a SwiftUI container. This happens in
            // situations like a SwiftUI Table, that, in macOS, is implemented by a NSTableView
            // with possible SwiftUI views inside the cells.
            let classNameFirstElement = String(describing: type(of: view)).prefix { char in
                char.isLetter || char.isNumber
            }
            let isSwiftUIContainerView = Self.swiftUIContainerViewPrefixes.contains(classNameFirstElement)

            var result: NSView?

            // Second, look up the hierarchy for the first interactive element.
            // Note NSTableView and NSTableRowView extend NSControl so there is no need to test
            // for those specifically.
            //
            // In case `isSwiftUIContainerView` is true, this (plus the processing below) will
            // be just the fallback view if the accessibility detector cannot create an action.
            let bestParent = view.findInParentHierarchy { parent in
                return parent is NSControl
                    || parent is NSCollectionView
            }

            if let collectionView = bestParent as? NSCollectionView {
                // If the user clicked on a collection view outside of a control in a collection
                // view item, look for the collection view item the user clicked on. If the click
                // was outside of any item, return the collection view itself.
                result = collectionViewItemView(collectionView: collectionView, windowCoordinates: event.locationInWindow)
            } else if let control = bestParent as? NSControl {
                // If the view is inside a control, process that control.
                // As stated above, this includes NSTableView and NSTableRowView.
                result = bestActionTargetFor(control: control, event: event)
            } else {
                result = bestParent
            }

            return isSwiftUIContainerView ? .tryAccessibilityHierarchyWithFallbackTo(result) : .appKit(result)
        }
    }

    /// Names of private views that act as SwiftUI containers.
    private static let swiftUIContainerViewPrefixes: Set<Substring> = [
        "CellHostingView",
        "TableCellHostingView",
        "PlatformGroupContainer"
    ]

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
