/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct RUMViewEventsFilter {
    /// The initial `time_spent` value (1ns) is a placeholder set when a view starts.
    /// If not updated (e.g., due to app interruption), the view may remain at 1ns duration.
    /// This is especially problematic for sessions with only the initial view, so we filter out such cases (see RUM-10723).
    private let oneNanosecondDuration = RUMViewScope.Constants.minimumTimeSpent.dd.toInt64Nanoseconds

    let decoder: JSONDecoder
    let telemetry: Telemetry

    init(telemetry: Telemetry, decoder: JSONDecoder = JSONDecoder()) {
        self.telemetry = telemetry
        self.decoder = decoder
    }

    private enum FilterResult {
        /// Keep the view event in the batch.
        case keep
        /// Skip redundant full view events for the same view ID (RUMM-3151).
        /// When multiple full events for the same view exist, we only keep the latest one
        /// to optimize payload size. This applies to delta baselines too: once a newer full event
        /// of the view is kept, the older baseline and its dependent deltas are redundant.
        case skipRedundant
        /// Skip `RUMViewUpdateEvent` deltas superseded by a newer full event of the same view (RUM-13988).
        /// The newer full event already carries everything the delta did, and the backend would
        /// reject the delta as stale anyway.
        case skipSuperseded
        /// Skip initial view (indexInSession == 0) with 1ns duration (RUM-10723).
        /// Initial views start with a 1ns placeholder duration that gets updated as events arrive.
        /// If the app is interrupted before any events are tracked, the initial view
        /// would create a problematic 1ns session, so we filter it out.
        case skipInitialOneNs
    }

    /// Filters RUM view events to improve data quality and optimize payload size.
    ///
    /// Events are visited newest → oldest. Once a full view event is kept for a view, every earlier
    /// event of that view in the batch (full events, delta baselines and `RUMViewUpdateEvent` deltas)
    /// is superseded and dropped. Events after the newest kept full event are kept.
    func filter(events: [Event]) -> [Event] {
        var supersededViews = Set<String>()
        var redundantEventsCount = 0
        var supersededUpdatesCount = 0
        var initialOneNsEventsCount = 0

        // reversed is O(1) and no copy because it is view on the original array
        let filtered: [Event] = events.reversed().compactMap { event in
            do {
                let result = try filterEvent(event, supersededViews: &supersededViews)
                switch result {
                case .keep:
                    return event
                case .skipRedundant:
                    redundantEventsCount += 1
                    return nil
                case .skipSuperseded:
                    supersededUpdatesCount += 1
                    return nil
                case .skipInitialOneNs:
                    initialOneNsEventsCount += 1
                    return nil
                }
            } catch {
                telemetry.error("Failed to decode RUM view event metadata", error: error)
                return event
            }
        }

        if redundantEventsCount > 0 || supersededUpdatesCount > 0 || initialOneNsEventsCount > 0 {
            DD.logger.debug("RUMViewEventsFilter: skipped \(redundantEventsCount) redundant view updates, \(supersededUpdatesCount) superseded view update deltas, \(initialOneNsEventsCount) initial 1ns views")
        }

        return filtered.reversed()
    }

    /// - Parameter supersededViews: IDs of views for which a newer full event in this batch has been kept.
    private func filterEvent(_ event: Event, supersededViews: inout Set<String>) throws -> FilterResult {
        guard let metadata = event.metadata else {
            // If there is no metadata, we can't filter it.
            return .keep
        }

        let viewMetadata = try decoder.decode(RUMViewEvent.Metadata.self, from: metadata)

        if viewMetadata.hasAccessibility == true {
            // If this event has accessibility information, always keep it.
            // It does not supersede earlier events of the view.
            return .keep
        }

        if viewMetadata.isViewUpdate == true {
            // A delta is redundant once a newer full event of the same view is kept in this batch.
            return supersededViews.contains(viewMetadata.id) ? .skipSuperseded : .keep
        }

        if viewMetadata.duration == oneNanosecondDuration, viewMetadata.indexInSession == 0 {
            // Filter out initial 1ns views. Such event is never a delta baseline,
            // so it does not supersede earlier events of the view.
            return .skipInitialOneNs
        }

        guard supersededViews.contains(viewMetadata.id) == false else {
            // A newer full event of this view is kept, so this one (baseline or not) is redundant.
            return .skipRedundant
        }

        supersededViews.insert(viewMetadata.id)
        return .keep
    }
}
