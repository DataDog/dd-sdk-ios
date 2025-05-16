/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogInternal

private enum SwiftUIComponentNames {
    static let button = "SwiftUI_Button"
    static let navigationLink = "SwiftUI_NavigationLink"
    static let toggle = "SwiftUI_Toggle"
    static let unidentified = "SwiftUI_Unidentified_Element"
}

internal enum SwiftUIComponentFactory {
    /// Factory that creates the appropriate SwiftUI detector based on iOS version
    static func createDetector() -> SwiftUIComponentDetector {
        if #available(iOS 18.0, *) {
            return ModernSwiftUIComponentDetector()
        } else {
            return LegacySwiftUIComponentDetector()
        }
    }
}

/**
 * SwiftUI component detection relies on internal implementation details that may change
 * with iOS updates. Our strategy uses different approaches for different iOS versions:
 *
 * - iOS 18+: We can detect SwiftUI buttons during the `.began` phase by analyzing touch
 *   and gesture information. This gives us more reliable component identification.
 *
 * - iOS 17 and earlier: We use a simpler heuristic approach that can identify
 *   basic interactions but with less component-specific granularity.
 */

internal protocol SwiftUIComponentDetector {
    /// Processes a touch and creates a RUM action command if appropriate
    /// - Parameters:
    ///   - touch: The `UITouch` to process
    ///   - predicate: The predicate to use for determining if an action should be created
    ///   - dateProvider: Provider for current time
    /// - Returns: A RUM action command if one should be created, `nil` otherwise
    func createActionCommand(
        from touch: UITouch,
        predicate: SwiftUIRUMActionsPredicate?,
        dateProvider: DateProvider
    ) -> RUMAddUserActionCommand?
}

// MARK: Implementation for iOS 18+
@available(iOS 18.0, *)
internal final class ModernSwiftUIComponentDetector: SwiftUIComponentDetector {
    /// Storage for pending touches that began but haven't ended yet
    private var pendingSwiftUIActions = [ObjectIdentifier: PendingAction]()

    /// Represents a touch in the `.began` phase that we're tracking
    private struct PendingAction {
        let componentName: String
        let timestamp: TimeInterval
    }

    func createActionCommand(
        from touch: UITouch,
        predicate: SwiftUIRUMActionsPredicate?,
        dateProvider: DateProvider
    ) -> RUMAddUserActionCommand? {
        guard let predicate = predicate else {
            return nil
        }

        cleanupStalePendingActions()

        /// Handle `.began` phase:
        /// store information for later use
        if touch.phase == .began,
           handleTouchBegan(touch, dateProvider: dateProvider) {
            return nil
        }

        /// Handle `.ended` phase
        if touch.phase == .ended {
            /// Retrieve pending action and create the corresponding command
            if let command = createCommandFromPendingTouch(
                for: touch,
                predicate: predicate,
                dateProvider: dateProvider
            ) {
                return command
            }

            /// Special detection for SwiftUI Toogle
            return SwiftUIComponentHelpers.extractSwiftUIToggleAction(
                from: touch,
                predicate: predicate,
                dateProvider: dateProvider
            )
        }

        return nil
    }

    /// Processes a touch in the `.began` phase,
    /// which is when we can detect the Button gesture.
    private func handleTouchBegan(_ touch: UITouch, dateProvider: DateProvider) -> Bool {
        guard let view = touch.view,
              view.isSwiftUIView,
              view.isSafeForPrivacy else {
            return false
        }

        let touchDescription = String(describing: touch)
        if touchDescription.contains("ButtonGesture") {
            let refinedName = SwiftUIComponentHelpers.extractComponentName(
                touch: touch,
                defaultName: SwiftUIComponentNames.button
            )

            pendingSwiftUIActions[ObjectIdentifier(touch)] = PendingAction(
                componentName: refinedName,
                timestamp: dateProvider.now.timeIntervalSince1970
            )
            return true
        }

        return false
    }

    /// Creates a command from a pending touch if one exists for the given touch
    private func createCommandFromPendingTouch(
        for touch: UITouch,
        predicate: SwiftUIRUMActionsPredicate?,
        dateProvider: DateProvider
    ) -> RUMAddUserActionCommand? {
        guard let pendingAction = pendingSwiftUIActions[ObjectIdentifier(touch)],
              let predicate else {
            return nil
        }

        pendingSwiftUIActions.removeValue(forKey: ObjectIdentifier(touch))

        let refinedName = SwiftUIComponentHelpers.extractComponentName(
            touch: touch,
            defaultName: pendingAction.componentName
        )

        if let rumAction = predicate.rumAction(with: refinedName) {
            print(">LOG \(refinedName) ACTION (SWIFTUI)")
            return RUMAddUserActionCommand(
                time: dateProvider.now,
                attributes: rumAction.attributes,
                instrumentation: .swiftuiAutomatic,
                actionType: .tap,
                name: rumAction.name
            )
        }

        return nil
    }

