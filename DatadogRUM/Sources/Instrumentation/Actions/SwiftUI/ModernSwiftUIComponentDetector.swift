/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogInternal

@available(iOS 18.0, tvOS 18.0, visionOS 18.0, *)
internal final class ModernSwiftUIComponentDetector: SwiftUIComponentDetector {
    /// Storage for pending touches that began but haven't ended yet
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

            // Special detection for SwiftUI Toogle
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
              view.isSwiftUIView else {
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
