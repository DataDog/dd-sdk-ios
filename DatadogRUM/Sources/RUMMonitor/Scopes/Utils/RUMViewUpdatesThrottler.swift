/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal protocol RUMViewUpdatesThrottlerType {
    func accept(event: RUMViewEvent) -> Bool
}

/// An utility suppressing the number of view updates sent for a single view.
///
/// It uses time-based heuristic for view updates throttling:
/// - it suppresses updates which happen more frequent than `viewUpdateThreshold`,
/// - it always samples (accepts) first and last update for the view.
internal final class RUMViewUpdatesThrottler: RUMViewUpdatesThrottlerType {
    struct Constants {
        /// Default suppression interval, in seconds.
        static let defaultViewUpdateThreshold: TimeInterval = 30.0
    }

    /// Suppression interval, in nanoseconds.
    private let viewUpdateThresholdInNs: Int64
    /// The `timeSpent` (in ns) from the last accepted view event.
    private var lastSampledTimeSpentInNs: Int64? = nil

    init(viewUpdateThreshold: TimeInterval = Constants.defaultViewUpdateThreshold) {
        self.viewUpdateThresholdInNs = viewUpdateThreshold.toInt64Nanoseconds
    }

    /// Based on the `viewUpdateThresholdInNs` and `viewUpdate.timeSpent`, it decides if an event should be "sampled" or not.
    /// - Returns: `true` if event should be sent to Datadog and `false` if it should be dropped.
    func accept(event: RUMViewEvent) -> Bool {
        var sample: Bool

        if let lastTimeSpent = lastSampledTimeSpentInNs {
            sample = (event.view.timeSpent - lastTimeSpent) >= viewUpdateThresholdInNs
        } else {
            sample = true // always accept the first event in a view
        }

        sample = sample || event.view.isActive == false // always accept the last event in a view

        sample = sample || event.view.crash.map { $0.count > 0 } ?? false

        if sample {
            lastSampledTimeSpentInNs = event.view.timeSpent
        }

        return sample
    }
}
