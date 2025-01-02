/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A struct representing the parameters of a RUM action that may be considered the "last interaction" in the previous view
/// for the Interaction-To-Next-View (ITNV) metric.
public struct ITNVActionParams {
    /// The type of the action (e.g., tap, swipe, click).
    public let type: RUMActionType

    /// The name of the action.
    public let name: String

    /// The time elapsed between this action and the start of the next view.
    public let timeToNextView: TimeInterval

    /// The name of the next view.
    public let nextViewName: String
}

/// A protocol for classifying which action in the previous view should be considered the "last interaction" for the
/// Interaction-To-Next-View (ITNV) metric.
///
/// This predicate is called in reverse chronological order for each action in the previous view until an implementation
/// returns `true`. The action for which `true` is returned will be classified as the "last interaction," and the ITNV metric
/// in the subsequent view will be measured from this action’s time to the new view’s start.
///
/// **Note:**
/// - The `isLastAction(from:)` method will be called on a secondary thread.
/// - The implementation must not assume any specific threading behavior and should avoid blocking.
/// - The method should always return the same result for identical input parameters to ensure consistent ITNV calculation.
public protocol NextViewActionPredicate {
    /// Determines whether the provided action should be classified as the "last interaction" in the previous view for ITNV calculation.
    ///
    /// This method is invoked in reverse chronological order for all actions in the previous view. Once `true` is returned,
    /// the iteration stops, and the accepted action defines the starting point for the ITNV metric.
    ///
    /// - Parameter actionParams: The parameters of the action (type, name, time to next view, and next view name).
    /// - Returns: `true` if this action is the "last interaction" for ITNV, `false` otherwise.
    func isLastAction(from actionParams: ITNVActionParams) -> Bool
}

/// A predicate implementation for classifying the "last interaction" for the Interaction-To-Next-View (ITNV) metric
/// based on a time threshold and action type. This predicate considers tap, click, or swipe actions in the previous view
/// as valid if the interval between the action and the next view’s start (`timeToNextView`) is within `maxTimeToNextView`.
///
/// The default value of `maxTimeToNextView` is `3` seconds.
public struct TimeBasedITNVActionPredicate: NextViewActionPredicate {
    /// The default maximum time interval for considering an action as the "last interaction."
    public static let defaultMaxTimeToNextView: TimeInterval = 3

    /// The maximum duration (in seconds) from the action to the next view’s start. Actions exceeding this duration are ignored.
    let maxTimeToNextView: TimeInterval

    /// Initializes a new predicate with a specified maximum time interval.
    ///
    /// - Parameter maxTimeToNextView: The maximum time interval (in seconds) from the action to the next view’s start.
    ///                                The default value is `3` seconds.
    public init(maxTimeToNextView: TimeInterval = TimeBasedITNVActionPredicate.defaultMaxTimeToNextView) {
        self.maxTimeToNextView = maxTimeToNextView
    }

    /// Determines if the provided action should be considered the "last interaction" for ITNV, based on its action type and timing.
    ///
    /// - Parameter actionParams: The parameters of the action (type, name, time to next view, and next view name).
    /// - Returns: `true` if the action’s `timeToNextView` is within `maxTimeToNextView` and its type is `tap`, `click`, or `swipe`;
    ///            otherwise, `false`.
    public func isLastAction(from actionParams: ITNVActionParams) -> Bool {
        // Action must occur within the allowed time range
        guard actionParams.timeToNextView >= 0, actionParams.timeToNextView <= maxTimeToNextView else {
            return false
        }

        // Only specific action types qualify as the "last interaction"
        switch actionParams.type {
        case .tap, .click, .swipe:
            return true
        case .scroll, .custom:
            return false
        }
    }
}
