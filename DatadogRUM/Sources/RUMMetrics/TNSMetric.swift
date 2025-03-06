/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol TNSMetricTracking {
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

    /// Returns the value for the TNS metric.
    ///
    /// - Parameters:
    ///   - appStateHistory: The history of app state transitions.
    /// - Returns: The value for the TNS metric, or `nil` if the metric cannot be calculated.
    /// - Returns: The TNS metric value (`TimeInterval`) if successfully calculated, or a `TNSNoValueReason` indicating why the value is unavailable.
    func value(with appStateHistory: AppStateHistory) -> Result<TimeInterval, TNSNoValueReason>
}

/// Possible reasons for a missing TNS value.
/// This list is standardized according to the "RUM View Ended" metric specification.
internal enum TNSNoValueReason: String, Error {
    /// No resources were tracked at all while the view was active.
    case noTrackedResources = "no_resources"
    /// At least one resource was tracked, but none qualified as "initial" according to the predicate.
    case noInitialResources = "no_initial_resources"
    /// Not all "initial" resources have completed loading at the time this metric was requested.
    case initialResourcesIncomplete = "initial_resources_incomplete"
    /// The view stopped before all "initial" resources finished loading.
    case viewStoppedBeforeSettled = "not_settled_yet"
    /// The app was not in the foreground for the full duration of the view’s loading process.
    case appNotInForeground = "not_in_foreground"
    /// All "initial" resources were dropped and never completed.
    case initialResourcesDropped = "initial_resources_dropped"
    /// All "initial" resources were invalid (e.g., they started before the view’s start time or had a negative duration).
    case initialResourcesInvalid = "initial_resources_invalid"
    /// The calculated TNS value was invalid (e.g., it turned out negative).
    case invalidCalculatedValue = "invalid_value"
    /// An unknown error occurred; the metric is missing for a reason not captured above.
    case unknown = "unknown"
}

/// A metric (**Time-to-Network-Settled**, or TNS) that measures the time from when the view becomes visible until all initial resources are loaded.
/// "Initial resources" are now classified using a customizable predicate.
internal final class TNSMetric: TNSMetricTracking {
    /// Flag indicating if the view was stopped (no more resources accepted).
    private var isViewStopped: Bool = false
    /// Total number of resources (initial or not) started in this view.
    private var totalResourcesCount: Int = 0
    /// Number of initial resources tracked so far.
    private var initialResourcesCount: Int = 0
    /// Number of invalid initial resources (e.g., negative duration or started before view start).
    private var invalidInitialResourcesCount: Int = 0
    /// Number of dropped initial resources.
    private var droppedInitialResourcesCount: Int = 0
    /// Maps each pending **initial** resource to its start date.
    private var pendingInitialResources: [RUMUUID: Date] = [:]

    /// Tracks the maximum end-time (relative to `viewStartDate`) of **the current wave** of initial resources.
    /// Resets when all current pending resources finish or are dropped, finalizing a wave.
    private var maxResourceEndTime: TimeInterval?
    /// The finalized TNS value **from previously completed waves**. Each time a wave completes, we set that wave’s TNS to `latestCompletedTNSValue`.
    private var latestCompletedTNSValue: TimeInterval?

    /// The name of the view this metric is tracked for.
    private let viewName: String
    /// The time at which the view was started (device time, no NTP offset).
    private let viewStartDate: Date

    /// Classifies resources as "initial."
    private let resourcePredicate: NetworkSettledResourcePredicate

    // MARK: - Initialization

    init(viewName: String, viewStartDate: Date, resourcePredicate: NetworkSettledResourcePredicate) {
        self.viewName = viewName
        self.viewStartDate = viewStartDate
        self.resourcePredicate = resourcePredicate
    }

    // MARK: - TNSMetricTracking

    func trackResourceStart(at startDate: Date, resourceID: RUMUUID, resourceURL: String) {
        guard !isViewStopped else {
            return
        }

        totalResourcesCount += 1

        let resourceParams = TNSResourceParams(
            url: resourceURL,
            timeSinceViewStart: startDate.timeIntervalSince(viewStartDate),
            viewName: viewName
        )
        guard resourcePredicate.isInitialResource(from: resourceParams) else {
            return // Not an initial resource.
        }

        if startDate < viewStartDate {
            invalidInitialResourcesCount += 1
            return
        }

        initialResourcesCount += 1

        // If we previously completed a wave, but new initial resources are starting, we begin a new wave:
        if pendingInitialResources.isEmpty, latestCompletedTNSValue != nil {
            // Reset the `accumulatedEndTime` for the new wave.
            maxResourceEndTime = nil
        }

        pendingInitialResources[resourceID] = startDate
    }

