/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol TTNSMetricTracking {
    /// Tracks the start time of a resource identified by its `resourceID`.
    ///
    /// - Parameters:
    ///   - startDate: The start time of the resource (device time, no NTP offset).
    ///   - resourceID: The unique identifier for the resource.
    func trackResourceStart(at startDate: Date, resourceID: RUMUUID)

    /// Tracks the completion of a resource identified by its `resourceID`.
    ///
    /// - Parameters:
    ///   - endDate: The end time of the resource (device time, no NTP offset).
    ///   - resourceID: The unique identifier for the resource.
    ///   - resourceDuration: The resource duration, if available.
    func trackResourceEnd(at endDate: Date, resourceID: RUMUUID, resourceDuration: TimeInterval?)

    /// Marks the view as stopped, preventing further resource tracking.
    func trackViewWasStopped()

    /// Returns the value for the TTNS metric.
    ///
    /// - Parameters:
    ///   - time: The current time (device time, no NTP offset).
    ///   - appStateHistory: The history of app state transitions.
    /// - Returns: The value for TTNS metric.
    func value(at time: Date, appStateHistory: AppStateHistory) -> TimeInterval?
}

/// A metric (**Time-to-Network-Settled**) that measures the time from when the current view becomes visible until all initial resources are loaded.
///
/// "Initial resources" are defined as resources starting within 100ms of the view becoming visible.
internal final class TTNSMetric: TTNSMetricTracking {
    enum Constants {
        /// Only resources starting within this interval of the view becoming visible are considered "initial resources."
        static let initialResourceThreshold: TimeInterval = 0.1
    }

    /// The time when the view tracking this metric becomes visible (device time, no NTP offset).
    private let viewStartDate: Date

    /// Indicates whether the view is active (`true`) or stopped (`false`).
    private var isViewActive = true

    /// A dictionary mapping resource IDs to their start times. Only tracks initial resources.
    private var pendingResourcesStartDates: [RUMUUID: Date] = [:]

    /// The time when the last of the initial resources completes.
    private var latestResourceEndDate: Date?

    /// Initializes a new TTNSMetric instance for a view.
    ///
    /// - Parameter viewStartDate: The time when the view becomes visible (device time, no NTP offset).
    init(viewStartDate: Date) {
        self.viewStartDate = viewStartDate
    }

    /// Tracks the start time of a resource identified by its `resourceID`.
    /// Only resources starting within the initial threshold are tracked.
    ///
    /// - Parameters:
    ///   - startDate: The start time of the resource (device time, no NTP offset).
    ///   - resourceID: The unique identifier for the resource.
    func trackResourceStart(at startDate: Date, resourceID: RUMUUID) {
        guard isViewActive else {
            return // View was stopped, do not track the resource
        }

        let isInitialResource = startDate.timeIntervalSince(viewStartDate) <= Constants.initialResourceThreshold && startDate >= viewStartDate
        if isInitialResource {
            pendingResourcesStartDates[resourceID] = startDate
        }
    }

    /// Tracks the completion of a resource identified by its `resourceID`.
    /// The `resourceDuration` is used if available; otherwise, the duration is calculated from the start to the end time.
    ///
    /// - Parameters:
    ///   - endDate: The end time of the resource (device time, no NTP offset).
    ///   - resourceID: The unique identifier for the resource.
    ///   - resourceDuration: The resource duration, if available.
    func trackResourceEnd(at endDate: Date, resourceID: RUMUUID, resourceDuration: TimeInterval?) {
        guard isViewActive, let startDate = pendingResourcesStartDates[resourceID] else {
            return // View was stopped or the resource was not tracked
        }

        let duration = resourceDuration ?? endDate.timeIntervalSince(startDate)
        let resourceEndDate = startDate.addingTimeInterval(duration)

        latestResourceEndDate = max(latestResourceEndDate ?? .distantPast, resourceEndDate)
        pendingResourcesStartDates[resourceID] = nil // Remove from the list of ongoing resources
    }

    /// Marks the view as stopped, preventing further resource tracking.
    func trackViewWasStopped() {
        isViewActive = false
    }

    /// Returns the value for the TTNS metric.
    /// - The value is only available after all initial resources have completed loading and no earlier than 100ms after view start.
    /// - The value is not tracked if the view was stopped before all initial resources completed loading.
    /// - The value is only tracked if the app was in "active" state during view loading.
    ///
    /// - Parameters:
    ///   - time: The current time (device time, no NTP offset).
    ///   - appStateHistory: The history of app state transitions.
    /// - Returns: The value for TTNS metric.
    func value(at time: Date, appStateHistory: AppStateHistory) -> TimeInterval? {
        guard time > viewStartDate.addingTimeInterval(Constants.initialResourceThreshold) else {
            return nil // No value before 100ms after view start
        }
        guard pendingResourcesStartDates.isEmpty else {
            return nil // No value until all initial resources are completed
        }
        guard let latestResourceEndDate = latestResourceEndDate else {
            return nil // Tracked no resource
        }

        let ttnsValue = latestResourceEndDate.timeIntervalSince(viewStartDate)
        let viewLoadedDate = viewStartDate.addingTimeInterval(ttnsValue)

        guard viewLoadedDate >= viewStartDate else { // sanity check
            return nil
        }

        // Check if app was in "active" state during the view loading period
        let viewLoadingAppStates = appStateHistory.take(between: viewStartDate...viewLoadedDate)
        let trackedInForeground = !(viewLoadingAppStates.snapshots.contains { $0.state != .active })

        guard trackedInForeground else {
            return nil // The app was not always "active" during view loading
        }

        return ttnsValue
    }
}
