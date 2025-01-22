/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal protocol INVMetricTracking {
    /// Tracks an action in a given view.
    ///
    /// An action can start in one view but still be tracked through this method even after the next view begins.
    /// For instance, a tap might begin in one view but end after the next view is already displayed.
    ///
    /// - Parameters:
    ///   - startTime: The time when the action started (device time, no NTP offset).
    ///   - endTime: The time when the action ended (device time, no NTP offset).
    ///   - name: A string identifying the action (e.g., button label).
    ///   - type: The specific type of the action (e.g., tap, swipe).
    ///   - viewID: The unique identifier of the view where the action was initiated.
    func trackAction(startTime: Date, endTime: Date, name: String, type: RUMActionType, in viewID: RUMUUID)

    /// Tracks the start of a view.
    ///
    /// From this point forward, calling `value(for:)` with this `viewID` can return an INV value, until the view is completed.
    ///
    /// - Parameters:
    ///   - startTime: The time when the view becomes active (device time, no NTP offset).
    ///   - name: A human-readable name of the view.
    ///   - viewID: The unique identifier of the newly started view.
    func trackViewStart(at startTime: Date, name: String, viewID: RUMUUID)

    /// Marks the completion of a view.
    ///
    /// Indicates that the view is no longer updated and that `value(for:)` calls for this `viewID` will no longer occur.
    ///
    /// - Parameter viewID: The unique identifier of the view that has been completed.
    func trackViewComplete(viewID: RUMUUID)

    /// Retrieves the INV value for a specified view.
    ///
    /// The INV value is available only after the view has started and before it’s marked completed.
    ///
    /// - Parameter viewID: The unique identifier of the view for which the metric is requested.
    /// - Returns: The INV metric value (`TimeInterval`) if successfully calculated, or a `INVNoValueReason` indicating why the value is unavailable.
    func value(for viewID: RUMUUID) -> Result<TimeInterval, INVNoValueReason>
}

/// Possible reasons for a missing INV value.
/// This list is standardized according to the "RUM View Ended" metric specification.
internal enum INVNoValueReason: String, Error {
    /// No actions were tracked in the previous view.
    case noTrackedActions = "no_action"
    /// No valid "last interaction" was found in the previous view according to the configured strategy.
    case noLastInteraction = "no_eligible_action"
    /// There is no preceding view to compute the INV metric from.
    case noPrecedingView = "no_previous_view"
    /// The view is unknown (it was never started or no longer exists).
    case viewUnknown = "unknown_view"
    /// The previous view data was removed because the current view has already completed.
    case previousViewRemoved = "previous_view_removed"
    /// Actions were tracked in the previous view, but all were invalid (e.g., started before the view started).
    case invalidTrackedActions = "invalid_actions"
}

internal final class INVMetric: INVMetricTracking {
    /// Represents a user action.
    private struct Action {
        let type: RUMActionType
        let name: String
        let date: Date
        let duration: TimeInterval
    }

    /// Represents a view in the INV workflow.
    private struct View {
        let name: String
        let startTime: Date
        /// Holds the identifier of the previous view, so we can compute INV from the previous view's action to this view's start.
        let previousViewID: RUMUUID?
        /// Stores actions tracked in this view that have not yet been queried by `NextViewActionPredicate`.
        /// Actions are removed from this array after they are queried.
        var actions: [Action] = []
        /// Counts all valid actions tracked in this view. This counter only increases and is not affected by changes to the `actions` array.
        var validActionsCount: Int = 0
        /// Counts all invalid actions (e.g., actions that occurred before the view started).
        var invalidActionsCount: Int = 0
    }

    /// Holds all tracked views by their unique identifiers.
    private var viewsByID: [RUMUUID: View] = [:]

    /// The identifier of the currently active view.
    private var currentViewID: RUMUUID?

    /// Predicate for determining which action qualifies as the "last interaction" for the INV metric.
    private let predicate: NextViewActionPredicate