    // MARK: Helpers
    /// Prevents memory growth by removing stale touch records
    /// that never completed their lifecycle
    private func cleanupStalePendingActions() {
        let currentTime = Date().timeIntervalSinceReferenceDate
        pendingSwiftUIActions = pendingSwiftUIActions.filter { _, action in
            return currentTime - action.timestamp < 5.0 // 5-sec timeout
        }
    }
}

// MARK: Implementation for iOS 17 and below
internal final class LegacySwiftUIComponentDetector: SwiftUIComponentDetector {
    func createActionCommand(
        from touch: UITouch,
        predicate: SwiftUIRUMActionsPredicate?,
        dateProvider: DateProvider
    ) -> RUMAddUserActionCommand? {
        guard let predicate = predicate else {
            return nil
        }

        if touch.phase == .ended {
            if let view = touch.view,
               view.isSwiftUIView,
               view.isSafeForPrivacy,
               // For iOS 17 and below, we can't reliably distinguish SwiftUI component types (e.g., Button vs Label).
               // We exclude hosting views and track other SwiftUI elements with a generic name.
                !view.typeDescription.contains("HostingView"),
                !view.typeDescription.contains("HostingScrollView") {
                let refinedName = SwiftUIComponentHelpers.extractComponentName(
                    touch: touch,
                    defaultName: SwiftUIComponentNames.unidentified
                )

                if let rumAction = predicate.rumAction(with: refinedName) {
                    print(">LOG \(rumAction.name) ACTION (SWIFTUI)")
                    return RUMAddUserActionCommand(
                        time: dateProvider.now,
                        attributes: rumAction.attributes,
                        instrumentation: .swiftuiAutomatic,
                        actionType: .tap,
                        name: rumAction.name
                    )
                }
            }

            // Fallback
            return SwiftUIComponentHelpers.extractSwiftUIToggleAction(
                from: touch,
                predicate: predicate,
                dateProvider: dateProvider
            )
        }

        return nil
    }
}

/// Utility class with static helper methods
internal class SwiftUIComponentHelpers {
    /// Extracts a component name from a touch, using gesture information when available
    /// - Parameters:
    ///   - touch: The `UITouch` to analyze
    ///   - defaultName: The fallback name to use if a more specific one can't be determined
    /// - Returns: The best available component name
    ///
    /// Note: SwiftUI component detection relies on internal implementation details
    /// which may change with iOS updates. This method uses various heuristics to
    /// identify common components like buttons and navigation links.
    /// Note: We check gestures' names both during the `.began` and `.ended` phases
    /// as we can collect different information.
    static func extractComponentName(touch: UITouch, defaultName: String) -> String {
        // Check gesture recognizers' names for more specific info
        if let gestures = touch.gestureRecognizers {
            for gesture in gestures {
                if let gestureName = gesture.name {
                    // E.g., Button<ResolvedButtonStyleBody<BorderlessButtonStyleBase>>
                    if gestureName.hasPrefix("Button<") {
                        return SwiftUIComponentNames.button
                    } else if gestureName == "com.apple.UIKit.HomeAffordanceGate" {
                        return SwiftUIComponentNames.navigationLink
                    }
                }
            }
        }

        return defaultName
    }

    /// Extracts a SwiftUI Toggle action from a touch if applicable
    /// - Parameters:
    ///   - touch: The `UITouch` to analyze
    ///   - predicate: The predicate to use for determining if an action should be created
    ///   - dateProvider: Provider for current time
    /// - Returns: A RUM action command if a toggle was detected, `nil` otherwise
    static func extractSwiftUIToggleAction(
        from touch: UITouch,
        predicate: SwiftUIRUMActionsPredicate?,
        dateProvider: DateProvider
    ) -> RUMAddUserActionCommand? {
        guard let predicate = predicate else {
            return nil
        }

        if let grandSuperview = touch.view?.superview?.superview {
            if grandSuperview.typeDescription.hasPrefix("UISwitch"),
               touch.phase == .ended,
               let rumAction = predicate.rumAction(with: SwiftUIComponentNames.toggle) {
                print(">LOG \(SwiftUIComponentNames.toggle) ACTION (SWIFTUI)")
                return RUMAddUserActionCommand(
                    time: dateProvider.now,
                    attributes: rumAction.attributes,
                    instrumentation: .swiftuiAutomatic,
                    actionType: .tap,
                    name: rumAction.name
                )
            }
        }

        return nil
    }
}

/// Protocol defining interface for type description functionality
@objc
internal protocol TypeDescribing {
    /// Returns a string describing the type of the object
    var typeDescription: String { get }
}

/// Default implementation for UIKit views
extension UIView: TypeDescribing {
    /// Returns a string describing the type of the view
    @objc var typeDescription: String {
        return String(describing: type(of: self))
    }
}
