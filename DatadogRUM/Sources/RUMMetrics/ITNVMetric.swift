/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal protocol ITNVMetricTracking {
    /// Tracks an action in a given view.
    /// Actions can be tracked even if the view is no longer active. For example, a "tap" can start in one view, but be tracked
    /// through this method even after the next view is started.
    /// - Parameters:
    ///   - startTime: The start time of the action.
    ///   - endTime: The end time of the action.
    ///   - actionType: The type of the user action.
    ///   - viewID: The ID of the view where the action occurred.
    func trackAction(startTime: Date, endTime: Date, actionType: RUMActionType, in viewID: RUMUUID)

    /// Tracks the start of a view.
    /// From this moment, calls to `value(for:)` for this `viewID` will return the value of ITNV.
    /// - Parameters:
    ///   - viewStart: The timestamp when the view starts.
    ///   - viewID: The ID of the view that has just started.
    func trackViewStart(at viewStart: Date, viewID: RUMUUID)

    /// Marks the completion of a view.
    /// Indicates that the view event will no longer be updated and no more calls to `value(for:)` for this `viewID` will be made.
    /// - Parameter viewID: The ID of the view that has completed.
    func trackViewComplete(viewID: RUMUUID)

    /// Retrieves the ITNV value for a specific view.
    /// Values are available after a view starts and before it completes.
    /// - Parameters:
    ///   - viewID: The ID of the view for which the ITNV value is requested.
    /// - Returns: The ITNV value (time interval) for the specified view, or `nil` if not available (the view has been completed).
    func value(for viewID: RUMUUID) -> TimeInterval?
}

internal final class ITNVMetric: ITNVMetricTracking {
    enum Constants {
        /// The maximum allowed duration for the ITNV metric. Values exceeding this threshold are ignored.
        static let maxDuration: TimeInterval = 3
    }

    /// The time of the last recorded action in the previous view.
    private var lastActionDateByViewID: [RUMUUID: Date] = [:]

    /// Stores the start times of views.
    private var startDateByViewID: [RUMUUID: Date] = [:]

    /// Tracks the previous view associated with each view.
    private var previousViewByViewID: [RUMUUID: RUMUUID] = [:]

    /// The ID of the current view.
    private var currentViewID: RUMUUID?

    func trackAction(startTime: Date, endTime: Date, actionType: RUMActionType, in viewID: RUMUUID) {
        // Retrieve the last recorded action time for the given view
        let lastDate = lastActionDateByViewID[viewID]
        switch actionType {
        case .tap, .click: // Discrete actions like tap or click should use their start time
            lastActionDateByViewID[viewID] = max(startTime, lastDate ?? .distantPast)
        case .swipe: // Continuous actions like swipe should use their end time
            lastActionDateByViewID[viewID] = max(endTime, lastDate ?? .distantPast)
        case .scroll, .custom:
            return // Ignore scroll and custom actions for ITNV calculation
        }
    }

    func trackViewStart(at viewStart: Date, viewID: RUMUUID) {
        startDateByViewID[viewID] = viewStart
        previousViewByViewID[viewID] = currentViewID
        currentViewID = viewID
    }

    func trackViewComplete(viewID: RUMUUID) {
        startDateByViewID[viewID] = nil

        if let previousViewID = previousViewByViewID[viewID] {
            lastActionDateByViewID[previousViewID] = nil
        }
        previousViewByViewID[viewID] = nil

        if viewID == currentViewID {
            currentViewID = nil
        }
    }

    func value(for viewID: RUMUUID) -> TimeInterval? {
        guard let viewStartDate = startDateByViewID[viewID] else {
            return nil // View has not started yet
        }

        guard let previousViewID = previousViewByViewID[viewID] else {
            return nil // No previous view for this one
        }

        guard let lastActionDate = lastActionDateByViewID[previousViewID] else {
            return nil // No action recorded in the previous view
        }

        let itnvValue = viewStartDate.timeIntervalSince(lastActionDate)

        guard itnvValue <= Constants.maxDuration else {
            return nil // ITNV exceeds the maximum allowed duration, return nil
        }

        return itnvValue
    }
}
