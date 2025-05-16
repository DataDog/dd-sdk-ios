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
    /// Factory that creates the appropriate SwiftUI detector based on platform and version.
    /// Modern detection is only available on iOS 18+ and tvOS 18+.
    static func createDetector() -> SwiftUIComponentDetector {
        if #available(iOS 18.0, tvOS 18.0, visionOS 18.0, *) {
            return ModernSwiftUIComponentDetector()
        }
        return LegacySwiftUIComponentDetector()
    }
}

/**
 * SwiftUI component detection relies on internal implementation details that may change
 * with iOS updates. Our strategy uses different approaches for different iOS versions:
 *
 * iOS 18+ (Modern):
 * This detector uses a two-phase detection strategy.
 * 1. Begin Phase (.began):
 *    - Captures and stores gesture information
 *    - Identifies component type (Button, NavigationLink) from gesture's name
 *    - Stores pending action with timestamp for later processing
 *
 * 2. End Phase (.ended):
 *    - Matches with stored begin-phase data
 *    - Creates RUM action if the touch completes successfully
 *
 * iOS 17 and below (Legacy):
 * - Uses view hierarchy analysis for basic detection
 * - Limited component identification:
 * reports generic interactions for most components
 * - May have some false positives: 
 * a `Button` can't be differentiated from a `Label`, therefore we report both interactions
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
@available(iOS 18.0, tvOS 18.0, visionOS 18.0, *)
internal final class ModernSwiftUIComponentDetector: SwiftUIComponentDetector {
    /// Storage for pending touches that began but haven't ended yet
    @ReadWriteLock
    private var pendingSwiftUIActions = [ObjectIdentifier: PendingAction]()
    private static let stalePendingActionTimeout: TimeInterval = 5.0 // 5-sec timeout

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
            pendingSwiftUIActions[ObjectIdentifier(touch)] = PendingAction(
                componentName: SwiftUIComponentNames.navigationLink,
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
            return currentTime - action.timestamp < Self.stalePendingActionTimeout
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
               !SwiftUIContainerViews.shouldIgnore(view.typeDescription) {
                let refinedName = SwiftUIComponentHelpers.extractComponentName(
                    touch: touch,
                    defaultName: SwiftUIComponentNames.unidentified
                )

                if let rumAction = predicate.rumAction(with: refinedName) {
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

private enum SwiftUIContainerViews {
    /// SwiftUI container views that should be ignored for action tracking
    /// to avoid duplicate events and noise
    static let ignoredTypeDescriptions: Set<String> = [
        "HostingView",
        "HostingScrollView",
        "PlatformGroupContainer"
    ]

    static func shouldIgnore(_ typeDescription: String) -> Bool {
        return ignoredTypeDescriptions.contains { typeDescription.contains($0) }
    }
}
