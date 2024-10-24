/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogInternal

internal protocol UIEventCommandFactory {
    func command(from event: UIEvent) -> RUMAddUserActionCommand?
}

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

extension UIEventCommandFactory {
    /// Tells if capturing given `UIView` is safe for the user privacy.
    func isSafeForPrivacy(_ view: UIView) -> Bool {
        guard let window = view.window else {
            return false // The view is invisible, we can't determine if it's safe.
        }
        guard !NSStringFromClass(type(of: window)).contains("Keyboard") else {
            return false // The window class name suggests that it's the on-screen keyboard.
        }
        return true
    }
}

internal struct UITouchCommandFactory: UIEventCommandFactory {
    let dateProvider: DateProvider

    let predicate: UITouchRUMActionsPredicate

    func command(from event: UIEvent) -> RUMAddUserActionCommand? {
        guard let allTouches = event.allTouches else {
            return nil // not a touch event
        }
        guard allTouches.count == 1, let tap = allTouches.first else {
            return nil // not a single touch event
        }
        guard tap.phase == .ended else {
            return nil // not in `.ended` phase
        }
        guard let view = tap.view, isSafeForPrivacy(view) else {
            return nil // no valid view
        }
        guard let targetView = bestActionTarget(for: view) else {
            return nil // Tapped view is not eligible for producing RUM Action
        }
        guard let action = predicate.rumAction(targetView: targetView) else {
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

    // MARK: - RUM Action Target Capturing

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

internal struct UIPressCommandFactory: UIEventCommandFactory {
    let dateProvider: DateProvider

    let predicate: UIPressRUMActionsPredicate

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
        guard let view = press.responder as? UIView, isSafeForPrivacy(view) else {
            return nil // no valid view
        }
        guard let action = predicate.rumAction(press: press.type, targetView: view) else {
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