    /// Initializes the INV metric system with an optional custom predicate.
    ///
    /// - Parameter predicate: A predicate defining which action is considered the "last interaction" in the previous view.
    init(predicate: NextViewActionPredicate) {
        self.predicate = predicate
    }

    func trackAction(startTime: Date, endTime: Date, name: String, type: RUMActionType, in viewID: RUMUUID) {
        guard var view = viewsByID[viewID] else {
            return // The view has not been started or is unknown.
        }
        defer { viewsByID[viewID] = view } // Update the stored view after modifications.

        guard startTime >= view.startTime else {
            view.invalidActionsCount += 1
            return // Ignore actions that occurred before the view started.
        }

        let action = Action(
            type: type,
            name: name,
            date: startTime,
            duration: endTime.timeIntervalSince(startTime)
        )
        view.actions.append(action)
        view.validActionsCount += 1
    }

    func trackViewStart(at startTime: Date, name: String, viewID: RUMUUID) {
        // Create and store a new view, referencing the previously active view.
        viewsByID[viewID] = View(name: name, startTime: startTime, previousViewID: currentViewID)
        currentViewID = viewID
    }

    func trackViewComplete(viewID: RUMUUID) {
        // When this view completes, remove its previous view entry because it’s no longer needed.
        // We still keep the current view entry, as it may be needed to compute INV for the next view.
        guard let view = viewsByID[viewID], let previousViewID = view.previousViewID else {
            return
        }
        viewsByID[previousViewID] = nil
    }

    func value(for viewID: RUMUUID) -> Result<TimeInterval, INVNoValueReason> {
        guard let view = viewsByID[viewID] else {
            return .failure(.viewUnknown)
        }

        guard let previousViewID = view.previousViewID else {
            return .failure(.noPrecedingView)
        }

        guard var previousView = viewsByID[previousViewID] else {
            return .failure(.previousViewRemoved)
        }
        defer { viewsByID[previousViewID] = previousView } // Update the stored view after modifications.

        guard previousView.validActionsCount > 0 else {
            return .failure(previousView.invalidActionsCount == 0 ? .noTrackedActions : .invalidTrackedActions)
        }

        // We iterate actions in reverse chronological order, stopping on the first match.
        // This reflects the INV contract that the "last interaction" is determined by
        // checking the most recent actions first.
        let lastAction = previousView.actions
            .reversed()
            .first { action in
                let params = actionParams(for: action, nextViewStart: view.startTime, nextViewName: view.name)
                return predicate.isLastAction(from: params)
            }

        guard let lastAction = lastAction else {
            previousView.actions = [] // No "last interaction"; remove all actions so we don't ask again
            return .failure(.noLastInteraction)
        }

        // Keep only the action classified as "last interaction." Future actions can still be appended after this one.
        previousView.actions = [lastAction]

        let invValue = timeToNextView(for: lastAction, nextViewStart: view.startTime)
        return .success(invValue)
    }

    /// Creates the params object for the given action, to be inspected by the `NextViewActionPredicate`.
    private func actionParams(for action: Action, nextViewStart: Date, nextViewName: String) -> INVActionParams {
        return INVActionParams(
            type: action.type,
            name: action.name,
            timeToNextView: timeToNextView(for: action, nextViewStart: nextViewStart),
            nextViewName: nextViewName
        )
    }

    /// Computes the interval from the user action to the start of the next view, depending on the action type.
    /// For some action types (tap, click, custom), the relevant start time is `action.date`.
    /// For others (scroll, swipe), we account for the action's duration.
    private func timeToNextView(for action: Action, nextViewStart: Date) -> TimeInterval {
        switch action.type {
        case .tap, .click, .custom:
            return nextViewStart.timeIntervalSince(action.date)
        case .scroll, .swipe:
            return nextViewStart.timeIntervalSince(action.date + action.duration)
        }
    }
}
