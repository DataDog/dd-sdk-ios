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
    /// Creates a RUM command from a `UIEvent` if applicable
    /// - Parameter event: The `UIEvent` to process
    /// - Returns: A command to add a user action, or `nil` if the event shouldn't be tracked
    func command(from event: DDEvent) -> RUMAddUserActionCommand?

    func command(from control: NSControl, action: Selector?, target: Any?) -> RUMAddUserActionCommand?
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

    func command(from event: DDEvent) -> RUMAddUserActionCommand? {
//        guard let allTouches = event.allTouches else {
//            return nil // not a touch event
//        }
//        guard allTouches.count == 1, let tap = allTouches.first else {
//            return nil // not a single touch event
//        }

        // Detect UIKit interactions first,
        // as they are more likely to happen.
        if let rumAction = createAppKitActionCommand(from: event) {
            return rumAction
        }

//        return swiftUIDetector?.createActionCommand(from: tap, predicate: swiftUIPredicate, dateProvider: dateProvider)

        return nil
    }

    func command(from control: NSControl, action: Selector?, target: Any?) -> RUMAddUserActionCommand? {
        if let rumAction = createAppKitActionCommand(from: control) {
            return rumAction
        }

        return nil
    }

    // MARK: UIKit

#if canImport(UIKit)
    private func createUIKitActionCommand(from tap: DDTouch) -> RUMAddUserActionCommand? {
        guard let uiKitPredicate else {
            return nil
        }

        guard tap.phase == .ended else {
            return nil // not in `.ended` phase
        }

        guard let view = tap.view else {
            return nil
        }

        guard view.isSafeForPrivacy else {
            return nil // no valid view
        }

        guard let targetView = bestActionTarget(for: view) else {
            return nil // Tapped view is not eligible for producing RUM Action
        }

        guard let action = uiKitPredicate.rumAction(targetView: targetView) else {
            return nil
        }
        return RUMAddUserActionCommand(
            time: dateProvider.now,
            attributes: action.attributes,
            instrumentation: .uikit,
            actionType: .tap,
            name: action.name
        )
    }
#elseif canImport(AppKit)
    private func createAppKitActionCommand(from event: NSEvent) -> RUMAddUserActionCommand? {
        guard let appKitPredicate else {
            return nil
        }

        guard event.type == .leftMouseUp, let window = event.window else {
            return nil
        }

//
//
//
//        guard view.isSafeForPrivacy else {
//            return nil // no valid view
//        }
//
//        guard let targetView = bestActionTarget(for: view) else {
//            return nil // Tapped view is not eligible for producing RUM Action
//        }

        switch event.type {
        case .leftMouseUp:
            return RUMAddUserActionCommand(
                time: dateProvider.now,
                attributes: [:],
                instrumentation: .appKit,
                actionType: .click,
                name: "Some button"
            )

        default:
            return nil
        }
    }

    private func createAppKitActionCommand(from control: NSControl) -> RUMAddUserActionCommand? {
        guard let appKitPredicate else {
            return nil
        }

        guard let action = appKitPredicate.rumAction(targetView: control) else {
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
#endif

    /// Traverses the hierarchy of the `view` bottom-up to find the best view which could be considered for RUM Action's target,
    /// e.g. if the tapped `view` is a `UILabel` embedded in a `UIStackView` inside the `UITableViewCell` it will
    /// return the `UITableViewCell` as the best guess of user interaction.
    ///
    /// May return `nil` if there's no good guess and the RUM Action for given `view` should not be produced.
    private func bestActionTarget(for view: DDView) -> DDView? {
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