    func trackResourceEnd(at endDate: Date, resourceID: RUMUUID, resourceDuration: TimeInterval?) {
        guard !isViewStopped else {
            return
        }

        // Only finalize if we had this resource as pending.
        guard let resourceStartDate = pendingInitialResources.removeValue(forKey: resourceID) else {
            return
        }

        let duration = resourceDuration ?? endDate.timeIntervalSince(resourceStartDate)
        guard duration >= 0 else {
            invalidInitialResourcesCount += 1
            return
        }

        let resourceEndTime = resourceStartDate.timeIntervalSince(viewStartDate) + duration
        if let current = maxResourceEndTime {
            maxResourceEndTime = max(current, resourceEndTime)
        } else {
            maxResourceEndTime = resourceEndTime
        }

        // If no pending resources remain, finalize this wave:
        if pendingInitialResources.isEmpty {
            finalizeWave()
        }
    }

    func trackResourceDropped(resourceID: RUMUUID) {
        guard !isViewStopped else {
            return
        }

        if pendingInitialResources.removeValue(forKey: resourceID) != nil {
            droppedInitialResourcesCount += 1
            // If that was the last resource in the wave, finalize.
            if pendingInitialResources.isEmpty {
                finalizeWave()
            }
        }
    }

    func trackViewWasStopped() {
        isViewStopped = true
    }

    func value(with appStateHistory: AppStateHistory) -> Result<TimeInterval, TNSNoValueReason> {
        // If we are loading a new wave (i.e., there are pending resources),
        // return the *last finalized* TNS if it exists.
        if !pendingInitialResources.isEmpty {
            // If there's a previously completed wave:
            if let oldTNS = latestCompletedTNSValue {
                return validate(tnsValue: oldTNS, with: appStateHistory)
            } else {
                // No wave has ever completed, so the metric is not available yet.
                return .failure(isViewStopped ? .viewStoppedBeforeSettled : .initialResourcesIncomplete)
            }
        }

        // If no resources are currently pending, we might have a new, finalized TNS from this wave:
        if let finalizedTNS = latestCompletedTNSValue {
            return validate(tnsValue: finalizedTNS, with: appStateHistory)
        }

        // Otherwise, we have no wave completed yet, so figure out why.
        return noValueReason()
    }

    // MARK: - Private

    /// Called when the current wave of pending resources has become empty (all completed or dropped).
    private func finalizeWave() {
        // If we actually got an end time for the wave, merge it with the latest completed TNS value.
        if let waveEndTime = maxResourceEndTime {
            if let existing = latestCompletedTNSValue {
                latestCompletedTNSValue = max(existing, waveEndTime)
            } else {
                latestCompletedTNSValue = waveEndTime
            }
        }
        maxResourceEndTime = nil // reset for the next wave
    }

    private func validate(tnsValue: TimeInterval, with appStateHistory: AppStateHistory) -> Result<TimeInterval, TNSNoValueReason> {
        guard tnsValue >= 0 else { // sanity check, this shouldn't happen
            return .failure(.invalidCalculatedValue)
        }

        // Check if the app stayed foregrounded through the resource load time.
        let loadingEndDate = viewStartDate.addingTimeInterval(tnsValue)
        let wasAlwaysForeground = !appStateHistory.containsState(during: viewStartDate...loadingEndDate) { $0 != .active }

        guard wasAlwaysForeground else {
            return .failure(.appNotInForeground)
        }

        return .success(tnsValue)
    }

    private func noValueReason() -> Result<TimeInterval, TNSNoValueReason> {
        // No resources at all
        if totalResourcesCount == 0 {
            return .failure(.noTrackedResources)
        }
        // No initial resources
        if initialResourcesCount == 0 {
            return .failure(.noInitialResources)
        }
        // Possibly all initial resources were invalid or dropped
        if invalidInitialResourcesCount == initialResourcesCount {
            return .failure(.initialResourcesInvalid)
        }
        if droppedInitialResourcesCount == initialResourcesCount {
            return .failure(.initialResourcesDropped)
        }

        // Otherwise, no final TNS is computed yet—unknown cause
        return .failure(.unknown)
    }
}
