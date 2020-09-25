/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal protocol UIKitRUMUserActionsHandlerType: class {
    func subscribe(commandsSubscriber: RUMCommandSubscriber)
    func notify_sendEvent(application: UIApplication, event: UIEvent)
}

internal class UIKitRUMUserActionsHandler: UIKitRUMUserActionsHandlerType {
    private let dateProvider: DateProvider

    init(dateProvider: DateProvider) {
        self.dateProvider = dateProvider
    }

    // MARK: - UIKitRUMUserActionsHandlerType

    weak var subscriber: RUMCommandSubscriber?

    func subscribe(commandsSubscriber: RUMCommandSubscriber) {
        self.subscriber = commandsSubscriber
    }

    func notify_sendEvent(application: UIApplication, event: UIEvent) {
        guard let tappedView = captureSingleTouch(event: event)?.view else {
            return // Not a "tap" event or doesn't have the view.
        }
        guard isSafeForPrivacy(tappedView) else {
            return // Ignore for privacy reason.
        }
        guard let actionTargetView = bestActionTarget(for: tappedView) else {
            return // Tapped view is not eligible for producing RUM Action
        }

        subscriber?.process(
            command: RUMAddUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: [:],
                actionType: .tap,
                name: targetName(for: actionTargetView)
            )
        )
    }

    // MARK: - Events Filtering

    /// Returns the `UITouch` for given `event` only if the event describes the "single tap ended" interaction.
    private func captureSingleTouch(event: UIEvent) -> UITouch? {
        guard let allTouches = event.allTouches else {
            return nil // not a touch event
        }
        guard allTouches.count == 1, let tap = allTouches.first else {
            return nil // not a single touch event
        }
        guard tap.phase == .ended else {
            return nil // touch is not in the `.ended` phase
        }
        return tap
    }

    /// Tells if capturing given `UIView` is safe for the user privacy.
    private func isSafeForPrivacy(_ view: UIView) -> Bool {
        guard let window = view.window else {
            return false // The view is invisible, we can't determine if it's safe.
        }
        guard !NSStringFromClass(type(of: window)).contains("Keyboard") else {
            return false // The window class name suggests that it's the on-screen keyboard.
        }
        return true
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

    /// Builds the RUM Action's `target` name for given `UIView`.
    private func targetName(for view: UIView) -> String {
        let className = NSStringFromClass(type(of: view))

        if let accessibilityIdentifier = view.accessibilityIdentifier {
            return "\(className)(\(accessibilityIdentifier))"
        } else {
            return className
        }
    }
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
