/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(macOS)

import Foundation
import AppKit
import DatadogInternal

/**
 *
 */
internal protocol SwiftUIComponentDetector {
    /// Processes a touch and creates a RUM action command if appropriate
    /// - Parameters:
    ///   - touch: The `UITouch` to process
    ///   - predicate: The predicate to use for determining if an action should be created
    ///   - dateProvider: Provider for current time
    /// - Returns: A RUM action command if one should be created, `nil` otherwise
    func createActionCommand(
        from event: NSEvent,
        predicate: AppKitRUMActionsPredicate?,
        dateProvider: DateProvider
    ) -> AccessibilityCommandResult
}

internal enum AccessibilityCommandResult {
    case noDecision
    case command(RUMAddUserActionCommand)
    case ignore
}

/// Protocol defining interface for type description functionality
@objc
internal protocol TypeDescribing {
    /// Returns a string describing the type of the object
    var typeDescription: String { get }
}

/// Default implementation for UIKit views
extension DDView: TypeDescribing {
    /// Returns a string describing the type of the view
    @objc var typeDescription: String {
        return String(describing: type(of: self))
    }
}

#endif
