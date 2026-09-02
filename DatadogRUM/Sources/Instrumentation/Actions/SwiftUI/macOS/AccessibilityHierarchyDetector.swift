/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(macOS)

import Foundation
import AppKit
import DatadogInternal

/// Protocol defining the macOS version of the SwiftUI component detector.
internal protocol AccessibilityHierarchyDetector {
    /// Processes a touch and creates a RUM action command if appropriate
    /// - Parameters:
    ///   - touch: The `NSEvent` to process
    ///   - predicate: The predicate to use for determining if an action should be created
    ///   - dateProvider: Provider for current time
    /// - Returns: A RUM action command if one should be created, `nil` otherwise
    func createActionCommand(
        from event: NSEvent,
        predicate: MacOSRUMActionsPredicate?,
        dateProvider: DateProvider
    ) -> AccessibilityCommandResult
}

/// Result from `SwiftUIComponentDetector.createActionCommand(from:predicate:dateProvider:)`.
internal enum AccessibilityCommandResult {
    /// The accessibility detector could not find a suitable target, and no predicate rejection happened.
    ///
    /// The caller is free to use any AppKit callback, or give up, depending on the current context.
    case noDecision

    /// A `RUMAddUserActionCommand` was obtained from the given event.
    case command(RUMAddUserActionCommand)

    /// The event should not generate a `RUMAddUserActionCommand` because the predicate
    /// explicitly rejected the proposed target.
    case ignore
}

#endif
