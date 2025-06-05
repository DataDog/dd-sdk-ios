/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogInternal

internal enum SwiftUIComponentNames {
    static let button = "SwiftUI_Button"
    static let navigationLink = "SwiftUI_NavigationLink"
    static let toggle = "SwiftUI_Toggle"
    static let unidentified = "SwiftUI_Unidentified_Element"
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
