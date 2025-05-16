/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal

/// Factory responsible for creating RUM user action commands from UIEvents.
/// This abstraction allows for platform-specific implementations (iOS/tvOS).
internal protocol UIEventCommandFactory {
    /// Creates a RUM command from a `UIEvent` if applicable
    /// - Parameter event: The `UIEvent` to process
    /// - Returns: A command to add a user action, or `nil` if the event shouldn't be tracked
    func command(from event: UIEvent) -> RUMAddUserActionCommand?
}

// MARK: iOS implementation
/// iOS-specific implementation that detects user interactions through touches.
/// Handles both UIKit and SwiftUI components using different detection strategies.
internal final class UITouchCommandFactory: UIEventCommandFactory {
    let dateProvider: DateProvider
    let uiKitPredicate: UITouchRUMActionsPredicate?
    let swiftUIPredicate: SwiftUIRUMActionsPredicate?
    let swiftUIDetector: SwiftUIComponentDetector?

    init(
        dateProvider: DateProvider,
        uiKitPredicate: UITouchRUMActionsPredicate?,
        swiftUIPredicate: SwiftUIRUMActionsPredicate?,
        swiftUIDetector: SwiftUIComponentDetector?
    ) {
        self.dateProvider = dateProvider
        self.uiKitPredicate = uiKitPredicate
        self.swiftUIPredicate = swiftUIPredicate
        self.swiftUIDetector = swiftUIDetector
    }

    func command(from event: UIEvent) -> RUMAddUserActionCommand? {
        guard let allTouches = event.allTouches else {
            return nil // not a touch event
        }
        guard allTouches.count == 1, let tap = allTouches.first else {
            return nil // not a single touch event
        }

        // Detect UIKit interactions first,
        // as they are more likely to happen.
        if let rumAction = createUIKitActionCommand(from: tap) {
            return rumAction
        }

        return swiftUIDetector?.createActionCommand(from: tap, predicate: swiftUIPredicate, dateProvider: dateProvider)
    }

    // MARK: UIKit

    private func createUIKitActionCommand(from tap: UITouch) -> RUMAddUserActionCommand? {
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

    /// Traverses the hierarchy of the `view` bottom-up to find the best view which could be considered for RUM Action's target,
    /// e.g. if the tapped `view` is a `UILabel` embedded in a `UIStackView` inside the `UITableViewCell` it will
    /// return the `UITableViewCell` as the best guess of user interaction.
    ///
    /// May return `nil` if there's no good guess and the RUM Action for given `view` should not be produced.
    private func bestActionTarget(for view: UIView) -> UIView? {
        if let uiControl = view as? UIControl {
            // If the `view` is a `UIControl` (interactive element), accept it.
            return uiControl
        } else {
            // If the `view` is not an interactive element, check if it's a child of a known view hierarchy
            // which can be considered as interactive.
            // For now this includes checking if the interacted view is an (in-)direct child of the `UITableViewCell`
            // or `UICollectionCell`, which is a common pattern when building list-based navigation on iOS.
            let bestParent = view.findInParentHierarchy { parent in
                return parent is UITableViewCell
                || parent is UICollectionViewCell
            }
            return bestParent // best parent or `nil`
        }
    }
}

// MARK: tvOS implementation
/// tvOS-specific implementation that detects user interactions through touches.
internal struct UIPressCommandFactory: UIEventCommandFactory {
    let dateProvider: DateProvider

    let uiKitPredicate: UIPressRUMActionsPredicate

    func command(from event: UIEvent) -> RUMAddUserActionCommand? {
        guard let event = event as? UIPressesEvent else {
            return nil // not a press event
        }
        guard event.allPresses.count == 1, let press = event.allPresses.first else {
            return nil // not a single press event
        }
        guard press.phase == .ended else {
            return nil // not in `.ended` phase
        }
        guard let view = press.responder as? UIView, view.isSafeForPrivacy else {
            return nil // no valid view
        }
        guard let action = uiKitPredicate.rumAction(press: press.type, targetView: view) else {
            return nil
        }
        return RUMAddUserActionCommand(
            time: dateProvider.now,
            attributes: action.attributes,
            instrumentation: .uikit,
            actionType: .click,
            name: action.name
        )
    }
}

// MARK: Helpers
private extension UIView {
    /// Traverses the hierarchy of this view from bottom-up to find any parent view matching
    /// the given predicate. It starts from `self`.
    func findInParentHierarchy(viewMatching predicate: (UIView) -> Bool) -> UIView? {
        if predicate(self) {
            return self
        } else if let superview = superview {
            return superview.findInParentHierarchy(viewMatching: predicate)
        } else {
            return nil
        }
    }
}
