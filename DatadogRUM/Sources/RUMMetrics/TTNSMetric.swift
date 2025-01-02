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
    ///   - resourceURL: The URL of this resource.
    func trackResourceStart(at startDate: Date, resourceID: RUMUUID, resourceURL: String)

    /// Tracks the completion of a resource identified by its `resourceID`.
    ///
    /// - Parameters:
    ///   - endDate: The end time of the resource (device time, no NTP offset).
    ///   - resourceID: The unique identifier for the resource.
    ///   - resourceDuration: The resource duration, if available.
    func trackResourceEnd(at endDate: Date, resourceID: RUMUUID, resourceDuration: TimeInterval?)

    /// Tracks the completion of a resource without considering its duration.
    ///
    /// - Parameters:
    ///   - resourceID: The unique identifier for the resource.
    func trackResourceDropped(resourceID: RUMUUID)

    /// Marks the view as stopped, preventing further resource tracking.
    func trackViewWasStopped()

    /// Returns the value for the TTNS metric.
    ///
    /// - Parameters:
    ///   - time: The current time (device time, no NTP offset).
    ///   - appStateHistory: The history of app state transitions.
    /// - Returns: The value for the TTNS metric, or `nil` if the metric cannot be calculated.
    func value(at time: Date, appStateHistory: AppStateHistory) -> TimeInterval?
}

/// A metric (**Time-to-Network-Settled**, or TTNS) that measures the time from when the view becomes visible until all initial resources are loaded.
/// "Initial resources" are now classified using a customizable predicate.
internal final class TTNSMetric: TTNSMetricTracking {
    /// The name of the view this metric is tracked for.
    private let viewName: String

    /// The time when the view tracking this metric becomes visible (device time, no NTP offset).
    private let viewStartDate: Date

    /// The predicate used to classify resources as "initial" for TTNS.
    private let resourcePredicate: NetworkSettledResourcePredicate

    /// Indicates whether the view is active (`true`) or stopped (`false`).
    private var isViewActive = true

    /// A dictionary mapping resource IDs to their start times. Tracks resources classified as "initial."
    private var pendingResourcesStartDates: [RUMUUID: Date] = [:]

    /// The time when the last of the initial resources completes.
    private var latestResourceEndDate: Date?

    /// Stores the last computed value for the TTNS metric.
    /// This is used to return the same value for subsequent calls to `value(at:appStateHistory:)`
    /// while some resources are still pending.
    private var lastReturnedValue: TimeInterval?

    /// Initializes a new TTNSMetric instance for a view with a customizable predicate.
    ///
    /// - Parameters:
    ///   - viewName: The name of the view this metric is tracked for.
    ///   - viewStartDate: The time when the view becomes visible (device time, no NTP offset).
    ///   - resourcePredicate: A predicate used to classify resources as "initial" for TTNS.
    init(
        viewName: String,
        viewStartDate: Date,
        resourcePredicate: NetworkSettledResourcePredicate
    ) {
        self.viewName = viewName
        self.viewStartDate = viewStartDate
        self.resourcePredicate = resourcePredicate
    }

    /// Tracks the start time of a resource identified by its `resourceID`.
    /// Only resources classified as "initial" by the predicate are tracked.
    ///
    /// - Parameters:
    ///   - startDate: The start time of the resource (device time, no NTP offset).
    ///   - resourceID: The unique identifier for the resource.
    ///   - resourceURL: The URL of this resource.
    func trackResourceStart(at startDate: Date, resourceID: RUMUUID, resourceURL: String) {
        guard isViewActive else {
            return // View was stopped, do not track the resource
        }
        guard startDate >= viewStartDate else {
            return // Sanity check to ensure resource is being tracked after view start
        }

        let resourceParams = TTNSResourceParams(
            url: resourceURL,
            timeSinceViewStart: startDate.timeIntervalSince(viewStartDate),
            viewName: viewName
        )
        if resourcePredicate.isInitialResource(from: resourceParams) {
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

        guard duration >= 0 else {
            return // Sanity check to avoid negative durations
        }

        let resourceEndDate = startDate.addingTimeInterval(duration)
        latestResourceEndDate = max(latestResourceEndDate ?? .distantPast, resourceEndDate)
        pendingResourcesStartDates[resourceID] = nil // Remove from the list of ongoing resources
    }

    /// Tracks the completion of a resource without considering its duration.
    /// Used to end resources dropped through event mapper APIs.
    ///
    /// - Parameters:
    ///   - resourceID: The unique identifier for the resource.
    func trackResourceDropped(resourceID: RUMUUID) {
        pendingResourcesStartDates[resourceID] = nil // Remove from the list of ongoing resources
    }

    /// Marks the view as stopped, preventing further resource tracking.
    func trackViewWasStopped() {
        isViewActive = false
    }

    /// Returns the value for the TTNS metric.
    /// - The value is only available after all initial resources have completed loading.
    /// - The value is not updated after view is stopped.
    /// - The value is only tracked if the app was in "active" state during view loading.
    ///
    /// - Parameters:
    ///   - time: The current time (device time, no NTP offset).
    ///   - appStateHistory: The history of app state transitions.
    /// - Returns: The value for TTNS metric.
    func value(at time: Date, appStateHistory: AppStateHistory) -> TimeInterval? {
        guard pendingResourcesStartDates.isEmpty else {
            return lastReturnedValue // No new value until all pending resources are completed
        }
        guard let latestResourceEndDate = latestResourceEndDate else {
            return nil // No resources were tracked
        }

        let ttnsValue = latestResourceEndDate.timeIntervalSince(viewStartDate)
        let viewLoadedDate = viewStartDate.addingTimeInterval(ttnsValue)

        guard viewLoadedDate >= viewStartDate else { // Sanity check to ensure valid time
            lastReturnedValue = nil
            return nil
        }

        // Check if app was in "active" state during the view loading period
        let viewLoadingAppStates = appStateHistory.take(between: viewStartDate...viewLoadedDate)
        let trackedInForeground = !(viewLoadingAppStates.snapshots.contains { $0.state != .active })

        guard trackedInForeground else {
            lastReturnedValue = nil
            return nil // The app was not always "active" during view loading
        }

        lastReturnedValue = ttnsValue
        return ttnsValue
    }
}
