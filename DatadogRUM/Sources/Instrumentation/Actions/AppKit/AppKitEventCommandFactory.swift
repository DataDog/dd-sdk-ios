/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import AppKit
import DatadogInternal

/// Factory responsible for creating RUM user action commands from UIEvents.
/// This abstraction allows for platform-specific implementations (iOS/tvOS).
internal protocol AppKitEventCommandFactory {
    func command(from app: NSApplication, action: Selector?, target: Any?, from: Any?) -> RUMAddUserActionCommand?
    func command(from event: NSEvent) -> RUMAddUserActionCommand?
}

// MARK: macOS implementation
/// macOS-specific implementation that detects user interactions through touches.
/// Handles both UIKit and SwiftUI components using different detection strategies.
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

    func command(from app: NSApplication, action: Selector?, target: Any?, from: Any?) -> RUMAddUserActionCommand? {

        if let view = from as? NSView, let rumAction = createAppKitActionCommand(from: view) {
            return rumAction
        }

        if let menuItem = from as? NSMenuItem,  let rumAction = createAppKitActionCommand(from: menuItem) {
            return rumAction
        }

        return nil
    }

    func command(from event: NSEvent) -> RUMAddUserActionCommand? {
        if let rumAction = createAppKitActionCommand(from: event) {
            return rumAction
        }

        return nil
    }

    // MARK: UIKit
    private func createAppKitActionCommand(from event: NSEvent) -> RUMAddUserActionCommand? {
        guard let appKitPredicate else {
            return nil
        }

        guard event.type == .leftMouseDown else {
            return nil // Handle mouse down only for now
        }

        guard let clickedView = event.window?.contentView?.hitTest(event.locationInWindow) else {
            return nil // We don't know what was clicked
        }

        return createAppKitActionCommand(from: clickedView)
    }

    private func createAppKitActionCommand(from view: NSView) -> RUMAddUserActionCommand? {
        guard let appKitPredicate else {
            return nil
        }

        guard view.isSafeForPrivacy else {
            return nil // no valid view
        }

        guard let targetView = bestActionTargetFor(view: view) else {
            return nil // Tapped view is not eligible for producing RUM Action
        }

        guard let action = appKitPredicate.rumAction(targetView: view) else {
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

    private func createAppKitActionCommand(from menuItem: NSMenuItem) -> RUMAddUserActionCommand? {
        guard let appKitPredicate else {
            return nil
        }

        // TODO: How to check this?
//        guard menuItem.isSafeForPrivacy else {
//            return nil // no valid view
//        }

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

    private func bestActionTargetFor(control: NSControl) -> NSView? {
        if let toolbarItemViewer = control.findInParentHierarchy(viewMatching: { $0.className == "NSToolbarItemViewer" }) {
            return toolbarItemViewer
        }

        return control
    }

    /// Traverses the hierarchy of the `view` bottom-up to find the best view which could be considered for RUM Action's target,
    /// e.g. if the tapped `view` is a `UILabel` embedded in a `UIStackView` inside the `UITableViewCell` it will
    /// return the `UITableViewCell` as the best guess of user interaction.
    ///
    /// May return `nil` if there's no good guess and the RUM Action for given `view` should not be produced.
    private func bestActionTargetFor(view: DDView) -> DDView? {
        if let ddControl = view as? DDControl {
            // If the `view` is a `DDControl` (interactive element), accept it.
            return ddControl
        } else {
            // If the `view` is not an interactive element, check if it's a child of a known view hierarchy
            // which can be considered as interactive.
            // For now this includes checking if the interacted view is an (in-)direct child of the `DDTableViewCell`
            // or `DDCollectionViewCell`, which is a common pattern when building list-based navigation on iOS.
            let bestParent = view.findInParentHierarchy { parent in
                return parent is DDTableViewCell
                || parent is DDCollectionViewCell
                || parent is DDControl
                || parent.isUIAlertActionView
                || parent.isUIAlertTextField
            }
            return bestParent // best parent or `nil`
        }
    }
}

